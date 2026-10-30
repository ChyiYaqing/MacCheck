import Foundation

// MacCheckWatchHelper：经由 iPhone 的 companion_proxy 服务读取配对 Apple Watch 的注册信息。
// 用法：MacCheckWatchHelper <iPhone UDID>，stdout 输出 XML plist 数组，每块手表一个字典（键同 lockdownd）。
//
// libimobiledevice 没有对应的命令行工具，只能运行时 dlopen Homebrew 的动态库：Homebrew 库与 App 签名不同，
// hardened runtime 的库验证会拒绝加载，所以单独放进这个关闭了库验证的辅助程序，主 App 保留库验证，
// Homebrew 的代码只在子进程里运行（和调用 ideviceinfo 一样），且本进程不持有摄像头 / 麦克风权限。

/// companion_proxy 能返回的键（实测 watchOS 26）；电池健康度、循环次数、存储、激活状态会返回"不支持的键"。
let keys = [
    "ProductType", "ProductVersion", "BuildVersion", "DeviceName", "SerialNumber",
    "ModelNumber", "RegionInfo", "HardwareModel", "BatteryCurrentCapacity", "BatteryIsCharging",
    "UniqueDeviceID", "WiFiAddress", "BluetoothAddress",
]

struct Library {
    typealias NewDevice = @convention(c) (UnsafeMutablePointer<OpaquePointer?>, UnsafePointer<CChar>?, Int32) -> Int32
    typealias FreeHandle = @convention(c) (OpaquePointer?) -> Int32
    typealias StartService = @convention(c) (OpaquePointer?, UnsafeMutablePointer<OpaquePointer?>, UnsafePointer<CChar>?) -> Int32
    typealias GetRegistry = @convention(c) (OpaquePointer?, UnsafeMutablePointer<OpaquePointer?>) -> Int32
    typealias GetValue = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?, UnsafeMutablePointer<OpaquePointer?>) -> Int32
    typealias ToXML = @convention(c) (OpaquePointer?, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>, UnsafeMutablePointer<UInt32>) -> Int32
    typealias PlistFree = @convention(c) (OpaquePointer?) -> Void
    typealias MemFree = @convention(c) (UnsafeMutableRawPointer?) -> Void

    let newDevice: NewDevice
    let freeDevice: FreeHandle
    let startService: StartService
    let freeClient: FreeHandle
    let getRegistry: GetRegistry
    let getValue: GetValue
    let toXML: ToXML
    let plistFree: PlistFree
    let memFree: MemFree

    /// 与 ideviceinfo 等命令行工具同一套 Homebrew 前缀（Apple Silicon / Intel）。
    static func load() -> Library? {
        func open(_ name: String) -> UnsafeMutableRawPointer? {
            ["/opt/homebrew/lib", "/usr/local/lib"].lazy.compactMap { dlopen("\($0)/\(name)", RTLD_NOW) }.first
        }
        guard let device = open("libimobiledevice-1.0.dylib"), let plist = open("libplist-2.0.dylib") else { return nil }
        func symbol<T>(_ handle: UnsafeMutableRawPointer, _ name: String, as _: T.Type) -> T? {
            dlsym(handle, name).map { unsafeBitCast($0, to: T.self) }
        }
        guard let newDevice = symbol(device, "idevice_new_with_options", as: NewDevice.self),
              let freeDevice = symbol(device, "idevice_free", as: FreeHandle.self),
              let startService = symbol(device, "companion_proxy_client_start_service", as: StartService.self),
              let freeClient = symbol(device, "companion_proxy_client_free", as: FreeHandle.self),
              let getRegistry = symbol(device, "companion_proxy_get_device_registry", as: GetRegistry.self),
              let getValue = symbol(device, "companion_proxy_get_value_from_registry", as: GetValue.self),
              let toXML = symbol(plist, "plist_to_xml", as: ToXML.self),
              let plistFree = symbol(plist, "plist_free", as: PlistFree.self),
              let memFree = symbol(plist, "plist_mem_free", as: MemFree.self)
        else { return nil }
        return Library(newDevice: newDevice, freeDevice: freeDevice, startService: startService, freeClient: freeClient,
                       getRegistry: getRegistry, getValue: getValue, toXML: toXML, plistFree: plistFree, memFree: memFree)
    }

    /// iPhone 回复一次请求后就关闭 companion_proxy 连接，所以每个请求都新建连接。返回解析后的 plist。
    func request(udid: String, _ body: (OpaquePointer?, UnsafeMutablePointer<OpaquePointer?>) -> Int32) -> Any? {
        var device: OpaquePointer?
        guard newDevice(&device, udid, 1 /* IDEVICE_LOOKUP_USBMUX */) == 0 else { return nil }
        defer { _ = freeDevice(device) }
        var client: OpaquePointer?
        guard startService(device, &client, "MacCheck") == 0 else { return nil }
        defer { _ = freeClient(client) }
        var result: OpaquePointer?
        guard body(client, &result) == 0, let result else { return nil }
        defer { plistFree(result) }
        var xml: UnsafeMutablePointer<CChar>?
        var length: UInt32 = 0
        guard toXML(result, &xml, &length) == 0, let xml else { return nil }
        defer { memFree(xml) }
        return try? PropertyListSerialization.propertyList(from: Data(bytes: xml, count: Int(length)), format: nil)
    }
}

guard CommandLine.arguments.count == 2, let lib = Library.load() else { exit(1) }
let iPhoneUDID = CommandLine.arguments[1]
let registry = lib.request(udid: iPhoneUDID) { client, out in lib.getRegistry(client, out) } as? [String] ?? []
let watches: [[String: Any]] = registry.map { watchUDID in
    var info: [String: Any] = ["UniqueDeviceID": watchUDID]
    for key in keys {
        let reply = lib.request(udid: iPhoneUDID) { client, out in lib.getValue(client, watchUDID, key, out) } as? [String: Any]
        if let value = reply?[key] { info[key] = value }
    }
    return info
}
guard let data = try? PropertyListSerialization.data(fromPropertyList: watches, format: .xml, options: 0) else { exit(1) }
FileHandle.standardOutput.write(data)
