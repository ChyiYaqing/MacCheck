import Foundation

/// A3：存储/固态硬盘检测。读取 SSD 型号、容量、SMART 健康状态、TRIM，以及剩余可用空间。
enum StorageService {

    private static func nvmeDrives() -> [[String: Any]] {
        let output = ShellRunner.run("/usr/sbin/system_profiler", ["SPNVMeDataType", "-json"])
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = json["SPNVMeDataType"] as? [[String: Any]]
        else { return [] }
        return controllers.flatMap { ($0["_items"] as? [[String: Any]]) ?? [] }
    }

    private static func freeSpaceBytes() -> Int64? {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let bytes = values.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return bytes
    }

    private static func gb(_ bytes: Int64) -> String {
        String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
    }

    /// 字节数 → 「12.3 TB / 456 GB」这类人类可读写法（十进制，与 smartctl 一致）。
    static func humanBytes(_ bytes: Double) -> String {
        if bytes >= 1e12 { return String(format: "%.2f TB", bytes / 1e12) }
        return String(format: "%.0f GB", bytes / 1e9)
    }

    /// 把 SMART 健康日志写进详情，并给出需要提醒买家的问题（空数组 = 无问题）。
    private static func applySMART(_ h: NVMeHealth, to details: inout [String: String]) -> (warnings: [String], redFlags: [String]) {
        details[L("累计写入", "Data written")] = humanBytes(h.bytesWritten)
        details[L("累计读取", "Data read")] = humanBytes(h.bytesRead)
        details[L("寿命已消耗", "Percentage used")] = "\(h.percentageUsed)%"
        details[L("可用备用块", "Available spare")] = "\(h.availableSpare)% (\(L("阈值", "threshold")) \(h.availableSpareThreshold)%)"
        details[L("通电时长", "Power-on hours")] = L("\(h.powerOnHours) 小时", "\(h.powerOnHours) h")
        details[L("通电次数", "Power cycles")] = "\(h.powerCycles)"
        details[L("异常断电次数", "Unsafe shutdowns")] = "\(h.unsafeShutdowns)"
        details[L("介质错误", "Media errors")] = "\(h.mediaErrors)"
        details[L("错误日志条目", "Error log entries")] = "\(h.errorLogEntries)"
        details[L("硬盘温度", "SSD temperature")] = "\(h.temperatureCelsius) °C"
        details[L("严重警告位", "Critical warning")] = h.criticalWarning == 0 ? L("无", "None") : String(format: "0x%02X", h.criticalWarning)

        var warnings: [String] = []
        var redFlags: [String] = []
        if h.criticalWarning != 0 {
            redFlags.append(L("硬盘报告了严重警告", "the SSD reports a critical warning"))
        }
        if h.availableSpare < h.availableSpareThreshold {
            redFlags.append(L("备用块已低于安全阈值", "available spare is below the safety threshold"))
        }
        if h.percentageUsed >= 100 {
            redFlags.append(L("标称写入寿命已用完（\(h.percentageUsed)%）", "rated write endurance is used up (\(h.percentageUsed)%)"))
        } else if h.percentageUsed >= 80 {
            warnings.append(L("写入寿命已消耗 \(h.percentageUsed)%", "\(h.percentageUsed)% of write endurance used"))
        }
        if h.mediaErrors > 0 {
            warnings.append(L("出现过 \(h.mediaErrors) 次介质错误", "\(h.mediaErrors) media errors recorded"))
        }
        return (warnings, redFlags)
    }

    static func runAll() -> [CheckResult] {
        let drives = nvmeDrives()
        let health = NVMeSMARTReader.readInternal()
        guard let disk = drives.first else {
            return [CheckResult(
                id: "storage",
                title: L("存储", "Storage"),
                status: .unsupported,
                summary: L("未检测到内建 NVMe 固态硬盘信息", "No built-in NVMe SSD information found")
            )]
        }

        let model = (disk["device_model"] as? String) ?? (disk["_name"] as? String) ?? L("未知", "Unknown")
        let size = (disk["size"] as? String) ?? ""
        let smart = (disk["smart_status"] as? String) ?? ""
        let trim = (disk["spnvme_trim_support"] as? String) ?? ""
        let revision = (disk["device_revision"] as? String) ?? ""

        var details: [String: String] = [
            L("型号", "Model"): model,
            L("容量", "Capacity"): size,
            L("SMART 状态", "SMART status"): smart.isEmpty ? L("未知", "Unknown") : smart,
            L("TRIM 支持", "TRIM support"): trim.isEmpty ? L("未知", "Unknown") : trim,
            L("固件版本", "Firmware"): revision,
        ]
        if let free = freeSpaceBytes() {
            details[L("可用空间", "Free space")] = gb(free)
        }
        let title = L("存储 / 固态硬盘", "Storage / SSD")
        let smartIssues: (warnings: [String], redFlags: [String]) = health.map { applySMART($0, to: &details) } ?? ([], [])

        // SMART "Verified" = 正常；其它值（如 Failing）→ 红旗
        let smartOK = smart.lowercased() == "verified"
        if !smart.isEmpty && !smartOK {
            return [CheckResult(
                id: "storage",
                title: title,
                status: .redFlag,
                summary: L("硬盘 SMART 健康状态异常（\(smart)），存在数据丢失风险", "SSD SMART status is abnormal (\(smart)); there is a risk of data loss"),
                rawDetails: details,
                isRedFlagHeadline: L(
                    "⛔ 固态硬盘的 SMART 健康检测未通过（状态：\(smart)），说明硬盘可能即将损坏，随时有数据丢失风险，不建议购买或应立即备份更换。",
                    "⛔ The SSD failed its SMART health check (status: \(smart)). The drive may be about to fail and data could be lost at any time. Not recommended — or back up and replace it immediately."
                )
            )]
        }
        if !smartIssues.redFlags.isEmpty {
            let reasons = smartIssues.redFlags.joined(separator: L("；", "; "))
            return [CheckResult(
                id: "storage",
                title: title,
                status: .redFlag,
                summary: L("硬盘健康数据异常：\(reasons)", "SSD health data is abnormal: \(reasons)"),
                rawDetails: details,
                isRedFlagHeadline: L(
                    "⛔ 固态硬盘自身的健康日志显示：\(reasons)。Mac 的硬盘焊在主板上无法单独更换，硬盘坏了等于换主板，强烈不建议购买。",
                    "⛔ The SSD's own health log shows: \(reasons). The SSD in a Mac is soldered to the logic board and can't be replaced separately — a failing SSD means a new logic board. Strongly not recommended."
                )
            )]
        }

        var summary = "\(model) · \(size) · " + L("SMART 健康状态正常", "SMART status OK")
        if let health {
            summary += L(
                " · 累计写入 \(humanBytes(health.bytesWritten))，寿命消耗 \(health.percentageUsed)%",
                " · \(humanBytes(health.bytesWritten)) written, \(health.percentageUsed)% endurance used"
            )
        }
        if !smartIssues.warnings.isEmpty {
            return [CheckResult(
                id: "storage",
                title: title,
                status: .warning,
                summary: summary + L("。注意：", ". Note: ") + smartIssues.warnings.joined(separator: L("；", "; ")),
                rawDetails: details
            )]
        }
        return [CheckResult(
            id: "storage",
            title: title,
            status: .pass,
            summary: summary,
            rawDetails: details
        )]
    }
}
