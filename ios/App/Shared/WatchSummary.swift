import Foundation

/// Compact daily summary the iPhone pushes to the watch (and the watch's water request back).
struct WatchSummary: Codable, Equatable {
    var date: String
    var kcalConsumed: Double
    var kcalTarget: Double?
    var waterML: Double
    var waterTarget: Double
    var steps: Double?
    var updatedAt: Date

    var kcalRemaining: Double? { kcalTarget.map { $0 - kcalConsumed } }
    var kcalProgress: Double { guard let target = kcalTarget, target > 0 else { return 0 }; return min(1, max(0, kcalConsumed / target)) }
    var waterProgress: Double { waterTarget > 0 ? min(1, max(0, waterML / waterTarget)) : 0 }

    static let contextKey = "summary"
    func encoded() -> [String: Any]? { (try? JSONEncoder().encode(self)).map { [Self.contextKey: $0] } }
    static func decode(_ context: [String: Any]) -> WatchSummary? {
        guard let data = context[contextKey] as? Data else { return nil }
        return try? JSONDecoder().decode(WatchSummary.self, from: data)
    }
    /// Message keys for a water request from the watch (validated again on the phone).
    static let waterAction = "addWater"
    static func validWater(_ ml: Any?) -> Int? { guard let ml = ml as? Int, (50...1000).contains(ml) else { return nil }; return ml }
}
