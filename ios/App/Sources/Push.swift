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
    private static let rows: [(key: String, title: String, icon: String, color: Color)] = [
        ("on_create", "פריט חדש נוצר", "plus.circle.fill", Color.proteinBlue), ("on_complete", "פריט סומן כבוצע", "checkmark.circle.fill", Color.kcalAmber),
        ("on_assigned_me", "שויכתי לפריט", "person.crop.circle.badge.checkmark", Color.carbsGold), ("on_shopping", "עדכונים ברשימת הקניות", "cart.fill", Color.proteinBlue),
        ("on_delete", "פריט נמחק", "trash.fill", Color.fatCoral), ("on_broadcast", "הודעות מבני הבית", "megaphone.fill", Color.fatCoral)]
    private var enabled: Bool { push.authorization == .authorized || push.authorization == .provisional }
    private func tile(_ symbol: String, _ color: Color, size: CGFloat = 34) -> some View {
        Image(systemName: symbol).font(.system(size: size * 0.44, weight: .semibold)).foregroundStyle(color).frame(width: size, height: size)
            .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 14) {
                    tile(enabled ? "bell.badge.fill" : "bell.slash.fill", Color.fatCoral, size: 64)
                    Text(enabled ? "ההתראות פעילות" : "קבל התראות מהבית").font(.hb(.title3, .bold))
                    Text("ההתראות מגיעות על שינויים של בני הבית אחרים, ולא על שינויים שעשית בעצמך.").font(.hb(.subheadline)).foregroundStyle(Color.wellnessSecondary).multilineTextAlignment(.center)
                    if push.authorization == .denied {
                        Text("התראות חסומות להגדרות המכשיר.").font(.hb(.footnote)).foregroundStyle(Color.fatCoralText)
                        Button("פתיחת הגדרות המכשיר") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }.buttonStyle(PrimaryButton())
                    } else if !enabled {
                        Button { Task { await push.enable() } } label: { Label("הפעלת התראות", systemImage: "bell.fill") }.buttonStyle(PrimaryButton()).accessibilityIdentifier("push-enable")
                    } else {
                        Label("מופעל במכשיר הזה", systemImage: "checkmark.circle.fill").font(.hb(.subheadline, .semibold)).foregroundStyle(Color.proteinBlue).accessibilityIdentifier("push-enable")
                    }
                    if push.failed { Text("ההרשמה להתראות נכשלה. נסה שוב בעוד רגע.").font(.hb(.footnote)).foregroundStyle(Color.fatCoralText) }
                }.frame(maxWidth: .infinity).wellnessCard(padding: 20)
                if enabled {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("על מה להתריע").sectionTitle().padding(.bottom, 6)
                        ForEach(Array(Self.rows.enumerated()), id: \.element.key) { index, row in
                            HStack(spacing: 12) {
                                tile(row.icon, row.color)
                                Toggle(row.title, isOn: Binding(get: { (prefs[row.key] ?? true) && prefs["muted"] != true }, set: { on in prefs[row.key] = on; save([row.key: on]) })).tint(Color.wellnessPrimary).disabled(prefs["muted"] == true)
                            }.padding(.vertical, 6)
                            if index < Self.rows.count - 1 { Divider().padding(.leading, 46) }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).wellnessCard(padding: 16)
                    HStack(spacing: 12) {
                        tile("moon.zzz.fill", Color.proteinBlue)
                        Toggle("השתקת כל ההתראות", isOn: Binding(get: { prefs["muted"] ?? false }, set: { on in prefs["muted"] = on; save(["muted": on]) })).tint(Color.wellnessPrimary).accessibilityIdentifier("push-mute")
                    }.wellnessCard(padding: 14)
                }
                Color.clear.frame(height: 24)
            }.padding(.horizontal, 16).padding(.top, 8)
        }
        .background(Color.wellnessCanvas.ignoresSafeArea()).navigationTitle("התראות").navigationBarTitleDisplayMode(.inline)
        .task { await push.refresh(); if !loaded { prefs = await store.notificationPrefs(); loaded = true } }
    }
    private func save(_ change: [String: Bool]) { Task { _ = await store.saveNotificationPrefs(change) } }
}
