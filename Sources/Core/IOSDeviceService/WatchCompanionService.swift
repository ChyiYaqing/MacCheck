import Foundation

/// Apple Watch 没有数据接口，只能经由配对的 iPhone 的 companion_proxy 服务读取注册信息。
/// 实际读取由内嵌的 MacCheckWatchHelper 完成（见 Helpers/WatchHelper/main.swift 的说明）。
enum WatchCompanionService {

    /// 一台已读取的手表：摘要 + 档案 + 检测结果。
    struct Watch: Sendable {
        let summary: IOSDeviceSummary
        let profile: DeviceProfile
        let results: [CheckResult]
    }

    /// 读取一台 iPhone 配对的所有手表。辅助程序缺失、Homebrew 库不可用、iPhone 未信任或没有配对手表时返回空。
    static func pairedWatches(iPhoneUDID: String) -> [Watch] {
        guard let helper = Bundle.main.url(forAuxiliaryExecutable: "MacCheckWatchHelper") else { return [] }
        let output = ShellRunner.run(helper.path, [iPhoneUDID])
        guard let data = output.data(using: .utf8),
              let watches = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]]
        else { return [] }
        return watches.compactMap { info in
            (info["UniqueDeviceID"] as? String).map { watch(udid: $0, info: info) }
        }
    }

    static func watch(udid: String, info: [String: Any]) -> Watch {
        let summary = IOSDeviceService.summary(udid: udid, info: info)
        return Watch(
            summary: summary,
            profile: IOSDeviceService.profile(info: info, disk: [:]),
            results: [
                IOSDeviceService.identityResult(info),
                IOSDeviceService.modelNumberResult(info),
                batteryResult(info),
                activationLockResult(),
            ]
        )
    }

    static func batteryResult(_ info: [String: Any]) -> CheckResult {
        let level = info["BatteryCurrentCapacity"] as? Int
        let charging = info["BatteryIsCharging"] as? Bool ?? false
        var details: [String: String] = [:]
        if let level { details[L("当前电量", "Current charge")] = "\(level)%" }
        details[L("是否充电中", "Charging")] = charging ? L("是", "Yes") : L("否", "No")
        let now = level.map { L("当前电量 \($0)%\(charging ? "（充电中）" : "")。", "Current charge \($0)%\(charging ? " (charging)" : ""). ") } ?? ""
        return CheckResult(
            id: "ios.watch.battery",
            title: L("电池", "Battery"),
            status: .unsupported,
            summary: now + L("健康度与循环次数无法经由 iPhone 读取，请在手表「设置 > 电池 > 电池健康」查看最大容量。", "Battery health and cycle count can't be read through the iPhone. Check maximum capacity in Settings > Battery > Battery Health on the watch."),
            rawDetails: details
        )
    }

    /// companion_proxy 不提供激活状态，只能提示人工确认。
    private static func activationLockResult() -> CheckResult {
        CheckResult(
            id: "ios.watch.activationLock",
            title: L("激活锁", "Activation Lock"),
            status: .unsupported,
            summary: L("无法经由 iPhone 读取激活锁状态。请让卖家在 iPhone「Watch」App 中解除配对，解除配对会同时关闭激活锁。", "Activation Lock status can't be read through the iPhone. Have the seller unpair the watch in the Watch app on their iPhone, which also turns off Activation Lock.")
        )
    }
}
