import Foundation

/// 已连接设备的摘要：名称（用户在设备上设的，如 "chyi 的 iPhone"）+ 机型与系统版本。
struct IOSDeviceSummary: Sendable, Hashable {
    enum Kind: Sendable { case iPhone, iPad, watch }

    let udid: String
    let name: String
    let subtitle: String   // "iPhone 13 · iOS 18.1"
    let kind: Kind

    /// 按型号标识前缀判断设备类型（iPod touch 归入 iPhone）。
    static func kind(of productType: String) -> Kind {
        if productType.hasPrefix("iPad") { return .iPad }
        if productType.hasPrefix("Watch") { return .watch }
        return .iPhone
    }

    static func osName(of kind: Kind) -> String {
        switch kind {
        case .iPhone: return "iOS"
        case .iPad: return "iPadOS"
        case .watch: return "watchOS"
        }
    }

    var symbolName: String {
        switch kind {
        case .iPhone: return "iphone"
        case .iPad: return "ipad"
        case .watch: return "applewatch"
        }
    }
}

/// iPhone / iPad 验机：USB 连接后调用 libimobiledevice 命令行（`brew install libimobiledevice`）
/// 读取 lockdownd 公开的设备信息。和 Mac 端检测一样只走本地，不联网。
enum IOSDeviceService {

    /// Apple Silicon 与 Intel 的 Homebrew 前缀。
    private static let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin"]

