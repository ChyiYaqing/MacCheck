import Foundation

/// A8：安全芯片档位识别。用大白话解释含义，避免用户误以为"没有 T2 = 有问题"。
enum SecurityChipTier: String, Sendable {
    case appleSilicon = "Apple Silicon（内置 Secure Enclave）"
    case intelWithT2 = "Intel + T2 安全芯片"
    case intelNoT2 = "Intel（无 T2 安全芯片）"
}

enum SecurityChipService {

    private static func bridgeOSJSON() -> [String: Any] {
        let output = ShellRunner.run("/usr/sbin/system_profiler", ["SPiBridgeDataType", "-json"])
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["SPiBridgeDataType"] as? [[String: Any]],
              let first = items.first
        else { return [:] }
        return first
    }

    static func detectTier() -> SecurityChipTier {
        if HardwareProbe.isAppleSiliconHardware() {
            return .appleSilicon
        }
        let bridge = bridgeOSJSON()
        let modelName = (bridge["ibridge_model_name"] as? String) ?? (bridge["Model Name"] as? String) ?? ""
        if modelName.contains("T2") {
            return .intelWithT2
        }
        return .intelNoT2
    }

    static func runAll() -> [CheckResult] {
        let tier = detectTier()
        let explanation: String
        switch tier {
        case .appleSilicon:
            explanation = "本机是 Apple Silicon（M 系列）芯片，安全能力内建在芯片里，务必确认「查找我的 Mac / 激活锁」已关闭（见监管检测项），这类机型激活锁问题最常见。"
        case .intelWithT2:
            explanation = "本机是带 T2 安全芯片的 Intel Mac，同样存在激活锁风险，请确认「查找我的 Mac」已关闭。"
        case .intelNoT2:
            explanation = "本机是较早期的 Intel Mac，不含 T2 安全芯片，不存在激活锁（Activation Lock）机制，无需担心 Apple ID 锁定问题，可以跳过这项顾虑。"
        }
        return [CheckResult(
            id: "hardware.securityChip",
            title: "安全芯片",
            status: .pass,
            summary: "\(tier.rawValue) —— \(explanation)",
            rawDetails: ["安全芯片档位": tier.rawValue]
        )]
    }
}
