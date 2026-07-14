import SwiftUI
import AVFoundation

/// B3：扬声器/耳机口测试。分别播放左右声道扫频音，用户确认左右是否都正常。
@MainActor
final class AudioCheckModel: ObservableObject {
    @Published var playingChannel: Int? = nil   // 0 = 左, 1 = 右, nil = 停止

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var started = false

    private func makeBuffer(channel: Int) -> AVAudioPCMBuffer? {
        let sampleRate = 44_100.0
        let duration = 1.0
        let frames = AVAudioFrameCount(sampleRate * duration)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)
        else { return nil }
        buffer.frameLength = frames
        let freq = 440.0
        for frame in 0..<Int(frames) {
            let value = Float(sin(2.0 * Double.pi * freq * Double(frame) / sampleRate)) * 0.25
            buffer.floatChannelData?[0][frame] = channel == 0 ? value : 0
            buffer.floatChannelData?[1][frame] = channel == 1 ? value : 0
        }
        return buffer
    }

    func play(channel: Int) {
        guard let buffer = makeBuffer(channel: channel) else { return }
        if !started {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
            do { try engine.start(); started = true } catch { return }
        }
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        player.play()
        playingChannel = channel
    }

    func stop() {
        player.stop()
        playingChannel = nil
    }

    func teardown() {
        stop()
        if started { engine.stop() }
    }
}

struct AudioCheckView: View {
    @StateObject private var model = AudioCheckModel()
    let onComplete: (CheckResult) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            CheckHeader(
                icon: "speaker.wave.3.fill",
                title: "扬声器 / 耳机测试",
                subtitle: "分别播放左右声道，确认两侧都能听到清晰的声音。插入耳机可同时验证耳机接口。"
            )

            HStack(spacing: DS.Spacing.md) {
                channelButton(title: "播放左声道", channel: 0, icon: "l.circle.fill")
                channelButton(title: "播放右声道", channel: 1, icon: "r.circle.fill")
                Button {
                    model.stop()
                } label: {
                    Label("停止", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            DS.Divider()

            HStack(spacing: DS.Spacing.md) {
                Text("测试结果：").font(DS.Font.body).foregroundStyle(.secondary)
                Button("左右都正常") {
                    model.teardown()
                    onComplete(CheckResult(id: "audio", title: "扬声器 / 耳机", status: .pass,
                        summary: "左右声道均可正常播放", rawDetails: ["左声道": "正常", "右声道": "正常"]))
                }
                .buttonStyle(.borderedProminent)
                Button("有声道异常") {
                    model.teardown()
                    onComplete(CheckResult(id: "audio", title: "扬声器 / 耳机", status: .warning,
                        summary: "用户反馈有声道异常，建议进一步检查扬声器或耳机口",
                        rawDetails: ["用户判断": "存在异常"]))
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(DS.Spacing.xl)
        .checkPane("扬声器 / 耳机")
        .onDisappear { model.teardown() }
    }

    private func channelButton(title: String, channel: Int, icon: String) -> some View {
        Button {
            model.play(channel: channel)
        } label: {
            Label(title, systemImage: icon)
                .frame(minWidth: 130)
        }
        .buttonStyle(.borderedProminent)
        .tint(model.playingChannel == channel ? .accentColor : .gray)
        .controlSize(.large)
    }
}
