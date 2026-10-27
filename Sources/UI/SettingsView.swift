import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return L("跟随系统", "System")
        case .light: return L("浅色", "Light")
        case .dark: return L("深色", "Dark")
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct SettingsView: View {
    @AppStorage("appTheme") private var themeRawValue = AppTheme.system.rawValue
    @AppStorage(AppLanguage.storageKey) private var languageRawValue = AppLanguage.system.rawValue

    private var selectedTheme: Binding<AppTheme> {
        Binding {
            AppTheme(rawValue: themeRawValue) ?? .system
        } set: { newValue in
            themeRawValue = newValue.rawValue
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                CheckHeader(
                    icon: "gearshape.fill",
                    title: L("设置", "Settings"),
                    subtitle: L("调整 MacCheck 的显示偏好。设置会保存在本机，下次打开自动沿用。",
                                "Adjust how MacCheck looks. Settings are saved on this Mac and kept next time you open it.")
                )

                Card {
                    HStack(alignment: .top, spacing: DS.Spacing.md) {
                        Image(systemName: "paintpalette.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.tint)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                            Text(L("外观主题", "Appearance")).font(DS.Font.bodyEmphasis)
                            Text(L("选择跟随系统，或固定使用浅色 / 深色模式。", "Follow the system, or always use Light / Dark mode."))
                                .font(DS.Font.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Picker(L("外观主题", "Appearance"), selection: selectedTheme) {
                                ForEach(AppTheme.allCases) { theme in
                                    Label(theme.title, systemImage: theme.icon)
                                        .tag(theme)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .padding(.top, DS.Spacing.xs)
                        }
                    }
                }

                Card {
                    HStack(alignment: .top, spacing: DS.Spacing.md) {
                        Image(systemName: "globe")
                            .font(.system(size: 20))
                            .foregroundStyle(.tint)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                            Text(L("语言", "Language")).font(DS.Font.bodyEmphasis)
                            Text(L("默认跟随系统语言：系统为中文时显示中文，其余显示英文。切换后会自动重新扫描。",
                                   "Follows the macOS language by default: Chinese if your system is in Chinese, English otherwise. MacCheck rescans after switching."))
                                .font(DS.Font.body)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Picker(L("语言", "Language"), selection: $languageRawValue) {
                                ForEach(AppLanguage.allCases) { language in
                                    Text(language.title).tag(language.rawValue)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .padding(.top, DS.Spacing.xs)
                        }
                    }
                }
            }
            .padding(DS.Spacing.xl)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .navigationTitle(L("设置", "Settings"))
    }
}
