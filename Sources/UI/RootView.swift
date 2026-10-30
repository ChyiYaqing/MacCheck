import SwiftUI

struct RootView: View {
    @StateObject private var model = AppModel()
    @StateObject private var iosModel = IOSDeviceModel()
    @AppStorage("appTheme") private var themeRawValue = AppTheme.system.rawValue
    @AppStorage(AppLanguage.storageKey) private var languageRawValue = AppLanguage.system.rawValue

    private var preferredScheme: ColorScheme? {
        (AppTheme(rawValue: themeRawValue) ?? .system).colorScheme
    }

    var body: some View {
        ZStack {
            NavigationSplitView {
                SidebarView()
            } detail: {
                DetailRouter()
            }
            .disabled(model.fullscreenTest != nil)
            // 语言切换后整棵视图重建，所有 L(...) 文案即时刷新
            .id(languageRawValue)
        }
        .environmentObject(model)
        .environmentObject(iosModel)
        .preferredColorScheme(preferredScheme)
        .task { await model.scanIfNeeded() }
        .task { await iosModel.monitor() }
        .onChange(of: languageRawValue) {
            // 自动检测结果的文案是扫描时生成的，切换语言后重扫一遍
            Task { await model.rescan() }
            iosModel.rescanAll()
        }
        .onChange(of: model.fullscreenTest?.id) {
            if let test = model.fullscreenTest {
                let screen = NSApp.keyWindow?.screen ?? NSApp.mainWindow?.screen
                FullscreenPresenter.present(fullscreenContent(test), on: screen)
            } else {
                FullscreenPresenter.dismiss()
            }
        }
    }

    @ViewBuilder
    private func fullscreenContent(_ test: FullscreenTest) -> some View {
        switch test {
        case .keyboard:
            KeyboardCheckView { result in
                model.recordTest(result)
                model.fullscreenTest = nil
            }
        case .screen:
            ScreenCheckView { result in
                model.recordTest(result)
                model.fullscreenTest = nil
            }
        }
    }
}
