import Foundation
import Combine
import WellnessCore

@MainActor
final class AppStore: ObservableObject {
    enum Phase: Equatable { case starting, signedOut, signedIn, retry }
    @Published private(set) var phase: Phase = .starting
    @Published private(set) var session: Session?
    @Published private(set) var loading = false
    @Published private(set) var busy = false
    @Published var error: String?
    @Published var selectedDate = Date()
    @Published private(set) var meals: [HealthRow] = []
    @Published private(set) var goals: [HealthRow] = []
    @Published private(set) var plans: [HealthRow] = []
    @Published private(set) var workouts: [HealthRow] = []
    @Published private(set) var profile: JSONValue = .null
    @Published private(set) var candidates: [AppleWorkout] = []
    @Published private(set) var steps: Double?
    @Published private(set) var healthLoaded = false
    @Published var selection: Set<UUID> = []
    @Published var importMessage: String?
    let health = HealthReader()
    private let backend: Backend?
    private var revision = 0
    private var healthRevision = 0
    init() {
        let info = Bundle.main.infoDictionary ?? [:]
        if let host = info["SUPABASE_HOST"] as? String, !host.contains("/"),
           let root = URL(string: "https://\(host)"), let key = info["SUPABASE_PUBLIC_KEY"] as? String {
            backend = try? Backend(root: root, publicKey: key, vault: KeychainVault())
        } else { backend = nil }
    }
    var timeZone: TimeZone { TimeZone(identifier: profile["timezone"].stringValue ?? "") ?? .current }
    var dateKey: String { Self.dateKey(selectedDate, zone: timeZone) }
    static func dateKey(_ date: Date, zone: TimeZone) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = zone; f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
    var goal: JSONValue {
        goals.filter { ($0.data["date"].stringValue ?? "9999") <= dateKey }
            .max { ($0.data["date"].stringValue ?? "") < ($1.data["date"].stringValue ?? "") }?.data ?? .null
    }
    var dayMeals: [HealthRow] { meals.filter { $0.data["date"].stringValue == dateKey }.reversed() }
    var activePlans: [HealthRow] { plans.filter { $0.data["archived"].boolValue != true } }
    var importedIDs: Set<String> { Set(workouts.compactMap { $0.data["appleHealth"]["uuid"].stringValue }) }

