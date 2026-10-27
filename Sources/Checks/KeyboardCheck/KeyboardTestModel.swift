import AppKit
import Combine
import CoreGraphics

/// 键盘测试状态机。用局部事件监听（不是全局 Accessibility 监听）——
/// 全屏测试窗口本身是 key window 时就能收到按键事件，无需辅助功能权限。
///
/// 所有事件码先经 `KeyboardLayout.canonicalCode` 归并到布局里的主 keyCode，
/// 所以顶排的亮度/音量等媒体键和 fn+F1…F12 都会点亮同一个键位。
@MainActor
final class KeyboardTestModel: ObservableObject {
    @Published private(set) var testedKeyCodes: Set<UInt16> = []
    @Published private(set) var pressedKeyCodes: Set<UInt16> = []
    @Published private(set) var stuckKeyCodes: Set<UInt16> = []
    /// 用户点击键位手动确认的键（被系统快捷键截走、App 收不到事件的键，如 fn+F11「显示桌面」）。
    @Published private(set) var manuallyConfirmed: Set<UInt16> = []

    private var pressStartTimes: [UInt16: Date] = [:]
    private var monitor: Any?
    private var stuckCheckTimer: Timer?
    private var resignObserver: NSObjectProtocol?

    let totalKeyCount: Int
    var onRequestFinish: (() -> Void)?

    private static let escKeyCode: UInt16 = 53
    private static let capsLockKeyCode: UInt16 = 57
    private static let escHoldToExitSeconds: TimeInterval = 1.2
    private static let stuckThresholdSeconds: TimeInterval = 5.0

    /// 修饰键 keyCode → 区分左右的设备相关标志位（NX_DEVICE*KEYMASK）。
    /// flagsChanged 事件本身不带 down/up，必须从标志位判断「此刻是否按着」，
    /// 不能用「收到一次就翻转」——那样只要漏掉一次事件（例如带 ⌘ 的组合被系统处理）状态就永久反了，进而误报卡键。
    private static let modifierMasks: [UInt16: UInt] = [
        56: 0x0000_0002, 60: 0x0000_0004,   // shift L / R
        59: 0x0000_0001, 62: 0x0000_2000,   // control L / R
        58: 0x0000_0020, 61: 0x0000_0040,   // option L / R
        55: 0x0000_0008, 54: 0x0000_0010,   // command L / R
        63: NSEvent.ModifierFlags.function.rawValue,
    ]

    init(totalKeyCount: Int = KeyboardLayout.totalKeyCount) {
        self.totalKeyCount = totalKeyCount
    }

    var progress: Double {
        totalKeyCount == 0 ? 0 : Double(testedKeyCodes.count) / Double(totalKeyCount)
    }

