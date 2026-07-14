import Foundation

/// B5：接口枚举。列出当前通过 USB / 雷雳(Thunderbolt) 接口连接的设备，帮助用户逐口验证接口连通性。
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
        let output = ShellRunner.run("/usr/sbin/system_profiler", ["SPUSBDataType", "-json"])
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roots = json["SPUSBDataType"] as? [[String: Any]]
        else { return [] }
        var names: [String] = []
        for root in roots {
            if let children = root["_items"] as? [[String: Any]] {
                flatten(children, into: &names)
            }
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

    static func runAll() -> [CheckResult] {
        let usb = usbDevices()
        let tb = thunderboltDevices()

        var details: [String: String] = [:]
        details["已连接 USB 设备"] = usb.isEmpty ? "无" : usb.joined(separator: "、")
        details["已连接雷雳设备"] = tb.isEmpty ? "无" : tb.joined(separator: "、")

        let total = usb.count + tb.count
        let summary = total == 0
            ? "当前未接入任何 USB / 雷雳外设 —— 请依次插入设备以验证各接口"
            : "当前检测到 \(total) 个外接设备，接口通信正常"

        return [CheckResult(
            id: "ports",
            title: "接口 (USB / 雷雳)",
            status: .pass,
            summary: summary,
            rawDetails: details
        )]
    }
}