    static func toolPath(_ name: String) -> String? {
        searchPaths.map { "\($0)/\(name)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var isToolInstalled: Bool {
        toolPath("idevice_id") != nil && toolPath("ideviceinfo") != nil
    }

    /// USB 连接的设备 UDID 列表。
    static func connectedUDIDs() -> [String] {
        guard let tool = toolPath("idevice_id") else { return [] }
        return parseUDIDs(ShellRunner.run(tool, ["-l"]))
    }

    static func parseUDIDs(_ output: String) -> [String] {
        var seen = Set<String>()
        return output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// 侧边栏用的设备摘要。`-s` 简单连接不触发配对，设备尚未信任这台 Mac 时也能读到。
    static func summary(udid: String) -> IOSDeviceSummary {
        let info = toolPath("ideviceinfo").map { plist(ShellRunner.run($0, ["-u", udid, "-s", "-x"])) } ?? [:]
        return summary(udid: udid, info: info)
    }

    static func summary(udid: String, info: [String: Any]) -> IOSDeviceSummary {
        let productType = info["ProductType"] as? String ?? ""
        let kind = IOSDeviceSummary.kind(of: info["DeviceClass"] as? String ?? productType)
        let model = IOSDeviceNaming.marketingName(productType)
        let version = info["ProductVersion"] as? String ?? ""
        let name = info["DeviceName"] as? String ?? ""
        return IOSDeviceSummary(
            udid: udid,
            name: name.isEmpty ? (model.isEmpty ? udid : model) : name,
            subtitle: [model, version.isEmpty ? "" : "\(IOSDeviceSummary.osName(of: kind)) \(version)"]
                .filter { !$0.isEmpty }.joined(separator: " · "),
            kind: kind
        )
    }

    /// 读取一台设备的档案与检测结果。返回 nil 表示设备尚未信任这台 Mac（lockdownd 拒绝连接，
    /// 此时 ideviceinfo 会在设备上弹出「要信任此电脑吗？」）。
    static func scan(udid: String) -> (DeviceProfile, [CheckResult])? {
        guard let infoTool = toolPath("ideviceinfo") else { return nil }
        let info = plist(ShellRunner.run(infoTool, ["-u", udid, "-x"]))
        guard !info.isEmpty else { return nil }
        var disk = plist(ShellRunner.run(infoTool, ["-u", udid, "-q", "com.apple.disk_usage", "-x"]))
        // 设备刚插入时 disk_usage 偶尔返回空（实测 iPad mini 4），稍等重试一次
        if disk["TotalDiskCapacity"] == nil {
            Thread.sleep(forTimeInterval: 1)
            disk = plist(ShellRunner.run(infoTool, ["-u", udid, "-q", "com.apple.disk_usage", "-x"]))
        }
        let chaperone = plist(ShellRunner.run(infoTool, ["-u", udid, "-q", "com.apple.mobile.chaperone", "-x"]))
        let battery = batteryRegistry(udid: udid)
        return (profile(info: info, disk: disk), results(info: info, disk: disk, chaperone: chaperone, battery: battery))
    }

    /// 电池循环次数/容量只在 IORegistry 里，走 diagnostics relay 服务读取；设备锁屏时该服务拒绝连接，返回空。
    private static func batteryRegistry(udid: String) -> [String: Any] {
        guard let tool = toolPath("idevicediagnostics") else { return [:] }
        for entry in ["AppleSmartBattery", "AppleARMPMUCharger"] {
            let output = plist(ShellRunner.run(tool, ["-u", udid, "ioregentry", entry]))
            if let registry = output["IORegistry"] as? [String: Any], registry["CycleCount"] != nil {
                return registry
            }
        }
        return [:]
    }

    static func plist(_ xml: String) -> [String: Any] {
        guard let data = xml.data(using: .utf8),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [:] }
        return dict
    }

    // MARK: - 档案

    /// 导出报告复用 Mac 的 DeviceProfile：chip 位放型号号码（如 "MK8D2LL/A"），memory 位放存储容量。
    static func profile(info: [String: Any], disk: [String: Any]) -> DeviceProfile {
        let productType = info["ProductType"] as? String ?? ""
        let version = info["ProductVersion"] as? String ?? ""
        let build = info["BuildVersion"] as? String ?? ""
        let osName = IOSDeviceSummary.osName(of: IOSDeviceSummary.kind(of: productType))
        return DeviceProfile(
            marketingName: IOSDeviceNaming.marketingName(productType),
            modelIdentifier: productType,
            chip: modelNumber(info),
            memory: (disk["TotalDiskCapacity"] as? Int).map(formatBytes) ?? "",
            macOSVersion: build.isEmpty ? "\(osName) \(version)" : "\(osName) \(version) (\(build))",
            serialNumber: info["SerialNumber"] as? String ?? "",
            architecture: info["CPUArchitecture"] as? String ?? "",
            modelYear: "",
            productionDate: ""
        )
    }

    private static func modelNumber(_ info: [String: Any]) -> String {
        (info["ModelNumber"] as? String ?? "") + (info["RegionInfo"] as? String ?? "")
    }

    /// 厂商口径的十进制容量：128000000000 → "128 GB"。
    static func formatBytes(_ bytes: Int) -> String {
        let gb = Double(bytes) / 1_000_000_000
        if gb >= 1000 { return String(format: "%.0f TB", gb / 1000) }
        return gb >= 100 ? String(format: "%.0f GB", gb) : String(format: "%.1f GB", gb)
    }

    // MARK: - 检测结果

    static func results(info: [String: Any], disk: [String: Any], chaperone: [String: Any], battery: [String: Any]) -> [CheckResult] {
        [
            identityResult(info),
            modelNumberResult(info),
            activationResult(info),
            findMyResult(),
            supervisionResult(chaperone),
        ] + batteryResults(battery) + [storageResult(disk)]
    }

    static func identityResult(_ info: [String: Any]) -> CheckResult {
        let serial = info["SerialNumber"] as? String ?? ""
        var details: [String: String] = [:]
        let keys: [(String, String)] = [
            ("SerialNumber", L("序列号", "Serial number")),
            ("InternationalMobileEquipmentIdentity", "IMEI"),
            ("InternationalMobileEquipmentIdentity2", "IMEI 2"),
            ("MLBSerialNumber", L("主板序列号", "Logic board serial")),
            ("UniqueDeviceID", "UDID"),
            ("WiFiAddress", L("Wi-Fi 地址", "Wi-Fi address")),
            ("BluetoothAddress", L("蓝牙地址", "Bluetooth address")),
        ]
        for (key, label) in keys {
            if let value = info[key] as? String, !value.isEmpty { details[label] = value }
        }
        return CheckResult(
            id: "ios.identity",
            title: details["IMEI"] == nil ? L("序列号", "Serial number") : L("序列号与 IMEI", "Serial number & IMEI"),
            status: serial.isEmpty ? .warning : .pass,
            summary: serial.isEmpty
                ? L("未能读取序列号", "Couldn't read the serial number")
                : L("序列号 \(serial)，请与包装盒、设置 > 通用 > 关于本机里的序列号核对一致", "Serial number \(serial). Make sure it matches the box and Settings > General > About."),
            rawDetails: details
        )
    }

    /// 型号号码首字母代表销售渠道：M 零售、F 官方翻新、N 售后换机、P 刻字定制。
    static func modelNumberResult(_ info: [String: Any]) -> CheckResult {
        let number = modelNumber(info)
        let region = info["RegionInfo"] as? String ?? ""
        let regionName = regionNames[region].map { L($0.0, $0.1) } ?? region
        let status: CheckStatus
        let channel: String
        switch number.first {
        case "M": status = .pass; channel = L("零售机（全新正品渠道）", "retail unit (sold new)")
        case "P": status = .pass; channel = L("刻字定制机（官网定制刻字购买）", "personalized unit (engraved, bought online)")
        case "F": status = .warning; channel = L("官方翻新机，品质有保障，但应按翻新机价格议价", "Apple Certified Refurbished; fine quality, but price it as refurbished")
        case "N": status = .warning; channel = L("售后换机（Apple 维修时替换的整机），不是原始零售机", "replacement unit issued by Apple service, not the original retail unit")
        default: status = .warning; channel = L("未知渠道", "unknown channel")
        }
        var details = [L("型号号码", "Model number"): number.isEmpty ? "N/A" : number]
        if !region.isEmpty { details[L("销售地区", "Sales region")] = regionName }
        return CheckResult(
            id: "ios.modelNumber",
            title: L("销售渠道", "Sales channel"),
            status: status,
            summary: L("\(number) —— \(channel)", "\(number) — \(channel)") + (regionName.isEmpty ? "" : L("，\(regionName)版", ", \(regionName) model")),
            rawDetails: details
        )
    }

    private static let regionNames: [String: (String, String)] = [
        "CH/A": ("中国大陆", "Mainland China"),
        "ZP/A": ("中国香港/澳门", "Hong Kong/Macau"),
        "TA/A": ("中国台湾", "Taiwan"),
        "LL/A": ("美国", "US"),
        "J/A": ("日本", "Japan"),
        "KH/A": ("韩国", "Korea"),
        "B/A": ("英国", "UK"),
        "X/A": ("澳大利亚", "Australia"),
        "C/A": ("加拿大", "Canada"),
        "ZA/A": ("新加坡", "Singapore"),
    ]

    private static func activationResult(_ info: [String: Any]) -> CheckResult {
        let state = info["ActivationState"] as? String ?? ""
        let activated = state == "Activated"
        return CheckResult(
            id: "ios.activation",
            title: L("激活状态", "Activation"),
            status: activated ? .pass : .warning,
            summary: activated
                ? L("设备已激活", "Device is activated")
                : L("设备未激活（\(state.isEmpty ? "未知" : state)），开机后若出现激活锁界面，需原机主的 Apple 账户才能解锁", "Device isn't activated (\(state.isEmpty ? "unknown" : state)). If it shows an Activation Lock screen at setup, only the previous owner's Apple Account can unlock it."),
            rawDetails: ["ActivationState": state.isEmpty ? "N/A" : state]
        )
    }

    /// lockdownd 不公开「查找」开关状态，只能提示人工确认。
    private static func findMyResult() -> CheckResult {
        CheckResult(
            id: "ios.findMy",
            title: L("查找 / 激活锁", "Find My / Activation Lock"),
            status: .unsupported,
            summary: L("USB 无法读取「查找」状态。请在设备「设置 > Apple 账户 > 查找」确认已关闭，并当面让卖家退出 Apple 账户。", "Find My status can't be read over USB. Check Settings > Apple Account > Find My on the device is off, and have the seller sign out of their Apple Account in front of you.")
        )
    }

    static func supervisionResult(_ chaperone: [String: Any]) -> CheckResult {
        let supervised = chaperone["DeviceIsChaperoned"] as? Bool ?? false
        return CheckResult(
            id: "ios.supervision",
            title: L("监管 / 设备管理", "Supervision / MDM"),
            status: supervised ? .redFlag : .pass,
            summary: supervised
                ? L("设备处于受监管状态，属于企业或学校管理的设备", "The device is supervised: it's managed by a company or school")
                : L("未检测到监管，不是企业/学校管理的设备", "Not supervised; not managed by a company or school"),
            rawDetails: ["DeviceIsChaperoned": supervised ? "true" : "false"],
            isRedFlagHeadline: supervised
                ? L("⛔ 这台设备受企业或学校监管，管理方可以远程锁定、抹掉或限制功能，刷机也无法解除。除非能拿到管理方的释放证明，否则不建议购买。", "⛔ This device is supervised by a company or school. The organization can remotely lock, erase or restrict it, and restoring it won't remove that. Don't buy it unless the organization confirms it has been released.")
                : nil
        )
    }

    /// 较新系统（实测 iOS 27）把容量字段挪进了 `BatteryData` 子字典，顶层只剩 CycleCount 等少数键；两层合并，顶层优先。
    private static func batteryFields(_ registry: [String: Any]) -> [String: Any] {
        (registry["BatteryData"] as? [String: Any] ?? [:]).merging(registry) { _, top in top }
    }

    static func batteryResults(_ registry: [String: Any]) -> [CheckResult] {
        let fields = batteryFields(registry)
        guard let cycles = fields["CycleCount"] as? Int else {
            return [CheckResult(
                id: "ios.battery",
                title: L("电池", "Battery"),
                status: .unsupported,
                summary: L("未能读取电池数据：请解锁设备屏幕后点「重新检测」", "Couldn't read battery data. Unlock the device screen, then click Check Again.")
            )]
        }

        let design = fields["DesignCapacity"] as? Int ?? 0
        let full = fields["NominalChargeCapacity"] as? Int ?? fields["AppleRawMaxCapacity"] as? Int ?? 0
        var details: [String: String] = [
            L("循环次数", "Cycle count"): "\(cycles)",
            L("设计容量(mAh)", "Design capacity (mAh)"): design > 0 ? "\(design)" : "N/A",
            L("当前满充容量(mAh)", "Full charge capacity (mAh)"): full > 0 ? "\(full)" : "N/A",
        ]
        if let serial = fields["Serial"] as? String, !serial.isEmpty {
            details[L("电池序列号", "Battery serial number")] = serial
        }

        // iPhone 15 之前的机型按 500 次循环保持 80% 设计，15 及以后为 1000 次，取 800 作为提醒线。
        var results = [CheckResult(
            id: "ios.battery.cycleCount",
            title: L("电池循环次数", "Battery cycle count"),
            status: cycles > 800 ? .warning : .pass,
            summary: L("循环 \(cycles) 次", "\(cycles) cycles") + (cycles > 800 ? L("，循环偏高，电池可能已明显衰减", ", which is high; the battery has likely worn noticeably") : ""),
            rawDetails: details
        )]

        if let health = batteryHealth(registry) {
            let status: CheckStatus = health >= 80 ? .pass : (health >= 60 ? .warning : .redFlag)
            results.append(CheckResult(
                id: "ios.battery.health",
                title: L("电池健康度", "Battery health"),
                status: status,
                summary: L("健康度约 \(health)%", "Health about \(health)%") + (health >= 80 ? L("，状态良好", ", in good shape") : health >= 60 ? L("，有明显衰减，Apple 建议低于 80% 时更换", ", noticeably worn; Apple recommends replacement below 80%") : L("，衰减严重", ", badly worn")),
                rawDetails: details,
                isRedFlagHeadline: health < 60
                    ? L("⛔ 电池健康度仅 \(health)%，续航会明显缩水甚至意外关机，建议要求换电池或大幅议价。", "⛔ Battery health is only \(health)%. Expect much shorter battery life or sudden shutdowns. Ask for a battery replacement or a big discount.")
                    : nil
            ))
        }
        return results
    }

    /// 优先用系统「电池健康」页同源的 MaximumCapacityPercent（较新机型才有），否则按满充/设计容量换算。
    static func batteryHealth(_ registry: [String: Any]) -> Int? {
        let fields = batteryFields(registry)
        if let percent = fields["MaximumCapacityPercent"] as? Int, percent > 0 {
            return percent
        }
        let design = fields["DesignCapacity"] as? Int ?? 0
        let full = fields["NominalChargeCapacity"] as? Int ?? fields["AppleRawMaxCapacity"] as? Int ?? 0
        guard design > 0, full > 0 else { return nil }
        return Int((Double(full) / Double(design) * 100).rounded())
    }

    private static func storageResult(_ disk: [String: Any]) -> CheckResult {
        guard let total = disk["TotalDiskCapacity"] as? Int else {
            return CheckResult(id: "ios.storage", title: L("存储", "Storage"), status: .unsupported,
                               summary: L("未能读取存储信息", "Couldn't read storage info"))
        }
        let available = disk["TotalDataAvailable"] as? Int
        var details = [L("容量", "Capacity"): formatBytes(total)]
        if let available { details[L("可用", "Available")] = formatBytes(available) }
        return CheckResult(
            id: "ios.storage",
            title: L("存储", "Storage"),
            status: .pass,
            summary: L("容量 \(formatBytes(total))", "\(formatBytes(total)) capacity") + (available.map { L("，可用 \(formatBytes($0))", ", \(formatBytes($0)) available") } ?? ""),
            rawDetails: details
        )
    }
}
