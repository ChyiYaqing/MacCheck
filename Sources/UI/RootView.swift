import SwiftUI

struct RootView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        ZStack {
            NavigationSplitView {
                SidebarView()
            } detail: {
                DetailRouter()
            }
            .disabled(model.fullscreenTest != nil)

            if let test = model.fullscreenTest {
                fullscreenOverlay(test)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .environmentObject(model)
        .animation(.easeInOut(duration: 0.2), value: model.fullscreenTest?.id)
        .task { await model.scanIfNeeded() }
    }

    @ViewBuilder
    private func fullscreenOverlay(_ test: FullscreenTest) -> some View {
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
