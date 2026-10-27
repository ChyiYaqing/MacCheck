import Foundation
import IOKit

/// A2：电池健康。循环次数/容量走 IORegistry `AppleSmartBattery`，
/// 并用 `ioreg` 命令行输出做第二来源交叉核对（5.5 防篡改：两条独立路径读同一数据，不一致就标红）。
enum BatteryService {

    private static func openBatteryService() -> io_service_t {
        IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    }

    private static func ioKitProperties() -> [String: Any] {
        let service = openBatteryService()
        guard service != 0 else { return [:] }
        defer { IOObjectRelease(service) }

        var propsUnmanaged: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &propsUnmanaged, kCFAllocatorDefault, 0)
        guard result == KERN_SUCCESS, let props = propsUnmanaged?.takeRetainedValue() as? [String: Any] else {
            return [:]
        }
        return props
    }

    /// 第二来源：直接解析 `ioreg` 命令行文本输出中的 CycleCount，走的是另一条独立的数据管道。
    private static func ioregCycleCount() -> Int? {
        let output = ShellRunner.run("/usr/sbin/ioreg", ["-rd1", "-c", "AppleSmartBattery"])
        guard let range = output.range(of: "\"CycleCount\" = ") else { return nil }
        let tail = output[range.upperBound...]
        let numberString = tail.prefix { $0.isNumber }
        return Int(numberString)
    }

    static func runAll() -> [CheckResult] {
        let props = ioKitProperties()
        guard !props.isEmpty else {
            return [CheckResult(
                id: "battery.health",
                title: L("电池健康", "Battery"),
                status: .unsupported,
                summary: L("未检测到电池（可能是 Mac mini / Mac Studio / Mac Pro 台式机，无需关注此项）", "No battery found (likely a desktop such as Mac mini, Mac Studio or Mac Pro, so nothing to check here)")
            )]
        }

        var results: [CheckResult] = []

        let cycleCount = props["CycleCount"] as? Int ?? 0
        let designCapacity = props["DesignCapacity"] as? Int ?? 0
        let rawMaxCapacity = props["AppleRawMaxCapacity"] as? Int ?? 0
        let maxCapacityPercentRaw = props["MaxCapacity"] as? Int
        let isCharging = props["IsCharging"] as? Bool ?? false
        let externalConnected = props["ExternalConnected"] as? Bool ?? false
        let temperatureRaw = props["Temperature"] as? Int ?? 0
        let temperatureC = Double(temperatureRaw) / 100.0

        var health: Double?
        if designCapacity > 0 && rawMaxCapacity > 0 {
            health = Double(rawMaxCapacity) / Double(designCapacity) * 100.0
        } else if let pct = maxCapacityPercentRaw, pct > 0 && pct <= 100 {
            health = Double(pct)
        }

        var details: [String: String] = [
            L("循环次数", "Cycle count"): "\(cycleCount)",
            L("设计容量(mAh)", "Design capacity (mAh)"): designCapacity > 0 ? "\(designCapacity)" : "N/A",
            L("当前最大容量(mAh)", "Current max capacity (mAh)"): rawMaxCapacity > 0 ? "\(rawMaxCapacity)" : "N/A",
            L("电池温度", "Battery temperature"): String(format: "%.1f °C", temperatureC),
            L("是否充电中", "Charging"): isCharging ? L("是", "Yes") : L("否", "No"),
            L("是否接电源", "Power connected"): externalConnected ? L("是", "Yes") : L("否", "No"),
        ]
        if let serial = props["BatterySerialNumber"] as? String {
            details[L("电池序列号", "Battery serial number")] = serial
        }
        if let adapterDetails = props["AdapterDetails"] as? [String: Any],
           let watts = adapterDetails["Watts"] as? Int {
            details[L("当前充电器功率", "Charger wattage")] = "\(watts)W"
        }

        // 循环次数交叉核对
        if let ioregCount = ioregCycleCount(), ioregCount != cycleCount {
            results.append(CheckResult(
                id: "battery.cycleCount.crosscheck",
                title: L("电池循环次数交叉核对", "Battery cycle count cross-check"),
                status: .redFlag,
                summary: L("两种方式读到的循环次数不一致（\(cycleCount) vs \(ioregCount)），电池数据可能被篡改", "Two independent readings of the cycle count disagree (\(cycleCount) vs \(ioregCount)). The battery data may have been tampered with."),
                rawDetails: [L("IOKit 读取", "IOKit reading"): "\(cycleCount)", L("ioreg 读取", "ioreg reading"): "\(ioregCount)"],
                isRedFlagHeadline: L("⛔ 电池循环次数两种读取方式结果不一致，可能被人为修改过，不要仅凭软件显示的数字判断电池成色，建议实际观察续航表现。", "⛔ The battery cycle count reads differently from two sources and may have been altered. Don't judge the battery by the number on screen alone; check how long it actually lasts.")
            ))
        }

        // 循环次数本体判断（大白话换算：iPhone/Mac 电池设计寿命常见参考线在 1000 次左右）
        let cycleStatus: CheckStatus = cycleCount > 1000 ? .warning : .pass
        let usageHint: String
        switch cycleCount {
        case 0...30: usageHint = L("几乎全新，使用时间很短", "nearly new, barely used")
        case 31...200: usageHint = L("轻度使用，大约几个月到一年", "light use, roughly a few months to a year")
        case 201...500: usageHint = L("中度使用，属于正常二手成色", "moderate use, normal for a used Mac")
        case 501...1000: usageHint = L("使用较多，电池已有一定衰减", "heavy use, the battery has worn somewhat")
        default: usageHint = L("循环次数偏高，电池健康度可能明显下降，建议议价或准备换电池", "high cycle count, battery health may be noticeably lower; negotiate the price or plan for a battery replacement")
        }
        results.append(CheckResult(
            id: "battery.cycleCount",
            title: L("电池循环次数", "Battery cycle count"),
            status: cycleStatus,
            summary: L("循环 \(cycleCount) 次 —— \(usageHint)", "\(cycleCount) cycles — \(usageHint)"),
            rawDetails: details
        ))

        // 电池健康度
        if let health {
            let healthStatus: CheckStatus = health >= 80 ? .pass : (health >= 60 ? .warning : .redFlag)
            let headline: String? = health < 60
                ? L("⛔ 电池健康度仅 \(Int(health))%，日常使用可能出现续航明显缩水或自动关机，建议购买前要求更换电池或大幅议价。", "⛔ Battery health is only \(Int(health))%. Expect much shorter battery life or sudden shutdowns. Ask for a battery replacement or a big discount before buying.")
                : nil
            results.append(CheckResult(
                id: "battery.health",
                title: L("电池健康度", "Battery health"),
                status: healthStatus,
                summary: L("健康度约 \(Int(health))%", "Health about \(Int(health))%") + (health >= 80 ? L("，状态良好", ", in good shape") : health >= 60 ? L("，有明显衰减但可用", ", noticeably worn but usable") : L("，衰减严重", ", badly worn")),
                rawDetails: details,
                isRedFlagHeadline: headline
            ))
        } else {
            results.append(CheckResult(
                id: "battery.health",
                title: L("电池健康度", "Battery health"),
                status: .warning,
                summary: L("本机型未提供标准健康度数据，仅供参考原始容量数值", "This model doesn't report a standard health figure; see the raw capacity numbers for reference"),
                rawDetails: details
            ))
        }

        return results
    }
}
