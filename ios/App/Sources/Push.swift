import SwiftUI
import UIKit
import UserNotifications

/// Receives the APNs device token and shows notifications that arrive while the app is open.
final class PushAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in PushManager.shared.tokenReceived(deviceToken) }
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Task { @MainActor in PushManager.shared.registrationFailed() }
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound, .list] }
}

/// Permission, registration and token upload for push notifications.
@MainActor
final class PushManager: ObservableObject {
    static let shared = PushManager()
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
    @Published private(set) var deviceToken: String?
    @Published private(set) var failed = false
    private weak var store: AppStore?
    func bind(_ store: AppStore) { self.store = store; Task { await refresh() } }

    /// Reads the current permission; if it is already granted, makes sure this installation is registered (tokens can change).
    func refresh() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        if authorization == .authorized || authorization == .provisional { UIApplication.shared.registerForRemoteNotifications() }
    }
    /// Asks for permission (the system prompt appears once) and registers for remote notifications.
    @discardableResult
    func enable() async -> Bool {
        failed = false
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refresh()
        return granted
    }
    func tokenReceived(_ data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        deviceToken = token
        Task { await store?.registerPushToken(token) }
    }
    func registrationFailed() { failed = true }
    /// Called after sign-in so a token received before login is uploaded for the new member.
    func uploadIfPossible() async { if let token = deviceToken { await store?.registerPushToken(token) } }
}

/// Notification settings (the web app's notification dialog): permission and which events to hear about.
struct NotificationSettingsScreen: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var push = PushManager.shared
    @Environment(\.openURL) private var openURL
    @State private var prefs: [String: Bool] = [:]
    @State private var loaded = false
    private static let rows: [(key: String, title: String)] = [
        ("on_create", "פריט חדש נוצר"), ("on_complete", "פריט סומן כבוצע"), ("on_assigned_me", "שויכתי לפריט"),
        ("on_shopping", "עדכונים ברשימת הקניות"), ("on_delete", "פריט נמחק"), ("on_broadcast", "הודעות מבני הבית")]
    private var enabled: Bool { push.authorization == .authorized || push.authorization == .provisional }
    var body: some View {
        List {
            Section {
                if push.authorization == .denied {
                    Text("התראות חסומות להגדרות המכשיר.").font(.hb(.subheadline)).foregroundStyle(Color.wellnessSecondary)
                    Button("פתיחת הגדרות המכשיר") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
                } else {
                    Toggle(isOn: Binding(get: { enabled }, set: { on in if on { Task { await push.enable() } } })) { Label("קבלת התראות", systemImage: enabled ? "bell.fill" : "bell.slash") }
                        .tint(Color.wellnessPrimary).disabled(enabled).accessibilityIdentifier("push-enable")
                }
                if push.failed { Text("ההרשמה להתראות נכשלה. נסה שוב בעוד רגע.").font(.hb(.footnote)).foregroundStyle(Color.fatCoralText) }
            } footer: { Text("ההתראות מגיעות על שינויים של בני הבית אחרים, ולא על שינויים שעשית בעצמך.") }
            if enabled {
                Section("על מה להתריע") {
                    ForEach(Self.rows, id: \.key) { row in
                        Toggle(row.title, isOn: Binding(get: { (prefs[row.key] ?? true) && prefs["muted"] != true }, set: { on in prefs[row.key] = on; save([row.key: on]) })).tint(Color.wellnessPrimary).disabled(prefs["muted"] == true)
                    }
                    Toggle("השתקת כל ההתראות", isOn: Binding(get: { prefs["muted"] ?? false }, set: { on in prefs["muted"] = on; save(["muted": on]) })).tint(Color.wellnessPrimary).accessibilityIdentifier("push-mute")
                }
            }
        }
        .wellnessList().navigationTitle("התראות").navigationBarTitleDisplayMode(.inline)
        .task { await push.refresh(); if !loaded { prefs = await store.notificationPrefs(); loaded = true } }
    }
    private func save(_ change: [String: Bool]) { Task { _ = await store.saveNotificationPrefs(change) } }
}
