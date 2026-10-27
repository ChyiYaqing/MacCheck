import SwiftUI
import AVFoundation
import AppKit

/// B4：麦克风测试。实时显示输入电平，用户对着麦克风说话看电平是否跳动。
@MainActor
final class MicrophoneCheckModel: ObservableObject {
    @Published var level: Double = 0        // 0...1
    @Published var peak: Double = 0
    @Published var isRunning = false
    @Published var permissionDenied = false
    @Published var statusText = L("准备中…", "Getting ready…")
    @Published var errorText: String?

    private let engine = AVAudioEngine()

    func start() {
        guard !isRunning else { return }
        permissionDenied = false
        errorText = nil

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            beginTap()
        case .notDetermined:
            statusText = L("等待麦克风授权…", "Waiting for microphone permission…")
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted {
                        self.beginTap()
                    } else {
                        self.showPermissionDenied()
                    }
                }
            }
        case .denied, .restricted:
            showPermissionDenied()
        @unknown default:
            showPermissionDenied()
        }
    }

    private func showPermissionDenied() {
        permissionDenied = true
        isRunning = false
        statusText = L("麦克风权限未开启", "Microphone access is off")
        errorText = L("请在系统设置中允许 MacCheck 访问麦克风，然后重新打开此测试。", "Allow MacCheck to use the microphone in System Settings, then reopen this test.")
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    func retry() {
        stop()
        start()
    }

    private func beginTap() {
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.channelCount > 0 else {
            errorText = L("未检测到可用的麦克风输入设备。", "No microphone input device found.")
            statusText = L("无法启动监听", "Couldn't start listening")
            return
        }

        input.removeTap(onBus: 0)
        let block: @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void = { [weak self] buffer, _ in
            let normalized = MicrophoneCheckModel.level(from: buffer)
            DispatchQueue.main.async {
                self?.updateLevel(normalized)
            }
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: block)
        do {
            engine.prepare()
            try engine.start()
            isRunning = true
            statusText = L("正在监听…", "Listening…")
        } catch {
            input.removeTap(onBus: 0)
            isRunning = false
            statusText = L("无法启动监听", "Couldn't start listening")
            errorText = L("麦克风监听启动失败：\(error.localizedDescription)", "Couldn't start the microphone: \(error.localizedDescription)")
        }
    }

    /// 纯函数、无隔离：在音频线程安全地算 RMS 电平。
    nonisolated private static func level(from buffer: AVAudioPCMBuffer) -> Double {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let frames = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<frames { sum += channel[i] * channel[i] }
        let rms = frames > 0 ? sqrt(sum / Float(frames)) : 0
        return min(1.0, Double(rms) * 8)
    }

    private func updateLevel(_ value: Double) {
        level = value
        peak = max(peak * 0.92, value)
    }

    func stop() {
        if isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            isRunning = false
        }
    }
}

struct MicrophoneCheckView: View {
    @StateObject private var model = MicrophoneCheckModel()
    let onComplete: (CheckResult) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            CheckHeader(
                icon: "mic.fill",
                title: L("麦克风测试", "Microphone Test"),
                subtitle: L("对着麦克风说话或发出声音，观察下方电平条是否随声音跳动。", "Talk or make a sound near the mic and watch whether the level bar below moves with it.")
            )

            if model.permissionDenied {
                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    InlineNotice(icon: "exclamationmark.triangle.fill", tint: .orange,
                        text: model.errorText ?? L("麦克风权限被拒绝。请在「系统设置 › 隐私与安全性 › 麦克风」中允许 MacCheck。", "Microphone access was denied. Allow MacCheck in System Settings › Privacy & Security › Microphone."))
                    HStack(spacing: DS.Spacing.md) {
                        Button {
                            model.openPrivacySettings()
                        } label: {
                            Label(L("打开麦克风权限设置", "Open Microphone Settings"), systemImage: "gearshape")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            model.retry()
                        } label: {
                            Label(L("重新检测", "Try Again"), systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } else {
                levelMeter
                if let error = model.errorText {
                    InlineNotice(icon: "exclamationmark.triangle.fill", tint: .orange, text: error)
                }
            }

            DS.Divider()

            HStack(spacing: DS.Spacing.md) {
                Text(L("测试结果：", "Result:")).font(DS.Font.body).foregroundStyle(.secondary)
                Button(L("电平正常跳动", "Level Moves Normally")) {
                    model.stop()
                    onComplete(CheckResult(id: "microphone", title: L("麦克风", "Microphone"), status: .pass,
                        summary: L("麦克风可正常拾音，电平随声音跳动", "Microphone picks up sound; the level moves with your voice")))
                }
                .buttonStyle(.borderedProminent)
                Button(L("无反应 / 异常", "No Response / Problem")) {
                    model.stop()
                    onComplete(CheckResult(id: "microphone", title: L("麦克风", "Microphone"), status: .warning,
                        summary: L("麦克风电平无跳动或异常，建议进一步检查", "Microphone level didn't move or behaved oddly; worth a closer look")))
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(DS.Spacing.xl)
        .checkPane(L("麦克风", "Microphone"))
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    private var levelMeter: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.12))
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(colors: [.green, .yellow, .red], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * model.level)
                        .animation(.easeOut(duration: 0.08), value: model.level)
                }
            }
            .frame(height: 28)
            Text(model.statusText)
                .font(DS.Font.caption).foregroundStyle(.secondary)
        }
    }
}
