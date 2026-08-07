import SwiftUI

@main
struct YachadApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(PushService.shared)
                .environment(\.layoutDirection, appState.locale.isRTL ? .rightToLeft : .leftToRight)
                .preferredColorScheme(nil)
                .task { await PushService.shared.refreshAuthorizationStatus() }
        }
    }
}
