import Foundation
import UserNotifications
import UIKit
import Supabase

/// Push registration is per-device, not per-area (see backend migration
/// 0005) — request permission once, register for remote notifications, and
/// keep the uploaded APNs token in sync with what the OS hands back.
@MainActor
final class PushService: NSObject, ObservableObject {
    static let shared = PushService()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private var client: SupabaseClient { SupabaseService.shared }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    /// Shows the system permission prompt (only has an effect the first
    /// time — after that, iOS silently reuses the earlier answer) and, if
    /// granted, registers for remote notifications so the app receives a
    /// device token in `didRegisterForRemoteNotificationsWithDeviceToken`.
    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshAuthorizationStatus()
        guard granted else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    func didRegister(deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task {
            do {
                try await self.uploadToken(token)
            } catch {
                print("Yachad: failed to upload push token: \(error)")
            }
        }
    }

    private struct PushTokenUpsert: Encodable {
        let device_id: String
        let apns_token: String
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
    }

    private func uploadToken(_ token: String) async throws {
        _ = try await client
            .from("push_tokens")
            .upsert(PushTokenUpsert(device_id: DeviceIdentity.shared.id.uuidString, apns_token: token), onConflict: "device_id")
            .execute()
    }
}
