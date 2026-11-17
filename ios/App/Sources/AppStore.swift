import Foundation
import Combine
import WellnessCore

@MainActor
final class AppStore: ObservableObject {
    enum Phase: Equatable { case starting, signedOut, signedIn, signingOut, retry }
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
    private var profileRow: HealthRow?
    @Published private(set) var waterLogs: [HealthRow] = []
    @Published private(set) var weightLogs: [HealthRow] = []
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
#if DEBUG
        if let scenario = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--ui-test-") }) {
            // Simulator UI tests are fully synthetic and cannot reach a production API.
            backend = nil
            phase = scenario == "--ui-test-login" ? .signedOut : .signedIn
            if phase == .signedIn {
                session = Session(accessToken: "ui-test", refreshToken: "ui-test", owner: UITestFixtures.owner, member: "ui-test")
                profile = .object(["timezone": .string("UTC"), "birthDate": .string("1990-01-01"), "aiProviderConsent": .bool(scenario == "--ui-test-coach")])
                goals = UITestFixtures.goals(date: dateKey)
                if scenario == "--ui-test-meal" || scenario == "--ui-test-coach" { meals = UITestFixtures.meals(date: dateKey); workouts = UITestFixtures.workouts(date: dateKey); plans = UITestFixtures.plans(); weightLogs = UITestFixtures.weights(zone: timeZone) }
            }
            return
        }