    func start() async {
        guard phase == .starting || phase == .retry else { return }
        guard let backend else { error = "צריך להגדיר את חיבור האפליקציה לפני הבנייה. ההוראות נמצאות ב־ios/README.md."; phase = .retry; return }
        error = nil
        do {
            session = try await backend.restore()
            phase = session == nil ? .signedOut : .signedIn
            if session != nil { await refresh() }
        } catch {
            if let e = error as? BackendError, e == .sessionRequired || e == .sessionChanged {
                await backend.signOut(); phase = .signedOut
            } else { self.error = Self.message(error); phase = .retry }
        }
    }
    func login(_ pin: String) async {
        guard !busy, let backend else { return }
        busy = true; error = nil
        defer { busy = false }
        do { session = try await backend.login(pin: pin); phase = .signedIn; await refresh() }
        catch { self.error = Self.message(error) }
    }
    func refresh() async {
        guard let owner = session?.owner, let backend else { return }
        revision += 1; let request = revision; loading = true
        defer { if request == revision { loading = false } }
        do {
            async let m = backend.rows(table: "meals", owner: owner)
            async let g = backend.rows(table: "nutrition_goals", owner: owner)
            async let p = backend.rows(table: "workout_plans", owner: owner)
            async let w = backend.rows(table: "workout_sessions", owner: owner)
            async let h = backend.rows(table: "health_profiles", owner: owner)
            let snapshot = try await (m, g, p, w, h)
            guard request == revision, session?.owner == owner else { return }
            meals = snapshot.0; goals = snapshot.1; plans = snapshot.2; workouts = snapshot.3; profile = snapshot.4.first?.data ?? .null
            candidates = pendingAppleWorkouts(candidates, existing: importedIDs)
            selection.formIntersection(Set(candidates.map(\.id)))
        } catch { if request == revision, session?.owner == owner { self.error = Self.message(error) } }
    }
    func readHealth() async {
        guard !busy, let owner = session?.owner else { return }
        busy = true; error = nil; importMessage = nil
        healthRevision += 1; let request = healthRevision
        defer { if request == healthRevision { busy = false } }
        do {
            try await health.requestAccess()
            let found = try await health.workouts()
            let count = try? await health.todaySteps()
            guard session?.owner == owner, request == healthRevision else { return }
            candidates = pendingAppleWorkouts(found, existing: importedIDs); steps = count
            selection = []; healthLoaded = true
        } catch { if session?.owner == owner, request == healthRevision { self.error = "לא הצלחנו לקרוא את הפעילות. אפשר לנסות שוב ולבדוק הרשאות ביישום בריאות." } }
    }
    func importSelected() async {
        guard !busy, let owner = session?.owner, let backend else { return }
        let chosen = candidates.filter { selection.contains($0.id) }
        guard !chosen.isEmpty else { return }
        busy = true; error = nil; importMessage = nil
        healthRevision += 1; let request = healthRevision
        let zone = timeZone.identifier
        defer { if request == healthRevision { busy = false } }
        var saved: Set<UUID> = []
        do {
            for workout in chosen {
                guard session?.owner == owner, request == healthRevision else { throw BackendError.sessionChanged }
                let payload = try workout.payload(timeZone: zone)
                let id = try HealthReader.rowID(workout, owner: owner)
                try await backend.insertImportedWorkout(id: id, owner: owner, payload: payload)
                saved.insert(workout.id)
            }
        } catch { if session?.owner == owner { self.error = "הייבוא נעצר. \(saved.count) אימונים נשמרו; אפשר לנסות שוב בלי ליצור כפילויות." } }
        guard session?.owner == owner, request == healthRevision else { return }
        candidates.removeAll { saved.contains($0.id) }; selection.subtract(saved)
        if saved.count == chosen.count { importMessage = "נוספו \(saved.count) אימונים" }
        await refresh()
    }
    func logout() async {
        revision += 1; healthRevision += 1
        session = nil; meals = []; goals = []; plans = []; workouts = []; profile = .null
        candidates = []; selection = []; steps = nil; healthLoaded = false; importMessage = nil; error = nil
        busy = false; loading = false; phase = .starting
        await backend?.signOut()
        phase = .signedOut
    }
    func removeImportedWorkout(_ row: HealthRow) async -> Bool {
        guard !busy, let owner = session?.owner, let backend else { return false }
        busy = true
        defer { if session?.owner == owner { busy = false } }
        do {
            try await backend.removeImportedWorkout(row, owner: owner)
            guard session?.owner == owner else { return false }
            workouts.removeAll { $0.id == row.id }
            return true
        } catch { if session?.owner == owner { self.error = "לא הצלחנו למחוק את האימון. רענן את הנתונים ונסה שוב." }; return false }
    }
    func imageData(_ path: String) async -> Data? {
        guard let owner = session?.owner, let backend else { return nil }
        let data = try? await backend.imageData(path: path, owner: owner)
        guard session?.owner == owner else { return nil }
        return data
    }
    static func message(_ error: Error) -> String {
        switch error {
        case BackendError.invalidPIN: return "הקוד לא התקבל. בדוק את ארבע הספרות ונסה שוב."
        case BackendError.rateLimited: return "היו הרבה ניסיונות כניסה. המתן מעט ונסה שוב."
        case BackendError.sessionRequired, BackendError.sessionChanged: return "צריך להתחבר מחדש."
        case BackendError.connection: return "אין חיבור לשרת. נסה שוב בעוד רגע."
        default: return "לא הצלחנו להשלים את הפעולה. אפשר לנסות שוב."
        }
    }
}
