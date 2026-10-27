import SwiftUI
import IOKit
import IOKit.usb

/// B5+：接口逐口实测。定时枚举 USB 设备并与上一帧差分，实时输出插入/拔出事件与速率，
/// 引导用户依次插入每个物理接口逐口验证。用轮询差分而非 C 回调桥接（避开 Swift 6 并发陷阱）。
@MainActor
final class PortLiveMonitor: ObservableObject {
    struct Event: Identifiable {
        let id = UUID()
        let time: String
        let inserted: Bool
        let name: String
        let speed: String
    }

    @Published var events: [Event] = []
    @Published var currentDevices: [String] = []
    @Published var isMonitoring = false

    private var previous: Set<String> = []
    private var timer: Timer?
    private var startedBaseline = false

    func start() {
        guard timer == nil else { return }
        isMonitoring = true
        // 先建立基线（当前已连接的设备不算"新插入"）
        previous = Set(Self.enumerate().map(\.key))
        startedBaseline = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        isMonitoring = false
    }

    func reset() {
        events.removeAll()
        previous = Set(Self.enumerate().map(\.key))
    }

    private func tick() {
        let now = Self.enumerate()
        let nowKeys = Set(now.map(\.key))
        let inserted = nowKeys.subtracting(previous)
        let removed = previous.subtracting(nowKeys)

        for key in inserted {
            if let dev = now.first(where: { $0.key == key }) {
                events.insert(Event(time: Self.timestamp(), inserted: true, name: dev.name, speed: dev.speed), at: 0)
            }
        }
        for key in removed {
            let name = key.components(separatedBy: "|").first ?? key
            events.insert(Event(time: Self.timestamp(), inserted: false, name: name, speed: ""), at: 0)
        }
        previous = nowKeys
        currentDevices = now.map { "\($0.name) · \($0.speed)" }
    }

    /// 事件数（插入）——用于统计验证了多少次接入。
    var insertCount: Int { events.filter(\.inserted).count }

    // MARK: - IOKit 枚举

    private struct Dev { let key: String; let name: String; let speed: String }

    private static func enumerate() -> [Dev] {
        usbDevices() + thunderboltDevices() + externalStorage()
    }

    private static func forEachService(_ className: String, _ body: (io_service_t) -> Void) {
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching(className),
              IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
        else { return }
        defer { IOObjectRelease(iterator) }
        var service = IOIteratorNext(iterator)
        while service != 0 {
            body(service)
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }

    /// USB 设备（现代 macOS 用 IOUSBHostDevice）。
    private static func usbDevices() -> [Dev] {
        var result: [Dev] = []
        forEachService("IOUSBHostDevice") { service in
            let name = stringProp(service, "USB Product Name")
                ?? stringProp(service, "Product Name")
                ?? registryName(service)
            guard let name, !name.isEmpty else { return }
            let speed = speedLabel(intProp(service, "Device Speed"))
            let locationID = intProp(service, "locationID") ?? 0
            // key 用 名称+locationID 保证不同口的同名设备也能区分
            result.append(Dev(key: "\(name)|usb\(locationID)", name: name, speed: speed))
        }
        return result
    }

    /// 雷电设备（issue #5：雷电 3/4 硬盘走 PCIe 隧道，不会出现在 USB 树里）。
    /// 每个雷电控制器自身是 Depth = 0 的根交换机，外接设备的 Depth ≥ 1。
    private static func thunderboltDevices() -> [Dev] {
        var result: [Dev] = []
        forEachService("IOThunderboltSwitch") { service in
            guard let depth = intProp(service, "Depth"), depth > 0 else { return }
            let vendor = stringProp(service, "Device Vendor Name") ?? ""
            let model = stringProp(service, "Device Model Name") ?? L("雷电设备", "Thunderbolt device")
            let name = [vendor, model].filter { !$0.isEmpty }.joined(separator: " ")
            let uid = (IORegistryEntryCreateCFProperty(service, "UID" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? NSNumber)?.stringValue ?? name
            result.append(Dev(key: "\(name)|tb\(uid)", name: name, speed: L("雷电 / Thunderbolt", "Thunderbolt")))
        }
        return result
    }

    /// 外置存储整盘（雷电 NVMe 硬盘盒、SD 卡等）。USB 存储已由 USB 树覆盖，这里跳过避免重复。
    private static func externalStorage() -> [Dev] {
        var result: [Dev] = []
        let parents = IOOptionBits(kIORegistryIterateRecursively | kIORegistryIterateParents)
        forEachService("IOMedia") { service in
            guard (IORegistryEntryCreateCFProperty(service, "Whole" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? Bool) == true,
                  let proto = IORegistryEntrySearchCFProperty(service, kIOServicePlane, "Protocol Characteristics" as CFString,
                                                              kCFAllocatorDefault, parents) as? [String: Any]
            else { return }
            let interconnect = proto["Physical Interconnect"] as? String ?? ""
            let location = proto["Physical Interconnect Location"] as? String ?? ""
            let isSDCard = interconnect == "Secure Digital"
            guard (location == "External" || isSDCard), interconnect != "USB" else { return }
            let device = IORegistryEntrySearchCFProperty(service, kIOServicePlane, "Device Characteristics" as CFString,
                                                         kCFAllocatorDefault, parents) as? [String: Any]
            let product = (device?["Product Name"] as? String)?.trimmingCharacters(in: .whitespaces)
            var name = (product?.isEmpty == false ? product : nil) ?? L("外置硬盘", "External disk")
            if let size = intProp(service, "Size"), size > 0 {
                name += " · " + ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .decimal)
            }
            let bsd = stringProp(service, "BSD Name") ?? name
            let speed = isSDCard ? L("SD 读卡器", "SD card reader")
                : interconnect.isEmpty ? L("外置存储", "External storage") : interconnect
            result.append(Dev(key: "\(name)|disk\(bsd)", name: name, speed: speed))
        }
        return result
    }

    private static func stringProp(_ service: io_service_t, _ key: String) -> String? {
        guard let cf = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) else { return nil }
        return cf.takeRetainedValue() as? String
    }

    private static func intProp(_ service: io_service_t, _ key: String) -> Int? {
        guard let cf = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0) else { return nil }
        return (cf.takeRetainedValue() as? NSNumber)?.intValue
    }