#endif
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
            async let wl = backend.rows(table: "water_logs", owner: owner)
            async let wt = backend.rows(table: "weight_logs", owner: owner)
            let snapshot = try await (m, g, p, w, h)
            let extras = try await (wl, wt)
            guard request == revision, session?.owner == owner else { return }
            meals = snapshot.0; goals = snapshot.1; plans = snapshot.2; workouts = snapshot.3; profile = snapshot.4.first?.data ?? .null; profileRow = snapshot.4.first
            waterLogs = extras.0; weightLogs = extras.1
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
        session = nil; meals = []; goals = []; plans = []; workouts = []; profile = .null; profileRow = nil; waterLogs = []; weightLogs = []
        candidates = []; selection = []; steps = nil; healthLoaded = false; importMessage = nil; error = nil
        busy = false; loading = false; phase = .signingOut
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
    // MARK: - Writes (same rows and edge functions as the web app)
    var waterTarget: Double { profile["waterTarget"].doubleValue ?? 2000 }
    var dayWaterLogs: [HealthRow] { waterLogs.filter { $0.data["date"].stringValue == dateKey } }
    var dayWater: Double { dayWaterLogs.reduce(0) { $0 + ($1.data["amount"].doubleValue ?? 0) } }
    var latestWeight: Double? { weightLogs.max { ($0.data["date"].stringValue ?? "") < ($1.data["date"].stringValue ?? "") }?.data["weight"].doubleValue }

    private func write(_ failure: String, _ work: (Backend, String) async throws -> Void) async -> Bool {
        guard let owner = session?.owner, let backend else { return false }
        do { try await work(backend, owner); return session?.owner == owner }
        catch { if session?.owner == owner { self.error = error as? BackendError == .conflict ? "הנתון השתנה במקום אחר. רענן ונסה שוב." : failure }; return false }
    }
    func addWater(_ ml: Int) async {
        let date = dateKey
        _ = await write("לא הצלחנו לשמור את המים.") { backend, owner in
            let row = try await backend.save(table: "water_logs", owner: owner, payload: .object(["date": .string(date), "amount": .number(Double(ml))]))
            if session?.owner == owner { waterLogs.append(row) }
        }
    }
    func undoWater() async {
        guard let last = dayWaterLogs.last else { return }
        _ = await write("לא הצלחנו לבטל את הכוס האחרונה.") { backend, owner in
            try await backend.softDelete(table: "water_logs", row: last, owner: owner)
            if session?.owner == owner { waterLogs.removeAll { $0.id == last.id } }
        }
    }
    func logWeight(_ kg: Double) async -> Bool {
        guard kg >= 20, kg <= 400 else { return false }
        let date = dateKey
        return await write("לא הצלחנו לשמור את המשקל.") { backend, owner in
            let row = try await backend.save(table: "weight_logs", owner: owner, payload: .object(["date": .string(date), "weight": .number((kg * 10).rounded() / 10)]))
            if session?.owner == owner { weightLogs.append(row) }
        }
    }
    func searchFoods(query: String, barcode: String? = nil) async -> [JSONValue]? {
        guard let owner = session?.owner, let backend else { return nil }
        var body: [String: JSONValue] = ["query": .string(query), "labelOnly": .bool(false)]
        if let barcode { body["barcode"] = .string(barcode) }
        do {
            let result = try await backend.invoke("food-lookup", body: .object(body), owner: owner)
            return session?.owner == owner ? result["foods"].arrayValue : nil
        } catch { if session?.owner == owner { self.error = "החיפוש לא הושלם. בדוק חיבור ונסה שוב." }; return nil }
    }
    func saveMeal(kind: String, name: String, food: JSONValue, quantity: Double) async -> Bool {
        guard quantity > 0, quantity <= 10_000 else { return false }
        let date = dateKey
        let item: JSONValue = .object(["id": .string(UUID().uuidString.lowercased()), "food": food, "quantity": .number(quantity)])
        let payload: JSONValue = .object(["date": .string(date), "kind": .string(kind), "name": .string(name), "items": .array([item]), "imagePath": .null])
        return await write("לא הצלחנו לשמור את הארוחה.") { backend, owner in
            let row = try await backend.save(table: "meals", owner: owner, payload: payload)
            if session?.owner == owner { meals.append(row) }
        }
    }
    /// Latest distinct meals (by name), newest first, for one-tap re-logging.
    var recentMeals: [HealthRow] {
        var seen = Set<String>()
        return meals.sorted { ($0.data["date"].stringValue ?? "") > ($1.data["date"].stringValue ?? "") }.filter { meal in
            let name = meal.data["name"].stringValue?.isEmpty == false ? meal.data["name"].stringValue! : (meal.data["items"].arrayValue.first?["food"]["name"].stringValue ?? meal.id)
            return seen.insert(name).inserted
        }.prefix(8).map { $0 }
    }
    func relogMeal(_ source: HealthRow, kind: String) async -> Bool {
        let items = source.data["items"].arrayValue.map { item -> JSONValue in
            guard case .object(var fields) = item else { return item }
            fields["id"] = .string(UUID().uuidString.lowercased()); return .object(fields)
        }
        guard !items.isEmpty else { return false }
        let payload: JSONValue = .object(["date": .string(dateKey), "kind": .string(kind), "name": .string(source.data["name"].stringValue ?? ""), "items": .array(items), "imagePath": source.data["imagePath"]])
        return await write("לא הצלחנו להוסיף את הארוחה.") { backend, owner in
            let row = try await backend.save(table: "meals", owner: owner, payload: payload)
            if session?.owner == owner { meals.append(row) }
        }
    }
    /// Edits name, kind and items of an existing meal; everything else (date, photo, favorite…) is preserved.
    func updateMeal(_ row: HealthRow, name: String, kind: String, items: [JSONValue]) async -> Bool {
        guard !items.isEmpty, case .object(var fields) = row.data else { return false }
        fields["name"] = .string(name); fields["kind"] = .string(kind); fields["items"] = .array(items)
        let payload = JSONValue.object(fields)
        return await write("לא הצלחנו לשמור את השינויים בארוחה.") { backend, owner in
            let saved = try await backend.save(table: "meals", owner: owner, payload: payload, existing: row)
            if session?.owner == owner, let index = meals.firstIndex(where: { $0.id == row.id }) { meals[index] = saved }
        }
    }
    // MARK: - Workout plans
    struct PlanExercise: Identifiable, Equatable { var id = UUID(); var name = ""; var sets = 3; var reps = 10; var weight = 0.0; var rest = 90 }
    func savePlan(name: String, days: Set<Int>, exercises: [PlanExercise]) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let valid = exercises.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !trimmed.isEmpty, trimmed.count <= 150, !valid.isEmpty, valid.count <= 100 else { return false }
        let list: [JSONValue] = valid.map { e in
            .object(["id": .string(e.id.uuidString.lowercased()), "name": .string(String(e.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(150))), "muscle": .string(""), "equipment": .string(""), "kind": .string("strength"),
                     "sets": .number(Double(min(30, max(1, e.sets)))), "reps": .number(Double(min(500, max(1, e.reps)))), "weight": .number(min(1000, max(0, e.weight))), "rest": .number(Double(min(1800, max(0, e.rest)))),
                     "duration": .number(0), "distance": .number(0), "notes": .string("")])
        }
        let payload: JSONValue = .object(["name": .string(trimmed), "exercises": .array(list), "days": .array(days.sorted().map { .number(Double($0)) }), "archived": .bool(false)])
        return await write("לא הצלחנו לשמור את התוכנית.") { backend, owner in
            let row = try await backend.save(table: "workout_plans", owner: owner, payload: payload)
            if session?.owner == owner { plans.append(row) }
        }
    }
    func archivePlan(_ row: HealthRow) async -> Bool {
        guard case .object(var fields) = row.data else { return false }
        fields["archived"] = .bool(true)
        return await write("לא הצלחנו להעביר את התוכנית לארכיון.") { backend, owner in
            let saved = try await backend.save(table: "workout_plans", owner: owner, payload: .object(fields), existing: row)
            if session?.owner == owner, let index = plans.firstIndex(where: { $0.id == row.id }) { plans[index] = saved }
        }
    }

    // MARK: - Live workouts
    private static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    /// Creates an active session from a plan: one unchecked set per planned set, same shape as the web app.
    func startWorkout(from plan: HealthRow) async -> HealthRow? {
        let exercises = plan.data["exercises"].arrayValue.map { exercise -> JSONValue in
            guard case .object(var fields) = exercise else { return exercise }
            let sets = max(1, Int(fields["sets"]?.doubleValue ?? 3)), reps = fields["reps"]?.doubleValue ?? 10, weight = fields["weight"]?.doubleValue ?? 0
            fields["performed"] = .array((0..<sets).map { _ in .object(["id": .string(UUID().uuidString.lowercased()), "reps": .number(reps), "weight": .number(weight), "done": .bool(false), "duration": .number(0), "distance": .number(0)]) })
            fields["skipped"] = .bool(false)
            return .object(fields)
        }
        guard !exercises.isEmpty else { return nil }
        let payload: JSONValue = .object(["date": .string(dateKey), "planId": .string(plan.id), "name": plan.data["name"].stringValue.map { .string($0) } ?? .string("אימון"), "status": .string("active"), "quick": .bool(false), "startedAt": .string(Self.iso(Date())), "endedAt": .null, "exercises": .array(exercises), "notes": .string("")])
        var result: HealthRow?
#if DEBUG
        if backend == nil, session?.accessToken == "ui-test" {
            // Synthetic UI-test sessions never touch the network.
            let row = HealthRow(id: UUID().uuidString.lowercased(), owner_user_id: session?.owner ?? "", data: payload, version: 1)
            workouts.append(row); return row
        }
#endif
        _ = await write("לא הצלחנו להתחיל את האימון.") { backend, owner in
            let row = try await backend.save(table: "workout_sessions", owner: owner, payload: payload)
            if session?.owner == owner { workouts.append(row); result = row }
        }
        return result
    }
    /// Persists a new payload for an existing session (autosave on every change) and returns the saved row.
    func saveWorkout(_ row: HealthRow, payload: JSONValue) async -> HealthRow? {
        var result: HealthRow?
#if DEBUG
        if backend == nil, session?.accessToken == "ui-test" { return HealthRow(id: row.id, owner_user_id: row.owner_user_id, data: payload, version: row.version + 1) }
#endif
        _ = await write("לא הצלחנו לשמור את האימון. הנתונים האחרונים לא נשמרו.") { backend, owner in
            let saved = try await backend.save(table: "workout_sessions", owner: owner, payload: payload, existing: row)
            if session?.owner == owner, let index = workouts.firstIndex(where: { $0.id == row.id }) { workouts[index] = saved; result = saved }
        }
        return result
    }
    func finishedTimestamp() -> String { Self.iso(Date()) }
    func deleteMeal(_ row: HealthRow) async -> Bool {
        await write("לא הצלחנו למחוק את הארוחה.") { backend, owner in
            try await backend.softDelete(table: "meals", row: row, owner: owner)
            if session?.owner == owner { meals.removeAll { $0.id == row.id } }
        }
    }
    // MARK: - AI meal analysis (same gating and edge function as the web app)
    struct MealAnalysis { let items: [JSONValue]; let needsClarification: Bool; let question: String; let analysisId: String; let imagePath: String }
    /// AI is for adults only; the web app derives this from the profile's birth date.
    var aiEligible: Bool {
        guard let birth = profile["birthDate"].stringValue else { return false }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = timeZone; f.dateFormat = "yyyy-MM-dd"
        guard let date = f.date(from: birth) else { return false }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        return (calendar.dateComponents([.year], from: date, to: Date()).year ?? 0) >= 18
    }
    var aiConsented: Bool { profile["aiProviderConsent"].boolValue == true }
    func grantAIConsent() async -> Bool {
        guard let row = profileRow, case .object(var fields) = row.data else { return false }
        fields["aiProviderConsent"] = .bool(true)
        return await write("לא הצלחנו לשמור את האישור.") { backend, owner in
            let saved = try await backend.save(table: "health_profiles", owner: owner, payload: .object(fields), existing: row)
            if session?.owner == owner { profileRow = saved; profile = saved.data }
        }
    }
    /// Calls an allow-listed edge function as the signed-in owner. Returns the server's error code on failure.
    func call(_ function: String, _ body: JSONValue) async -> Result<JSONValue, BackendError> {
#if DEBUG
        if backend == nil, session?.accessToken == "ui-test", function == "wellness-chat" { return .success(UITestFixtures.chatState) }
#endif
        guard let owner = session?.owner, let backend else { return .failure(.sessionRequired) }
        do {
            let result = try await backend.invoke(function, body: body, owner: owner)
            return session?.owner == owner ? .success(result) : .failure(.sessionChanged)
        } catch let error as BackendError { return .failure(error) } catch { return .failure(.connection) }
    }
    func analyzeMeal(jpeg: Data, description: String) async -> MealAnalysis? {
        guard aiEligible, aiConsented, let owner = session?.owner, let backend else { return nil }
        do {
            let path = try await backend.uploadImage(jpeg, owner: owner)
            let requestID = UUID().uuidString.lowercased()
            let raw = try await backend.invoke("nutrition-analyze", body: .object(["imagePath": .string(path), "requestId": .string(requestID), "mode": .string("meal"), "description": .string(description)]), owner: owner)
            guard session?.owner == owner else { return nil }
            let items = raw["items"].arrayValue.compactMap { item -> JSONValue? in
                guard let name = item["name"].stringValue, let quantity = item["quantity"].doubleValue, quantity > 0, item["per100"] != .null else { return nil }
                var food: [String: JSONValue] = ["id": .string(UUID().uuidString.lowercased()), "name": .string(name), "basis": item["basis"].stringValue == "ml" ? .string("ml") : .string("g"), "source": item["source"].stringValue.map { .string($0) } ?? .string("ai"), "per100": item["per100"]]
                if let sourceId = item["sourceId"].stringValue { food["sourceId"] = .string(sourceId) }
                var fields: [String: JSONValue] = ["id": .string(UUID().uuidString.lowercased()), "food": .object(food), "quantity": .number(min(10_000, quantity))]
                if let assumption = item["assumption"].stringValue { fields["assumption"] = .string(assumption) }
                return .object(fields)
            }
            guard let analysisId = raw["analysisId"].stringValue, !items.isEmpty else { self.error = "לא הצלחנו לזהות את הארוחה. אפשר לנסות תמונה אחרת או להוסיף ידנית."; return nil }
            return MealAnalysis(items: items, needsClarification: raw["needsClarification"].boolValue == true, question: raw["question"].stringValue ?? "", analysisId: analysisId, imagePath: path)
        } catch { if session?.owner == owner { self.error = "הניתוח לא הושלם. בדוק חיבור ונסה שוב." }; return nil }
    }
    func saveAnalyzedMeal(_ analysis: MealAnalysis, items: [JSONValue], kind: String) async -> Bool {
        guard !items.isEmpty else { return false }
        let name = items.first?["food"]["name"].stringValue ?? ""
        let payload: JSONValue = .object(["date": .string(dateKey), "kind": .string(kind), "name": .string(name), "items": .array(items), "imagePath": .string(analysis.imagePath), "aiEstimate": .object(["analysisId": .string(analysis.analysisId)])])
        return await write("לא הצלחנו לשמור את הארוחה.") { backend, owner in
            let row = try await backend.save(table: "meals", owner: owner, payload: payload)
            if session?.owner == owner { meals.append(row) }
        }
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
