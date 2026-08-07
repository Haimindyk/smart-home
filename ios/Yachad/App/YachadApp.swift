import SwiftUI

@main
struct YachadApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environment(\.layoutDirection, appState.locale.isRTL ? .rightToLeft : .leftToRight)
                .preferredColorScheme(nil)
        }
    }
}
