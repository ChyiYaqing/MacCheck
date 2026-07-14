import SwiftUI
import AVFoundation

/// B4：麦克风测试。实时显示输入电平，用户对着麦克风说话看电平是否跳动。
@MainActor
final class MicrophoneCheckModel: ObservableObject {
    @Published var level: Double = 0        // 0...1
    @Published var peak: Double = 0
    @Published var isRunning = false
    @Published var permissionDenied = false

    private let engine = AVAudioEngine()

    func start() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                if granted { self.beginTap() } else { self.permissionDenied = true }
            }
        }
    }

    private func beginTap() {
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        // 关键：tap 回调在 AVFoundation 的实时音频线程执行，必须是 @Sendable（非隔离）闭包，
        // 否则会继承外层 @MainActor 隔离、在音频线程触发执行器断言而崩溃。
        let block: @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void = { [weak self] buffer, _ in
            let normalized = MicrophoneCheckModel.level(from: buffer)
            DispatchQueue.main.async { self?.updateLevel(normalized) }
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: block)
        do {
            try engine.start()
            isRunning = true
        } catch {
            permissionDenied = true
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
                title: "麦克风测试",
                subtitle: "对着麦克风说话或发出声音，观察下方电平条是否随声音跳动。"
            )

            if model.permissionDenied {
                InlineNotice(icon: "exclamationmark.triangle.fill", tint: .orange,
                    text: "麦克风权限被拒绝。请在「系统设置 › 隐私与安全性 › 麦克风」中允许 MacCheck。")
            } else {
                levelMeter
            }

            DS.Divider()

            HStack(spacing: DS.Spacing.md) {
                Text("测试结果：").font(DS.Font.body).foregroundStyle(.secondary)
                Button("电平正常跳动") {
                    model.stop()
                    onComplete(CheckResult(id: "microphone", title: "麦克风", status: .pass,
                        summary: "麦克风可正常拾音，电平随声音跳动"))
                }
                .buttonStyle(.borderedProminent)
                Button("无反应 / 异常") {
                    model.stop()
                    onComplete(CheckResult(id: "microphone", title: "麦克风", status: .warning,
                        summary: "麦克风电平无跳动或异常，建议进一步检查"))
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(DS.Spacing.xl)
        .checkPane("麦克风")
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
            Text(model.isRunning ? "正在监听…" : "准备中…")
                .font(DS.Font.caption).foregroundStyle(.secondary)
        }
    }
}