    private static func registryName(_ service: io_service_t) -> String? {
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: 128)
        defer { buffer.deallocate() }
        guard IORegistryEntryGetName(service, buffer) == KERN_SUCCESS else { return nil }
        return String(cString: buffer)
    }

    private static func speedLabel(_ speed: Int?) -> String {
        switch speed {
        case 0: return L("USB 1.0 低速", "USB 1.0 Low Speed")
        case 1: return L("USB 1.1 全速", "USB 1.1 Full Speed")
        case 2: return L("USB 2.0 高速", "USB 2.0 High Speed")
        case 3: return "USB 3.0 (5 Gbps)"
        case 4: return "USB 3.1 (10 Gbps)"
        case 5: return "USB 3.2 (20 Gbps)"
        default: return L("未知速率", "Unknown speed")
        }
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: Date())
    }
}

struct PortLiveCheckView: View {
    @StateObject private var monitor = PortLiveMonitor()
    let onComplete: (CheckResult) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            CheckHeader(
                icon: "cable.connector.horizontal",
                title: L("接口逐口实测", "Port-by-Port Test"),
                subtitle: L("依次把 U 盘/读卡器/线缆插入每一个 USB-C 或读卡器接口，下方会实时显示接入的设备与速率。逐口都能识别即说明接口正常。",
                            "Plug a USB drive, card reader or cable into each USB-C port or card slot in turn. Connected devices and their speeds show up below in real time. If every port is recognized, the ports work.")
            )

            Card {
                HStack {
                    Circle().fill(monitor.isMonitoring ? .green : .secondary).frame(width: 8, height: 8)
                    Text(monitor.isMonitoring ? L("监听中，请插入设备…", "Listening — plug in a device…") : L("未开始", "Not started"))
                        .font(DS.Font.body).foregroundStyle(.secondary)
                    Spacer()
                    Text(L("已捕获接入 \(monitor.insertCount) 次", "\(monitor.insertCount) connections detected")).font(DS.Font.caption).foregroundStyle(.secondary)
                }
                if monitor.events.isEmpty {
                    Text(L("暂无插拔事件", "No plug/unplug events yet")).font(DS.Font.caption).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, DS.Spacing.md)
                } else {
                    ForEach(monitor.events.prefix(12)) { e in
                        HStack(spacing: DS.Spacing.sm) {
                            Image(systemName: e.inserted ? "arrow.down.circle.fill" : "arrow.up.circle")
                                .foregroundStyle(e.inserted ? .green : .secondary)
                            Text(e.time).font(DS.Font.mono).foregroundStyle(.secondary)
                            Text(e.inserted ? L("接入", "Connected") : L("拔出", "Removed")).font(DS.Font.bodyEmphasis)
                            Text(e.name).font(DS.Font.body).lineLimit(1)
                            Spacer()
                            if !e.speed.isEmpty {
                                Text(e.speed).font(DS.Font.caption).foregroundStyle(.blue)
                            }
                        }
                    }
                }
            }

            DS.Divider()

            HStack(spacing: DS.Spacing.md) {
                if monitor.isMonitoring {
                    Button(L("停止监听", "Stop Listening")) { monitor.stop() }.buttonStyle(.bordered)
                    Button(L("清除记录", "Clear Log")) { monitor.reset() }.buttonStyle(.bordered)
                } else {
                    Button(L("开始监听", "Start Listening")) { monitor.start() }.buttonStyle(.borderedProminent)
                }
                Spacer()
                Button(L("每个接口都识别正常", "Every Port Works")) {
                    finish(pass: true)
                }.buttonStyle(.borderedProminent).disabled(monitor.insertCount == 0)
                Button(L("有接口无反应", "A Port Didn't Respond")) { finish(pass: false) }.buttonStyle(.bordered)
            }
        }
        .padding(DS.Spacing.xl)
        .checkPane(L("接口逐口实测", "Port-by-Port Test"))
        .onDisappear { monitor.stop() }
    }

    private func finish(pass: Bool) {
        monitor.stop()
        let names = monitor.events.filter(\.inserted).map { "\($0.name) (\($0.speed))" }
        onComplete(CheckResult(
            id: "portsLive",
            title: L("接口逐口实测", "Port-by-Port Test"),
            status: pass ? .pass : .warning,
            summary: pass
                ? L("共捕获 \(monitor.insertCount) 次接入，接口通信正常", "\(monitor.insertCount) connections detected; ports communicate normally")
                : L("用户反馈有接口无反应，建议重点复测该接口", "User reported a port that didn't respond; retest that port"),
            rawDetails: names.isEmpty ? [:] : [L("接入设备记录", "Connected devices"): names.joined(separator: L("；", "; "))]
        ))
    }
}
