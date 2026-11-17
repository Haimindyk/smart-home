import SwiftUI
import WatchConnectivity

@main
struct WellnessWatchApp: App {
    @StateObject private var model = WatchModel()
    var body: some Scene {
        WindowGroup {
            WatchHome()
                .environmentObject(model)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "he_IL"))
        }
    }
}

/// Receives the daily summary from the iPhone and sends water requests back.
final class WatchModel: NSObject, ObservableObject, WCSessionDelegate {
    @Published var summary: WatchSummary?
    @Published var pendingWater = 0
    @Published var feedback = 0
    override init() {
        super.init()
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--demo") {
            summary = WatchSummary(date: "2026-11-17", kcalConsumed: 1240, kcalTarget: 1800, waterML: 750, waterTarget: 2000, steps: 6420, updatedAt: Date())
            return
        }
#endif
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        summary = WatchSummary.decode(session.receivedApplicationContext)
    }
    func addWater(_ ml: Int) {
        pendingWater += ml; feedback += 1
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        let message: [String: Any] = ["action": WatchSummary.waterAction, "ml": ml]
        if session.isReachable { session.sendMessage(message, replyHandler: nil, errorHandler: { _ in session.transferUserInfo(message) }) }
        else { session.transferUserInfo(message) }
    }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { if let s = WatchSummary.decode(session.receivedApplicationContext) { self.summary = s } }
    }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let s = WatchSummary.decode(applicationContext) else { return }
        DispatchQueue.main.async { self.summary = s; self.pendingWater = 0 }
    }
}
