import Foundation
import CoreWLAN

/// A8/B7-8：无线连接。Wi-Fi 当前连接信息走 CoreWLAN（原生框架），蓝牙控制器状态走 system_profiler。
enum NetworkService {

    // MARK: - Wi-Fi

    private static func wifiResult() -> CheckResult {
        guard let iface = CWWiFiClient.shared().interface() else {
            return CheckResult(
                id: "network.wifi",
                title: "Wi-Fi",
                status: .unsupported,
                summary: "未检测到 Wi-Fi 网卡"
            )
        }

        var details: [String: String] = [:]
        let powerOn = iface.powerOn()
        details["Wi-Fi 开关"] = powerOn ? "已开启" : "已关闭"
        if let hw = iface.hardwareAddress() { details["网卡 MAC"] = hw }

        if let ssid = iface.ssid() {
            details["当前网络"] = ssid
            let rssi = iface.rssiValue()
            details["信号强度(RSSI)"] = "\(rssi) dBm"
            details["发射速率"] = "\(iface.transmitRate()) Mbps"
            details["频段"] = phyModeString(iface.activePHYMode())
            let quality = rssi >= -60 ? "信号良好" : (rssi >= -75 ? "信号一般" : "信号偏弱")
            return CheckResult(
                id: "network.wifi",
                title: "Wi-Fi",
                status: .pass,
                summary: "已连接「\(ssid)」· \(rssi) dBm · \(quality)",
                rawDetails: details
            )
        }

        return CheckResult(
            id: "network.wifi",
            title: "Wi-Fi",
            status: powerOn ? .pass : .warning,
            summary: powerOn ? "Wi-Fi 已开启但未连接网络，网卡工作正常" : "Wi-Fi 当前处于关闭状态",
            rawDetails: details
        )
    }

    private static func phyModeString(_ mode: CWPHYMode) -> String {
        switch mode {
        case .mode11a: return "802.11a"
        case .mode11b: return "802.11b"
        case .mode11g: return "802.11g"
        case .mode11n: return "802.11n (Wi-Fi 4)"
        case .mode11ac: return "802.11ac (Wi-Fi 5)"
        case .mode11ax: return "802.11ax (Wi-Fi 6/6E)"
        case .modeNone: return "未连接"
        @unknown default: return "未知"
        }
    }

    // MARK: - 蓝牙

    private static func bluetoothResult() -> CheckResult {
        let output = ShellRunner.run("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"])
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["SPBluetoothDataType"] as? [[String: Any]],
              let first = items.first,
              let ctrl = first["controller_properties"] as? [String: Any]
        else {
            return CheckResult(
                id: "network.bluetooth",
                title: "蓝牙",
                status: .warning,
                summary: "未能读取蓝牙控制器状态"
            )
        }

        let state = (ctrl["controller_state"] as? String) ?? ""
        let chipset = (ctrl["controller_chipset"] as? String) ?? ""
        let address = (ctrl["controller_address"] as? String) ?? ""
        let isOn = state.contains("on")

        var details: [String: String] = [
            "控制器状态": isOn ? "已开启" : "已关闭",
            "蓝牙芯片": chipset,
            "蓝牙地址": address,
        ]
        if let connected = first["device_connected"] as? [[String: Any]] {
            details["已连接设备数"] = "\(connected.count)"
        }

        return CheckResult(
            id: "network.bluetooth",
            title: "蓝牙",
            status: isOn ? .pass : .warning,
            summary: isOn ? "蓝牙控制器正常工作（\(chipset)）" : "蓝牙当前处于关闭状态，无法验证射频",
            rawDetails: details
        )
    }

    static func runAll() -> [CheckResult] {
        [wifiResult(), bluetoothResult()]
    }
}
