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

    // MARK: - MDM 绕过痕迹（issue #2）

    /// 与设备注册/MDM 相关的 Apple 域名。绕过脚本会在 hosts 里把它们指向 0.0.0.0，
    /// 让机器「联系不上」DEP 服务器，从而表面上显示「未监管」。
    static let enrollmentDomains = [
        "deviceenrollment.apple.com",
        "mdmenrollment.apple.com",
        "iprofiles.apple.com",
        "acmdm.apple.com",
    ]

    struct MDMBypassEvidence {
        var blockedHosts: [String] = []      // hosts 中被重定向的注册域名（原始行）
        var forgedMarkers: [String] = []     // 被伪造的云配置标记文件
        var isSuspicious: Bool { !blockedHosts.isEmpty || !forgedMarkers.isEmpty }
    }

    /// 解析 hosts 文本，找出把注册域名重定向到任意地址的有效行（忽略注释）。纯函数，便于测试。
    static func blockedEnrollmentHosts(inHostsFile text: String) -> [String] {
        var hits: [String] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.components(separatedBy: "#").first?.trimmingCharacters(in: .whitespaces) ?? ""
            let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map { $0.lowercased() }
            guard tokens.count >= 2 else { continue }
            let hostnames = tokens.dropFirst().map { $0.hasSuffix(".") ? String($0.dropLast()) : $0 }
            if hostnames.contains(where: { enrollmentDomains.contains($0) }) {
                hits.append(line)
            }
        }
        return hits
    }

    private static let cloudConfigDir = "/var/db/ConfigurationProfiles/Settings"

    private static func mdmBypassEvidence(mdmEnrolled: Bool?) -> MDMBypassEvidence {
        var evidence = MDMBypassEvidence()
        if let hosts = try? String(contentsOfFile: "/etc/hosts", encoding: .utf8) {
            evidence.blockedHosts = blockedEnrollmentHosts(inHostsFile: hosts)
        }
        // 正常机器只会有 .cloudConfigNoActivationRecord（无 DEP 记录）或 .cloudConfigHasActivationRecord（有记录）。
        // 绕过脚本的固定套路是：删掉 HasActivationRecord / RecordFound，再 touch
        // .cloudConfigProfileInstalled + .cloudConfigRecordNotFound 伪装成「描述文件已装好、查无记录」。
        // 「声称已装描述文件」却又「没有被 MDM 监管」，两者自相矛盾，即为伪造痕迹。
        let fm = FileManager.default
        func exists(_ name: String) -> Bool { fm.fileExists(atPath: "\(cloudConfigDir)/\(name)") }
        if exists(".cloudConfigProfileInstalled"), exists(".cloudConfigRecordNotFound"), mdmEnrolled != true {
            evidence.forgedMarkers = [".cloudConfigProfileInstalled", ".cloudConfigRecordNotFound"]
        }
        return evidence
    }

    // MARK: - Apple ID / 查找我的 Mac

    /// nil 表示缺少有效证据或来源冲突；不能当作已经退出登录。
    static func iCloudAccountSignedIn(legacy: [String: Any]?, cache: [String: Any]?) -> Bool? {
        let accounts = legacy?["Accounts"] as? [[String: Any]]
        let legacyState: Bool? = accounts.flatMap { accounts in
            if accounts.isEmpty { return false }
            return accounts.contains {
                !(($0["AccountID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            } ? true : nil
        }
        let cacheState = cache?["AAIsAccountSignedIn"] as? Bool
        if let legacyState, let cacheState, legacyState != cacheState { return nil }
        return cacheState ?? legacyState
    }

    struct ICloudAccountInfo {
        let signedIn: Bool?
        let accountID: String?
        let displayName: String?
        var needsFullDiskAccess = false
    }

    static func iCloudAccountInfo(
        legacy: [String: Any]?, cache: [String: Any]?, databaseUsernames: [String]
    ) -> ICloudAccountInfo {
        let signedIn = iCloudAccountSignedIn(legacy: legacy, cache: cache)
        // 退出登录后的缓存可能仍有个人资料，状态不明确时也不展示。
        guard signedIn == true else {
            return ICloudAccountInfo(signedIn: signedIn, accountID: nil, displayName: nil)
        }
        func nonempty(_ value: Any?) -> String? {
            guard let text = value as? String else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let accounts = (legacy?["Accounts"] as? [[String: Any]] ?? []).filter {
            nonempty($0["AccountID"]) != nil && ($0["LoggedIn"] as? Bool) != false
        }
        let identifiers = Set(accounts.compactMap { nonempty($0["AccountID"]) }
            + databaseUsernames.compactMap { nonempty($0) })
        let accountID = identifiers.count == 1 ? identifiers.first : nil
        let legacyName = accounts.first { nonempty($0["AccountID"]) == accountID }
            .flatMap { nonempty($0["DisplayName"]) }
        return ICloudAccountInfo(
            signedIn: signedIn, accountID: accountID,
            displayName: nonempty(cache?["AAAccountFullName"]) ?? legacyName
        )
    }

    /// 仅查询当前用户的主 Apple 账户，数据库内容不参与“已退出”判断。
    /// Schema reference: https://github.com/kolide/launcher/issues/1748
    static func iCloudAccountUsernames(at databaseURL: URL) -> [String] {
        iCloudAccountDatabase(at: databaseURL).usernames
    }

    static func parseICloudAccountDatabaseOutput(_ output: String) -> (usernames: [String], permissionDenied: Bool) {
        if let rows = (try? JSONSerialization.jsonObject(with: Data(output.utf8))) as? [[String: Any]] {
            return (rows.compactMap { $0["username"] as? String }, false)
        }
        let error = output.lowercased()
        return ([], ["authorization denied", "not authorized", "permission denied", "operation not permitted"]
            .contains { error.contains($0) })
    }

    private static func iCloudAccountDatabase(at databaseURL: URL) -> (usernames: [String], permissionDenied: Bool) {
        let query = """
            SELECT DISTINCT a.ZUSERNAME AS username FROM ZACCOUNT a
            JOIN ZACCOUNTTYPE t ON a.ZACCOUNTTYPE = t.Z_PK
            WHERE t.ZIDENTIFIER = 'com.apple.account.AppleAccount' AND a.ZACTIVE = 1
            """
        // GUI 应用的 TCC 权限与终端不同；保留错误类型，避免吞掉授权失败。
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-json", databaseURL.path, query]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return ([], false) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return parseICloudAccountDatabaseOutput(String(decoding: data, as: UTF8.self))
    }

    static func iCloudAccountInfo() -> ICloudAccountInfo {
        func preferences(_ domain: String) -> [String: Any]? {
            let output = ShellRunner.run("/usr/bin/defaults", ["export", domain, "-"])
            return (try? PropertyListSerialization.propertyList(
                from: Data(output.utf8), options: [], format: nil
            )) as? [String: Any]
        }
        let database = iCloudAccountDatabase(at: FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Accounts/Accounts4.sqlite"))
        var info = iCloudAccountInfo(
            legacy: preferences("MobileMeAccounts"),
            cache: preferences("com.apple.appleaccount.informationcache"),
            databaseUsernames: database.usernames
        )
        info.needsFullDiskAccess = info.signedIn == true && info.accountID == nil && database.permissionDenied
        return info
    }

    static func iCloudAccountSignedIn() -> Bool? { iCloudAccountInfo().signedIn }

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
            L("DEP 自动注册", "DEP auto-enrollment"): mdm.enrolledViaDEP.map { $0 ? L("是", "Yes") : L("否", "No") } ?? L("未知", "Unknown"),
            L("MDM 已监管", "MDM supervised"): mdm.mdmEnrolled.map { $0 ? L("是", "Yes") : L("否", "No") } ?? L("未知", "Unknown"),
        ]
        if let count = profiles.count {
            mdmDetails[L("已安装配置描述文件数量", "Installed configuration profiles")] = "\(count)"
        } else {
            mdmDetails[L("配置描述文件列表", "Configuration profiles")] = L("需要管理员权限，本次未能读取完整列表", "Admin rights needed; the full list couldn’t be read this time")
        }

        let bypass = mdmBypassEvidence(mdmEnrolled: mdm.mdmEnrolled)
        mdmDetails[L("hosts 屏蔽注册域名", "Enrollment domains blocked in hosts")] =
            bypass.blockedHosts.isEmpty ? L("无", "None") : bypass.blockedHosts.joined(separator: "; ")
        mdmDetails[L("伪造的云配置标记", "Forged cloud-config markers")] =
            bypass.forgedMarkers.isEmpty ? L("无", "None") : bypass.forgedMarkers.joined(separator: ", ")

        if mdm.mdmEnrolled != true, bypass.isSuspicious {
            var clues: [String] = []
            if !bypass.blockedHosts.isEmpty {
                clues.append(L("hosts 文件屏蔽了 Apple 设备注册服务器", "the hosts file blocks Apple's device-enrollment servers"))
            }
            if !bypass.forgedMarkers.isEmpty {
                clues.append(L("系统里有被手工伪造的「已跳过注册」标记文件", "hand-forged \"enrollment skipped\" marker files exist"))
            }
            results.append(CheckResult(
                id: "management.mdm",
                title: L("MDM 设备监管", "MDM Supervision"),
                status: .redFlag,
                summary: L("疑似已用脚本绕过 MDM：", "MDM appears to have been bypassed with a script: ")
                    + clues.joined(separator: L("；", "; ")),
                rawDetails: mdmDetails,
                isRedFlagHeadline: L(
                    "⛔ 这台机器表面显示「未监管」，但发现了绕过 MDM 的痕迹（\(clues.joined(separator: "、"))）。这通常意味着它属于某个企业/学校、仍在 Apple 的设备注册名单里，只是被脚本临时挡住了。一旦抹掉重装、升级系统或 hosts 被还原，就会被重新锁回原单位的管理。强烈不建议购买。",
                    "⛔ This Mac looks unsupervised, but there are signs that MDM was bypassed (\(clues.joined(separator: "; "))). This usually means it still belongs to a company or school and remains in Apple's device-enrollment program — the enrollment is only being blocked by a script. Erasing, reinstalling or updating macOS, or restoring the hosts file, will put it back under the organization's management. Strongly not recommended."
                )
            ))
        } else if mdm.mdmEnrolled == true {
            results.append(CheckResult(
                id: "management.mdm",
                title: L("MDM 设备监管", "MDM Supervision"),
                status: .redFlag,
                summary: L("此机已被 MDM（移动设备管理）监管", "This Mac is under MDM (mobile device management) supervision"),
                rawDetails: mdmDetails,
                isRedFlagHeadline: L("⛔ 此机正被企业/学校的 MDM 系统监管，对方可以远程施加限制、甚至远程抹除数据，重装系统通常也无法解除（尤其是 DEP 自动注册的情况）。强烈不建议购买，除非卖家能提供从原单位 解绑的证明。", "⛔ This Mac is managed by a company or school MDM system. They can restrict it remotely or even erase it, and reinstalling macOS usually won’t remove this (especially with DEP auto-enrollment). Strongly not recommended unless the seller can prove it has been released by the original organization.")
            ))
        } else if mdm.enrolledViaDEP == true {
            results.append(CheckResult(
                id: "management.mdm",
                title: L("MDM 设备监管", "MDM Supervision"),
                status: .warning,
                summary: L("此机存在 DEP 自动注册记录，虽当前未监管，但重装后可能被自动拉回监管", "This Mac has a DEP auto-enrollment record. It isn’t supervised now, but it may be pulled back under management after a reinstall"),
                rawDetails: mdmDetails,
                isRedFlagHeadline: L("⚠️ 此机在 Apple 的 DEP 名单中有记录，一旦联网重装系统，有可能被原企业自动重新监管。建议交易前让卖家联系原企业从 DEP 中移除此设备。", "⚠️ This Mac is listed in Apple’s DEP program. If macOS is reinstalled while online, the original organization may automatically manage it again. Before buying, ask the seller to have that organization remove it from DEP.")
            ))
        } else if mdm.mdmEnrolled == nil {
            results.append(CheckResult(
                id: "management.mdm",
                title: L("MDM 设备监管", "MDM Supervision"),
                status: .warning,
                summary: L("未能确认监管状态（命令执行异常），建议手动检查「系统设置 > 隐私与安全性 > 描述文件与设备管理」", "Couldn’t confirm supervision status (the command failed). Check manually in System Settings > Privacy & Security > Profiles & Device Management"),
                rawDetails: mdmDetails
            ))
        } else {
            results.append(CheckResult(
                id: "management.mdm",
                title: L("MDM 设备监管", "MDM Supervision"),
                status: .pass,
                summary: L("未检测到 MDM 监管，可以放心购买", "No MDM supervision found; safe to buy on this point"),
                rawDetails: mdmDetails
            ))
        }

        // Apple ID
        let account = iCloudAccountInfo()
        let signedIn = account.signedIn
        var accountDetails = [L("iCloud 账户", "iCloud account"): signedIn.map { $0 ? L("已登录", "Signed in") : L("未登录", "Not signed in") } ?? L("无法确认", "Unknown")]
        if signedIn == true {
            accountDetails["Apple ID"] = account.accountID ?? L("未能读取，请在系统设置中核对", "Unavailable; check System Settings")
            accountDetails[L("账户姓名", "Account name")] = account.displayName ?? L("未能读取", "Unavailable")
            if account.needsFullDiskAccess {
                accountDetails["Apple ID"] = L("读取被 macOS 隐私权限阻止", "Blocked by macOS privacy permissions")
                accountDetails[L("读取账号所需权限", "Account access permission")] = L(
                    "系统设置 > 隐私与安全性 > 完整磁盘访问权限，添加并启用 MacCheck，然后退出并重新打开应用",
                    "Add and enable MacCheck in System Settings > Privacy & Security > Full Disk Access, then quit and reopen the app"
                )
            }
        }
        results.append(CheckResult(
            id: "management.appleID",
            title: L("Apple ID 登录状态", "Apple ID Sign-in"),
            status: signedIn == false ? .pass : .warning,
            summary: signedIn.map { $0 ? L("检测到仍有 Apple ID 登录在本机，交易前必须确认已退出", "An Apple ID is still signed in on this Mac; make sure it’s signed out before buying") : L("未检测到已登录的 Apple ID", "No Apple ID is signed in") }
                ?? L("无法确认 Apple ID 登录状态，请在「系统设置 > Apple 账户」中核对", "Couldn’t confirm Apple ID sign-in; check System Settings > Apple Account"),
            rawDetails: accountDetails,
            isRedFlagHeadline: signedIn == true
                ? L("⚠️ 本机仍登录着一个 Apple ID。如果这不是你自己的账号，说明原机主没有退出登录——过户前必须让对方在「系统设置 > Apple 账户」里退出 Apple ID，否则你无法正常使用 iCloud、App Store 等服务。", "⚠️ An Apple ID is still signed in on this Mac. If it isn’t yours, the previous owner never signed out. Have them sign out of their Apple ID in System Settings before the handover, or you won’t be able to use iCloud, the App Store and other services properly.")
                : nil
        ))

        // 激活锁
        let lockStatus = activationLockStatus()
        let isLocked = lockStatus.lowercased().contains("enabled")
        if !lockStatus.isEmpty {
            results.append(CheckResult(
                id: "management.activationLock",
                title: L("查找我的 Mac / 激活锁", "Find My Mac / Activation Lock"),
                status: isLocked ? .redFlag : .pass,
                summary: isLocked ? L("激活锁处于开启状态", "Activation Lock is on") : L("激活锁已关闭，可以正常使用", "Activation Lock is off; the Mac can be used normally"),
                rawDetails: [L("激活锁原始状态", "Activation Lock raw status"): lockStatus],
                isRedFlagHeadline: isLocked
                    ? L("⛔ 此机的激活锁（查找我的 Mac）仍处于开启状态。如果卖家无法当场用自己的 Apple ID 密码关闭，这台机器有很大风险被锁定无法使用，切勿付款。", "⛔ Activation Lock (Find My Mac) is still on. If the seller can’t turn it off on the spot with their Apple ID password, this Mac is at serious risk of being locked and unusable. Do not pay.")
                    : nil
            ))
        }

        return results
    }
}
