import Foundation
import WatchConnectivity

/// iPhone side of the watch link: pushes the daily summary and applies water requests from the watch.
@MainActor
final class PhoneConnectivity: NSObject, WCSessionDelegate {
    static let shared = PhoneConnectivity()
    private weak var store: AppStore?
    func start(store: AppStore) {
        self.store = store
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }
    func push(_ summary: WatchSummary) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled, let context = summary.encoded() else { return }
        try? session.updateApplicationContext(context)
    }
    private func handle(_ message: [String: Any]) {
        // The watch is untrusted input: only a bounded water amount is accepted, and only while signed in.
        guard message["action"] as? String == WatchSummary.waterAction, let ml = WatchSummary.validWater(message["ml"]) else { return }
        Task { await store?.addWater(ml) }
    }
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.store?.publishToWatch() }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { Task { @MainActor in self.handle(message) } }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) { Task { @MainActor in self.handle(userInfo) } }
}
