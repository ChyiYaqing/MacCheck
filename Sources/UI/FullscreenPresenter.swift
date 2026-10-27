import AppKit
import SwiftUI

/// 无边框窗口默认不能成为 key window，键盘测试需要收到按键，必须放开。
private final class FullscreenTestWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// 键盘 / 屏幕测试的真·全屏呈现（issue #5：原先叠在主窗口里，标题栏和菜单栏那一条测不到）。
/// 用独立的无边框窗口铺满整块屏幕的 `frame`（含菜单栏区域与刘海两侧），层级高于菜单栏和程序坞。
@MainActor
enum FullscreenPresenter {
    private static var window: NSWindow?

    static func present<Content: View>(_ content: Content, on screen: NSScreen?) {
        dismiss()
        guard let screen = screen ?? NSScreen.main else { return }
        let window = FullscreenTestWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = true   // 切到别的 App 时让出屏幕，切回来自动恢复
        window.backgroundColor = .black
        window.hasShadow = false
        window.contentView = NSHostingView(rootView: content.ignoresSafeArea())
        window.setFrame(screen.frame, display: true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    static func dismiss() {
        window?.orderOut(nil)
        window = nil
    }
}
