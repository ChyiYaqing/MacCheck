import SwiftUI

/// 键盘可视化测试：按一下键，对应键位立刻在屏幕上亮起并保持"已测"状态——不是打字框。
struct KeyboardCheckView: View {
    @StateObject private var model = KeyboardTestModel()
    let onFinish: (CheckResult) -> Void

    private let keyUnit: CGFloat = 46
    private let keySpacing: CGFloat = 6

    var body: some View {
        VStack(spacing: 28) {
            header
            keyboardGrid
            footer
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            model.onRequestFinish = finish
            model.start()
        }
        .onDisappear { model.stop() }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text(L("键盘测试", "Keyboard Test"))
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
            Text(L("依次按下每一个按键，亮起代表已检测。长按 esc 键 1.2 秒可随时结束测试。",
                   "Press every key one by one — a key lights up once it's detected. Hold esc for 1.2 s to finish at any time."))
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.7))
            Text(L("顶排功能键直接按（调亮度/音量等）或 fn+F1…F12 都算。被系统快捷键占用、按了不亮的键（如 fn+F11「显示桌面」），按过后可点击键位手动确认。",
                   "Top-row keys count either as media keys (brightness, volume…) or as fn+F1…F12. If a key is captured by a system shortcut and doesn't light up (e.g. fn+F11 \"Show Desktop\"), press it, then click the key to confirm it manually."))
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 640)
            ProgressView(value: model.progress)
                .frame(width: 360)
            Text(L("\(model.testedKeyCodes.count) / \(model.totalKeyCount) 已测试", "\(model.testedKeyCodes.count) / \(model.totalKeyCount) tested"))
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var keyboardGrid: some View {
        VStack(spacing: keySpacing) {
            ForEach(Array(KeyboardLayout.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: keySpacing) {
                    ForEach(row) { key in
                        keyView(key)
                    }
                }
            }
        }
    }

    private func keyView(_ key: KeyDef) -> some View {
        let isPressed = model.pressedKeyCodes.contains(key.keyCode)
        let isStuck = model.stuckKeyCodes.contains(key.keyCode)
        let isTested = model.testedKeyCodes.contains(key.keyCode)
        let isManual = model.manuallyConfirmed.contains(key.keyCode)

        let fill: Color = isStuck ? .red : isPressed ? .green : isManual ? Color.orange.opacity(0.35)
            : isTested ? Color.green.opacity(0.35) : Color.white.opacity(0.08)
        let border: Color = isStuck ? .red : isManual ? .orange : isTested ? .green : Color.white.opacity(0.3)

        return Text(key.label)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: keyUnit * key.widthUnits, height: keyUnit)
            .background(RoundedRectangle(cornerRadius: 6).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(border, lineWidth: 1.5))
            .animation(.easeOut(duration: 0.12), value: isPressed)
            .contentShape(Rectangle())
            .onTapGesture { model.toggleManualConfirm(key.keyCode) }
            .help(L("按了不亮？点击手动确认此键", "Didn't light up? Click to confirm this key manually"))
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Button(L("结束并保存结果", "Finish and save")) { finish() }
                .keyboardShortcut(.cancelAction)
            if model.isComplete {
                Text(L("全部按键已测试完成 ✅", "All keys tested ✅")).foregroundStyle(.green)
            }
        }
        .buttonStyle(.bordered)
        .tint(.white)
    }

    private func finish() {
        onFinish(model.buildResult())
    }
}
