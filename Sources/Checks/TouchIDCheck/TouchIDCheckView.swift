import SwiftUI
import LocalAuthentication

/// B10：Touch ID 测试。调起一次生物识别认证，验证指纹传感器工作正常。
struct TouchIDCheckView: View {
    let onComplete: (CheckResult) -> Void
    @State private var statusText = L("点击下方按钮，用注册的指纹验证一次。", "Click the button below and verify once with an enrolled fingerprint.")
    @State private var available = true
    @State private var reason = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            CheckHeader(
                icon: "touchid",
                title: L("Touch ID 测试", "Touch ID Test"),
                subtitle: L("验证指纹传感器能否正常识别。", "Checks that the fingerprint sensor recognizes your finger.")
            )

            if !available {
                InlineNotice(icon: "info.circle.fill", tint: .secondary,
                    text: reason.isEmpty ? L("本机不支持 Touch ID，或系统中未录入指纹。", "This Mac doesn't support Touch ID, or no fingerprints are enrolled.") : reason)
            } else {
                Text(statusText).font(DS.Font.body).foregroundStyle(.secondary)
                Button {
                    authenticate()
                } label: {
                    Label(L("开始指纹验证", "Start Fingerprint Check"), systemImage: "touchid")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            DS.Divider()

            Button(L("跳过此项", "Skip")) {
                onComplete(CheckResult(id: "touchID", title: "Touch ID", status: .skipped,
                    summary: L("用户跳过了 Touch ID 测试", "User skipped the Touch ID test")))
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
                reason = L("本机不支持 Touch ID，或系统中未录入指纹。", "This Mac doesn't support Touch ID, or no fingerprints are enrolled.")
            }
        }
    }

    private func authenticate() {
        let context = LAContext()
        context.localizedFallbackTitle = ""
        statusText = L("请将手指放在 Touch ID 上…", "Place your finger on Touch ID…")
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                               localizedReason: L("验证 Touch ID 传感器是否正常", "check that the Touch ID sensor works")) { success, authError in
            Task { @MainActor in
                if success {
                    onComplete(CheckResult(id: "touchID", title: "Touch ID", status: .pass,
                        summary: L("指纹识别成功，Touch ID 传感器工作正常", "Fingerprint recognized; the Touch ID sensor works")))
                } else {
                    let code = (authError as? LAError)?.code
                    if code == .userCancel || code == .systemCancel {
                        statusText = L("已取消，可再次尝试。", "Canceled. You can try again.")
                    } else {
                        statusText = L("识别失败，可重试或跳过。", "Not recognized. Try again or skip.")
                    }
                }
            }
        }
    }
}
