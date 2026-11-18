import Foundation

/// Daily nutrition targets (port of the web app's calculations.ts): adult Mifflin–St Jeor estimate, editable by the user.
public enum GoalCalculator {
    public struct Profile: Equatable, Sendable {
        public var birthDate: String?, height: Double?, weight: Double?, physiology: String?, activity: String, objective: String
        public init(birthDate: String? = nil, height: Double? = nil, weight: Double? = nil, physiology: String? = nil, activity: String = "light", objective: String = "maintain") {
            self.birthDate = birthDate; self.height = height; self.weight = weight; self.physiology = physiology; self.activity = activity; self.objective = objective
        }
    }
    public struct Goal: Equatable, Sendable { public let date: String, kcal: Int, protein: Int, carbs: Int, fat: Int, method: String }
    public enum Failure: Error, Equatable { case invalidBirthDate, adultProfileRequired }

    private static func valid(_ s: String) -> Bool {
        guard s.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil else { return false }
        let p = s.split(separator: "-").compactMap { Int($0) }
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
        guard let d = c.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) else { return false }
        return c.component(.day, from: d) == p[2] && c.component(.month, from: d) == p[1]
    }
    /// Calendar age on `date` (both `yyyy-MM-dd`), without time zones.
    public static func calendarAge(birthDate: String, on date: String) throws -> Int {
        guard valid(birthDate), valid(date), birthDate <= date else { throw Failure.invalidBirthDate }
        let age = Int(date.prefix(4))! - Int(birthDate.prefix(4))! - (String(date.dropFirst(5)) < String(birthDate.dropFirst(5)) ? 1 : 0)
        guard age <= 120 else { throw Failure.invalidBirthDate }
        return age
    }
    public static func calculate(_ p: Profile, on date: String) throws -> Goal {
        guard let birth = p.birthDate else { throw Failure.adultProfileRequired }
        let age = try calendarAge(birthDate: birth, on: date)
        guard age >= 18, let weight = p.weight, let height = p.height, let physiology = p.physiology else { throw Failure.adultProfileRequired }
        let sexTerm: Double = physiology == "male" ? 5 : -161
        let bmr: Double = 10 * weight + 6.25 * height - 5 * Double(age) + sexTerm
        let factors: [String: Double] = ["sedentary": 1.2, "light": 1.375, "moderate": 1.55, "high": 1.725]
        let multipliers: [String: Double] = ["lose": 0.9, "maintain": 1.0, "gain": 1.05]
        let factor: Double = factors[p.activity] ?? 1.375
        let multiplier: Double = multipliers[p.objective] ?? 1.0
        let raw: Double = Swift.max(bmr, bmr * factor * multiplier)
        let kcal: Int = Int(raw.rounded())
        let protein = Int((weight * 1.6).rounded()), fat = Int((Double(kcal) * 0.25 / 9).rounded())
        let carbsRaw: Double = Double(kcal - protein * 4 - fat * 9) / 4
        return Goal(date: date, kcal: kcal, protein: protein, carbs: Swift.max(0, Int(carbsRaw.rounded())), fat: fat, method: "calculated")
    }
}