    var isComplete: Bool { testedKeyCodes.count >= totalKeyCount }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged, .systemDefined]) { [weak self] event in
            guard let self else { return event }
            if event.type == .systemDefined {
                self.handleMediaKey(event)
                return event // 媒体键照常交给系统（调亮度/音量），只是顺便记一笔
            }
            // 任何带 Command 的组合键都放行（Cmd+Q 退出、Cmd+Tab 切换、Cmd+. 取消等），
            // 保证全屏测试期间用户始终能安全退出。但状态机仍要更新，否则会丢 keyUp/修饰键松开。
            let passThrough = event.modifierFlags.contains(.command)
            self.handle(event, isShortcut: passThrough)
            return passThrough ? event : nil // 其余按键吞掉：不发出提示音、不误触其他控件
        }
        stuckCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkForStuckKeys() }
        }
        // 切到别的 App 时 keyUp 不会再送到这里，必须清空「按下」状态，否则回来后会误报卡键。
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.releaseAll() }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        stuckCheckTimer?.invalidate()
        stuckCheckTimer = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
    }

    /// 点击键位手动确认（再点一次取消）。
    func toggleManualConfirm(_ code: UInt16) {
        if manuallyConfirmed.contains(code) {
            manuallyConfirmed.remove(code)
            testedKeyCodes.remove(code)
        } else if !testedKeyCodes.contains(code) {
            manuallyConfirmed.insert(code)
            testedKeyCodes.insert(code)
        }
    }

    private func canonical(_ code: UInt16) -> UInt16 {
        KeyboardLayout.canonicalCode[code] ?? code
    }

    private func markTested(_ code: UInt16) {
        testedKeyCodes.insert(code)
        manuallyConfirmed.remove(code)
    }

    private func press(_ code: UInt16) {
        pressedKeyCodes.insert(code)
        if pressStartTimes[code] == nil { pressStartTimes[code] = Date() }
        stuckKeyCodes.remove(code)
    }

    private func release(_ code: UInt16) {
        pressedKeyCodes.remove(code)
        pressStartTimes[code] = nil
        stuckKeyCodes.remove(code)
    }

    private func releaseAll() {
        pressedKeyCodes.removeAll()
        pressStartTimes.removeAll()
        stuckKeyCodes.removeAll()
    }

    /// 只亮一下就熄灭（Caps Lock、媒体键等没有可靠 keyUp 的键）。
    private func flash(_ code: UInt16) {
        pressedKeyCodes.insert(code)
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            if self?.pressStartTimes[code] == nil { self?.pressedKeyCodes.remove(code) }
        }
    }

    private static let layoutCodes = Set(KeyboardLayout.allKeys.map(\.keyCode))

    private func handle(_ event: NSEvent, isShortcut: Bool) {
        let code = canonical(event.keyCode)
        // 布局外的键（小键盘、右 control 等）不计入进度，避免把「已测数」凑满
        guard Self.layoutCodes.contains(code) else { return }
        switch event.type {
        case .keyDown:
            markTested(code)
            // 带 ⌘ 的组合键可能被系统/菜单吃掉 keyUp，不进入「按住」状态，避免误判卡键。
            if isShortcut { flash(code) } else { press(code) }

        case .keyUp:
            if code == Self.escKeyCode, let start = pressStartTimes[code],
               Date().timeIntervalSince(start) >= Self.escHoldToExitSeconds {
                onRequestFinish?()
            }
            release(code)

        case .flagsChanged:
            markTested(code)
            if code == Self.capsLockKeyCode {
                flash(code) // Caps Lock 是锁定键，标志位表示「开/关」而非「按着」
            } else if let mask = Self.modifierMasks[code] {
                if event.modifierFlags.rawValue & mask != 0 { press(code) } else { release(code) }
            } else {
                flash(code)
            }

        default:
            break
        }
    }

    /// 顶排媒体键（亮度、音量、播放…）：NSEvent.systemDefined，subtype 8，
    /// data1 高 16 位是 NX_KEYTYPE，第 8–15 位为 0x0A 表示按下、0x0B 表示松开。
    private func handleMediaKey(_ event: NSEvent) {
        guard event.subtype.rawValue == 8 else { return }
        let keyType = UInt16((event.data1 & 0xFFFF_0000) >> 16)
        let isDown = ((event.data1 & 0xFF00) >> 8) == 0x0A
        guard isDown else { return }
        let code = canonical(KeyboardLayout.mediaBase + keyType)
        guard code < KeyboardLayout.mediaBase else { return } // 不是布局里的键（如电源键）
        markTested(code)
        flash(code)
    }

    private func checkForStuckKeys() {
        let now = Date()
        for (code, start) in pressStartTimes {
            // 以键盘硬件的实时状态为准：漏收 keyUp（被系统拦截、窗口失焦）时这里会发现键其实已松开，
            // 直接清掉，不误报。只有硬件确认「一直按着」超过阈值才标为卡键。
            guard CGEventSource.keyState(.hidSystemState, key: CGKeyCode(code)) else {
                release(code)
                continue
            }
            if now.timeIntervalSince(start) > Self.stuckThresholdSeconds {
                stuckKeyCodes.insert(code)
            }
        }
    }

    /// 生成本项检测结果：完全测过且无卡键 → pass；有卡键 → warning；未测完就退出 → 按已测覆盖率降级。
    func buildResult() -> CheckResult {
        var details: [String: String] = [
            L("已测键位数", "Keys tested"): "\(testedKeyCodes.count) / \(totalKeyCount)",
        ]
        if !manuallyConfirmed.isEmpty {
            details[L("手动确认的键", "Manually confirmed keys")] = labels(manuallyConfirmed)
        }
        let title = L("键盘测试", "Keyboard Test")
        if !stuckKeyCodes.isEmpty {
            let names = labels(stuckKeyCodes)
            details[L("疑似卡键", "Possibly stuck keys")] = names
            return CheckResult(
                id: "keyboard",
                title: title,
                status: .warning,
                summary: L("检测到疑似卡键：\(names)，建议重点复测这几个键", "Possibly stuck keys: \(names). Re-test these keys carefully."),
                rawDetails: details
            )
        }
        if isComplete {
            return CheckResult(
                id: "keyboard",
                title: title,
                status: .pass,
                summary: L("已逐键测试全部 \(totalKeyCount) 个按键，均正常响应", "All \(totalKeyCount) keys tested one by one and responded normally"),
                rawDetails: details
            )
        }
        return CheckResult(
            id: "keyboard",
            title: title,
            status: .warning,
            summary: L(
                "仅测试了 \(testedKeyCodes.count)/\(totalKeyCount) 个按键就退出，建议重新完整测试一遍",
                "Only \(testedKeyCodes.count)/\(totalKeyCount) keys were tested before exiting. Run the full test again."
            ),
            rawDetails: details
        )
    }

    private func labels(_ codes: Set<UInt16>) -> String {
        KeyboardLayout.allKeys.filter { codes.contains($0.keyCode) }.map(\.label).joined(separator: ", ")
    }
}
