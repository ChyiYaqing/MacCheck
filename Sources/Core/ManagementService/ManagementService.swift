import Foundation

/// A7：监管与锁定检测——二手交易里最容易被忽视、后果最重的一类问题。
/// 命中任意一项即产生红旗，因为这些问题"重装系统也解决不了"。
enum ManagementService {

    // MARK: - MDM 监管

    private struct MDMEnrollmentStatus {
        var enrolledViaDEP: Bool?
        var mdmEnrolled: Bool?
        var rawOutput: String
    }

    private static func mdmEnrollmentStatus() -> MDMEnrollmentStatus {
        let output = ShellRunner.run("/usr/bin/profiles", ["status", "-type", "enrollment"])
        func flag(after marker: String) -> Bool? {
            guard let range = output.range(of: marker) else { return nil }
            let tail = output[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if tail.hasPrefix("Yes") { return true }
            if tail.hasPrefix("No") { return false }
            return nil
        }
        return MDMEnrollmentStatus(
            enrolledViaDEP: flag(after: "Enrolled via DEP:"),
            mdmEnrolled: flag(after: "MDM enrollment:"),
            rawOutput: output
        )
    }

    private static func installedConfigurationProfilesSummary() -> (count: Int?, rawOutput: String) {
        let output = ShellRunner.run("/usr/bin/profiles", ["list", "-all"])
        // 无管理员权限时该命令通常直接报错或输出为空，如实降级而不是伪造结果。
        let profileLines = output.components(separatedBy: "\n").filter { $0.contains("profileIdentifier") }
        if output.isEmpty || output.lowercased().contains("you need to run this tool as root") {
            return (nil, output)
        }
        return (profileLines.count, output)
    }

    // MARK: - Apple ID / 查找我的 Mac

    private static func isICloudAccountSignedIn() -> Bool {
        let output = ShellRunner.run("/usr/bin/defaults", ["read", "MobileMeAccounts", "Accounts"])
        return !output.isEmpty && output.contains("AccountID")
    }

    // MARK: - 激活锁

    private static func activationLockStatus() -> String {
        let sp = HardwareProbe.systemProfilerHardwareJSON()
        return (sp["activation_lock_status"] as? String) ?? ""
    }

    // MARK: - 汇总检测

    static func runAll() -> [CheckResult] {
        var results: [CheckResult] = []

        // MDM
        let mdm = mdmEnrollmentStatus()
        let profiles = installedConfigurationProfilesSummary()
        var mdmDetails: [String: String] = [
            "DEP 自动注册": mdm.enrolledViaDEP.map { $0 ? "是" : "否" } ?? "未知",
            "MDM 已监管": mdm.mdmEnrolled.map { $0 ? "是" : "否" } ?? "未知",
        ]
        if let count = profiles.count {
            mdmDetails["已安装配置描述文件数量"] = "\(count)"
        } else {
            mdmDetails["配置描述文件列表"] = "需要管理员权限，本次未能读取完整列表"
        }

        if mdm.mdmEnrolled == true {
            results.append(CheckResult(
                id: "management.mdm",
                title: "MDM 设备监管",
                status: .redFlag,
                summary: "此机已被 MDM（移动设备管理）监管",
                rawDetails: mdmDetails,
                isRedFlagHeadline: "⛔ 此机正被企业/学校的 MDM 系统监管，对方可以远程施加限制、甚至远程抹除数据，重装系统通常也无法解除（尤其是 DEP 自动注册的情况）。强烈不建议购买，除非卖家能提供从原organization 解绑的证明。"
            ))
        } else if mdm.enrolledViaDEP == true {
            results.append(CheckResult(
                id: "management.mdm",
                title: "MDM 设备监管",
                status: .warning,
                summary: "此机存在 DEP 自动注册记录，虽当前未监管，但重装后可能被自动拉回监管",
                rawDetails: mdmDetails,
                isRedFlagHeadline: "⚠️ 此机在 Apple 的 DEP 名单中有记录，一旦联网重装系统，有可能被原企业自动重新监管。建议交易前让卖家联系原企业从 DEP 中移除此设备。"
            ))
        } else if mdm.mdmEnrolled == nil {
            results.append(CheckResult(
                id: "management.mdm",
                title: "MDM 设备监管",
                status: .warning,
                summary: "未能确认监管状态（命令执行异常），建议手动检查「系统设置 > 隐私与安全性 > 描述文件与设备管理」",
                rawDetails: mdmDetails
            ))
        } else {
            results.append(CheckResult(
                id: "management.mdm",
                title: "MDM 设备监管",
                status: .pass,
                summary: "未检测到 MDM 监管，可以放心购买",
                rawDetails: mdmDetails
            ))
        }

        // Apple ID
        let signedIn = isICloudAccountSignedIn()
        results.append(CheckResult(
            id: "management.appleID",
            title: "Apple ID 登录状态",
            status: signedIn ? .warning : .pass,
            summary: signedIn ? "检测到仍有 Apple ID 登录在本机，交易前必须确认已退出" : "未检测到已登录的 Apple ID",
            rawDetails: ["iCloud 账户": signedIn ? "已登录" : "未登录"],
            isRedFlagHeadline: signedIn
                ? "⚠️ 本机仍登录着一个 Apple ID。如果这不是你自己的账号，说明原机主没有退出登录——过户前必须让对方在「系统设置 > 用户」里退出 Apple ID，否则你无法正常使用 iCloud、App Store 等服务。"
                : nil
        ))

        // 激活锁
        let lockStatus = activationLockStatus()
        let isLocked = lockStatus.lowercased().contains("enabled")
        if !lockStatus.isEmpty {
            results.append(CheckResult(
                id: "management.activationLock",
                title: "查找我的 Mac / 激活锁",
                status: isLocked ? .redFlag : .pass,
                summary: isLocked ? "激活锁处于开启状态" : "激活锁已关闭，可以正常使用",
                rawDetails: ["激活锁原始状态": lockStatus],
                isRedFlagHeadline: isLocked
                    ? "⛔ 此机的激活锁（查找我的 Mac）仍处于开启状态。如果卖家无法当场用自己的 Apple ID 密码关闭，这台机器有很大风险被锁定无法使用，切勿付款。"
                    : nil
            ))
        }

        return results
    }
}
