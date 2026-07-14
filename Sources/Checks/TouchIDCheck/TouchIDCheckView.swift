import SwiftUI
import LocalAuthentication

/// B10：Touch ID 测试。调起一次生物识别认证，验证指纹传感器工作正常。
struct TouchIDCheckView: View {
    let onComplete: (CheckResult) -> Void
    @State private var statusText = "点击下方按钮，用注册的指纹验证一次。"
    @State private var available = true
    @State private var reason = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            CheckHeader(
                icon: "touchid",
                title: "Touch ID 测试",
                subtitle: "验证指纹传感器能否正常识别。"
            )

            if !available {
                InlineNotice(icon: "info.circle.fill", tint: .secondary,
                    text: reason.isEmpty ? "本机不支持 Touch ID，或系统中未录入指纹。" : reason)
            } else {
                Text(statusText).font(DS.Font.body).foregroundStyle(.secondary)
                Button {
                    authenticate()
                } label: {
                    Label("开始指纹验证", systemImage: "touchid")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            DS.Divider()

            Button("跳过此项") {
                onComplete(CheckResult(id: "touchID", title: "Touch ID", status: .skipped,
                    summary: "用户跳过了 Touch ID 测试"))
            }
            .buttonStyle(.bordered)
        }
        .padding(DS.Spacing.xl)
        .checkPane("Touch ID")
        .onAppear { checkAvailability() }
    }

    private func checkAvailability() {
        let context = LAContext()
        var error: NSError?
        if !context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            available = false
            if context.biometryType == .none {
                reason = "本机不支持 Touch ID，或系统中未录入指纹。"
            }
        }
    }

    private func authenticate() {
        let context = LAContext()
        context.localizedFallbackTitle = ""
        statusText = "请将手指放在 Touch ID 上…"
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                               localizedReason: "验证 Touch ID 传感器是否正常") { success, authError in
            Task { @MainActor in
                if success {
                    onComplete(CheckResult(id: "touchID", title: "Touch ID", status: .pass,
                        summary: "指纹识别成功，Touch ID 传感器工作正常"))
                } else {
                    let code = (authError as? LAError)?.code
                    if code == .userCancel || code == .systemCancel {
                        statusText = "已取消，可再次尝试。"
                    } else {
                        statusText = "识别失败，可重试或跳过。"
                    }
                }
            }
        }
    }
}
