import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
    public subscript(_ key: String) -> JSONValue { if case .object(let v) = self { return v[key] ?? .null }; return .null }
    public var stringValue: String? { if case .string(let v) = self { return v }; return nil }
    public var doubleValue: Double? { if case .number(let v) = self { return v }; return nil }
    public var boolValue: Bool? { if case .bool(let v) = self { return v }; return nil }
    public var arrayValue: [JSONValue] { if case .array(let v) = self { return v }; return [] }
}

public struct HealthRow: Codable, Identifiable, Sendable {
    public let id: String
    public let owner_user_id: String
    public let data: JSONValue
    public let version: Int
    public let deleted_at: String?
    public init(id: String, owner_user_id: String, data: JSONValue, version: Int, deleted_at: String? = nil) {
        self.id = id; self.owner_user_id = owner_user_id; self.data = data; self.version = version; self.deleted_at = deleted_at
    }
}

public enum CoreError: Error { case invalidWorkout, invalidTimeZone, invalidOwner }

public struct AppleWorkout: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let activityType: UInt
    public let sourceName: String
    public let start: Date
    public let end: Date
    public let duration: Double
    public let energyKcal: Double?
    public let distanceMeters: Double?
    public init(id: UUID, name: String, activityType: UInt, sourceName: String, start: Date, end: Date, duration: Double, energyKcal: Double?, distanceMeters: Double?) {
        self.id = id; self.name = name; self.activityType = activityType; self.sourceName = sourceName
        self.start = start; self.end = end; self.duration = duration; self.energyKcal = energyKcal; self.distanceMeters = distanceMeters
    }
    public func sourceKey(owner: String) throws -> String {
        guard let ownerID = UUID(uuidString: owner) else { throw CoreError.invalidOwner }
        return "apple-health/\(ownerID.uuidString.lowercased())/\(id.uuidString.lowercased())"
    }
    public func payload(timeZone: String) throws -> JSONValue {
        guard let zone = TimeZone(identifier: timeZone) else { throw CoreError.invalidTimeZone }
        guard start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite, end >= start,
              duration.isFinite, duration > 0, duration <= 604_800,
              energyKcal.map({ $0.isFinite && $0 >= 0 && $0 <= 100_000 }) ?? true,
              distanceMeters.map({ $0.isFinite && $0 >= 0 && $0 <= 10_000_000 }) ?? true else { throw CoreError.invalidWorkout }
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = DateFormatter(); date.locale = Locale(identifier: "en_US_POSIX"); date.timeZone = zone; date.dateFormat = "yyyy-MM-dd"
        return .object([
            "date": .string(date.string(from: start)), "planId": .null, "name": .string(String(name.prefix(150))),
            "status": .string("completed"), "quick": .bool(true), "startedAt": .string(iso.string(from: start)),
            "endedAt": .string(iso.string(from: end)), "notes": .string("Apple Health"), "exercises": .array([]),
            "appleHealth": .object([
                "uuid": .string(id.uuidString.lowercased()), "sourceName": .string(String(sourceName.prefix(200))),
                "activityType": .number(Double(activityType)), "durationSeconds": .number(duration),
                "energyKcal": energyKcal.map(JSONValue.number) ?? .null,
                "distanceMeters": distanceMeters.map(JSONValue.number) ?? .null
            ])
        ])
    }
}

public func pendingAppleWorkouts(_ workouts: [AppleWorkout], existing: Set<String>) -> [AppleWorkout] {
    var seen = Set(existing.map { $0.lowercased() })
    return workouts.sorted { $0.start > $1.start }.filter { seen.insert($0.id.uuidString.lowercased()).inserted }
}

public func nutrientTotal(meals: [HealthRow], nutrient: String) -> Double {
    meals.flatMap { $0.data["items"].arrayValue }.reduce(0) { total, item in
        guard let amount = item["quantity"].doubleValue, amount.isFinite, amount > 0,
              let value = item["food"]["per100"][nutrient].doubleValue, value.isFinite, value >= 0 else { return total }
        // A quantity already has its food's g/ml basis. No density conversion.
        return total + amount * value / 100
    }
}
