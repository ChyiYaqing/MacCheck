import Foundation
import AppKit
import CoreGraphics
import IOKit

/// B5：接口枚举。列出 USB / 雷雳设备与外接显示器，帮助用户逐口验证接口连通性。
/// 说明：这是"当前接了什么"的快照。要完整验证每个物理口，用户需依次插拔，配合首页的实时提示。
enum PortService {

    private static func flatten(_ items: [[String: Any]], into names: inout [String]) {
        for item in items {
            if let name = item["_name"] as? String {
                // 过滤掉纯 Hub/控制器根节点噪声，保留具名设备
                names.append(name)
            }
            if let children = item["_items"] as? [[String: Any]] {
                flatten(children, into: &names)
            }
        }
    }

    private static func usbDevices() -> [String] {
        // system_profiler can return an empty USB tree despite connected devices.
        // Enumerate all host devices, including hubs and their downstream devices.
        var iterator: io_iterator_t = 0
        guard let matching = IOServiceMatching("IOUSBHostDevice"),
              IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iterator) }
        var names: [String] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            let productNames = ["USB Product Name", "Product Name"].compactMap { key -> String? in
                guard let value = IORegistryEntryCreateCFProperty(
                    service, key as CFString, kCFAllocatorDefault, 0
                )?.takeRetainedValue() as? String else { return nil }
                let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return name.isEmpty ? nil : name
            }
            var buffer = [CChar](repeating: 0, count: 128)
            let registryName = IORegistryEntryGetName(service, &buffer) == KERN_SUCCESS
                ? String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) : ""
            names.append(productNames.first ?? (registryName.isEmpty ? L("USB 设备", "USB device") : registryName))
        }
        return names
    }

    private static func thunderboltDevices() -> [String] {
        let output = ShellRunner.run("/usr/sbin/system_profiler", ["SPThunderboltDataType", "-json"])
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roots = json["SPThunderboltDataType"] as? [[String: Any]]
        else { return [] }
        // 雷雳总线本身会作为根节点出现，只统计挂在总线下的外接设备
        var names: [String] = []
        for root in roots {
            if let children = root["_items"] as? [[String: Any]] {
                flatten(children, into: &names)
            }
        }
        return names
    }

    @MainActor
    static func externalDisplays() -> [String] {
        // Online list also includes mirrored displays that NSScreen.screens may omit.
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) == 0 }.map { id in
            NSScreen.screens.first {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
            }?.localizedName ?? L("外接显示器 \(id)", "External display \(id)")
        }
    }

    static func portResult(usb: [String], thunderbolt tb: [String], displays: [String]) -> CheckResult {

        var details: [String: String] = [:]
        details[L("已连接 USB 设备", "Connected USB devices")] = usb.isEmpty ? L("无", "None") : usb.joined(separator: "\n")
        details[L("已连接雷雳设备", "Connected Thunderbolt devices")] = tb.isEmpty ? L("无", "None") : tb.joined(separator: L("、", ", "))
        details[L("已连接外接显示器", "Connected external displays")] = displays.isEmpty ? L("无", "None") : displays.joined(separator: L("、", ", "))

        let total = usb.count + tb.count + displays.count
        let summary = total == 0
            ? L("未检测到 USB / 雷雳设备或外接显示器，请依次插入设备以验证各接口", "No USB, Thunderbolt devices or external displays detected; plug a device into each port in turn to test it")
            : L("检测到 USB 设备 \(usb.count) 个、雷雳设备 \(tb.count) 个、外接显示器 \(displays.count) 台", "Detected \(usb.count) USB device(s), \(tb.count) Thunderbolt device(s), \(displays.count) external display(s)")

        return CheckResult(
            id: "ports",
            title: L("接口 (USB / 雷雳 / 显示器)", "Ports (USB / Thunderbolt / Displays)"),
            status: .pass,
            summary: summary,
            rawDetails: details
        )
    }

    static func runAll() -> [CheckResult] {
        let displays: [String]
        if Thread.isMainThread {
            displays = MainActor.assumeIsolated { externalDisplays() }
        } else {
            // Scans run in AppModel's detached task; NSScreen must be read on the main thread.
            displays = DispatchQueue.main.sync { externalDisplays() }
        }
        return [portResult(usb: usbDevices(), thunderbolt: thunderboltDevices(), displays: displays)]
    }
}
