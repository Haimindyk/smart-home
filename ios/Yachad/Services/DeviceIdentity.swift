import Foundation

/// The whole "no login/signup" identity model: a random id generated once
/// per install and stored in UserDefaults (not Keychain — like the
/// website's localStorage picker, this is an attribution key, not a
/// security secret; see backend migration 0002 for what actually gates
/// access). A person only ever types a nickname, per area, when they create
/// or join it.
final class DeviceIdentity {
    static let shared = DeviceIdentity()

    private let defaultsKey = "yachad.deviceId"
    let id: UUID

    private init() {
        let defaults = UserDefaults.standard
        if let stored = defaults.string(forKey: defaultsKey), let uuid = UUID(uuidString: stored) {
            self.id = uuid
        } else {
            let fresh = UUID()
            defaults.set(fresh.uuidString, forKey: defaultsKey)
            self.id = fresh
        }
    }
}
