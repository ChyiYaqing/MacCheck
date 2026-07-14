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

    static func runAll() -> [CheckResult] {
        let drives = nvmeDrives()
        guard let disk = drives.first else {
            return [CheckResult(
                id: "storage",
                title: "存储",
                status: .unsupported,
                summary: "未检测到内建 NVMe 固态硬盘信息"
            )]
        }

        let model = (disk["device_model"] as? String) ?? (disk["_name"] as? String) ?? "未知"
        let size = (disk["size"] as? String) ?? ""
        let smart = (disk["smart_status"] as? String) ?? ""
        let trim = (disk["spnvme_trim_support"] as? String) ?? ""
        let revision = (disk["device_revision"] as? String) ?? ""

        var details: [String: String] = [
            "型号": model,
            "容量": size,
            "SMART 状态": smart.isEmpty ? "未知" : smart,
            "TRIM 支持": trim.isEmpty ? "未知" : trim,
            "固件版本": revision,
        ]
        if let free = freeSpaceBytes() {
            details["可用空间"] = gb(free)
        }

        // SMART "Verified" = 正常；其它值（如 Failing）→ 红旗
        let smartOK = smart.lowercased() == "verified"
        if !smart.isEmpty && !smartOK {
            return [CheckResult(
                id: "storage",
                title: "存储 / 固态硬盘",
                status: .redFlag,
                summary: "硬盘 SMART 健康状态异常（\(smart)），存在数据丢失风险",
                rawDetails: details,
                isRedFlagHeadline: "⛔ 固态硬盘的 SMART 健康检测未通过（状态：\(smart)），说明硬盘可能即将损坏，随时有数据丢失风险，不建议购买或应立即备份更换。"
            )]
        }

        return [CheckResult(
            id: "storage",
            title: "存储 / 固态硬盘",
            status: .pass,
            summary: "\(model) · \(size) · SMART 健康状态正常",
            rawDetails: details
        )]
    }
}
