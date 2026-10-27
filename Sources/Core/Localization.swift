import Foundation

/// 界面语言（issue #3）。默认跟随系统：系统首选语言是中文则显示中文，其余一律英文。
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, zh, en

    static let storageKey = "appLanguage"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return L("跟随系统", "System")
        case .zh: return "中文"
        case .en: return "English"
        }
    }

    static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }

    /// 当前是否显示英文。线程安全，可在后台检测任务里调用。
    static var isEnglish: Bool {
        switch current {
        case .zh: return false
        case .en: return true
        case .system: return !(Locale.preferredLanguages.first ?? "zh").hasPrefix("zh")
        }
    }
}

/// 双语文案：中文在前、英文在后，按当前界面语言取其一。
/// 用法：`L("电池", "Battery")`、`L("共 \(n) 项", "\(n) items")`。
func L(_ zh: String, _ en: String) -> String {
    AppLanguage.isEnglish ? en : zh
}
