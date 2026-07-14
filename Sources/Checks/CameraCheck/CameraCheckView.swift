import SwiftUI
import AVFoundation

/// B6：摄像头测试。打开预览画面，用户确认画面清晰、无坏点/色斑。
@MainActor
final class CameraCheckModel: ObservableObject {
    @Published var permissionDenied = false
    @Published var isRunning = false
    let session = AVCaptureSession()

    func start() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                if granted { self.configure() } else { self.permissionDenied = true }
            }
        }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .high
        if let device = AVCaptureDevice.default(for: .video),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        } else {
            permissionDenied = true
            session.commitConfiguration()
            return
        }
        session.commitConfiguration()
        nonisolated(unsafe) let session = self.session
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
            DispatchQueue.main.async { [weak self] in self?.isRunning = true }
        }
    }

    func stop() {
        if session.isRunning { session.stopRunning() }
        isRunning = false
    }
}

/// AVCaptureVideoPreviewLayer 的 SwiftUI 包装。
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        preview.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer = preview
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct CameraCheckView: View {
    @StateObject private var model = CameraCheckModel()
    let onComplete: (CheckResult) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            CheckHeader(
                icon: "camera.fill",
                title: "摄像头测试",
                subtitle: "观察下方预览画面：是否清晰、有无坏点、色斑或明显偏色。"
            )

            if model.permissionDenied {
                InlineNotice(icon: "exclamationmark.triangle.fill", tint: .orange,
                    text: "摄像头权限被拒绝。请在「系统设置 › 隐私与安全性 › 摄像头」中允许 MacCheck。")
            } else {
                CameraPreview(session: model.session)
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card))
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.card).strokeBorder(DS.Color.hairline))
            }

            DS.Divider()

            HStack(spacing: DS.Spacing.md) {
                Text("测试结果：").font(DS.Font.body).foregroundStyle(.secondary)
                Button("画面清晰正常") {
                    model.stop()
                    onComplete(CheckResult(id: "camera", title: "摄像头", status: .pass,
                        summary: "摄像头画面清晰，无坏点或异常"))
                }
                .buttonStyle(.borderedProminent)
                Button("画面异常") {
                    model.stop()
                    onComplete(CheckResult(id: "camera", title: "摄像头", status: .warning,
                        summary: "用户反馈画面异常，建议进一步检查摄像头"))
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(DS.Spacing.xl)
        .checkPane("摄像头")
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}
