import Foundation
import Combine
import SwiftUI
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
    /// The meal that was just removed; shown with an Undo button for a few seconds.
    @Published var undoableMeal: HealthRow?
    /// Opt-in contribution of corrected meals to improve the recognition model (server policy wellness-training-v1).
    @Published private(set) var trainingEnabled = false
    @Published private(set) var trainingCount = 0
    @Published private(set) var trainingShared: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "trainingSharedMeals") ?? [])
    @Published private(set) var personalFoods: [HealthRow] = []
    @Published private(set) var recipes: [HealthRow] = []
    @Published private(set) var goals: [HealthRow] = []
    @Published private(set) var plans: [HealthRow] = []
    @Published private(set) var workouts: [HealthRow] = []
    @Published private(set) var profile: JSONValue = .null
    private var profileRow: HealthRow?
    @Published private(set) var waterLogs: [HealthRow] = []
    @Published private(set) var weightLogs: [HealthRow] = []
    @Published private(set) var candidates: [AppleWorkout] = []
    @Published private(set) var steps: Double?
    @Published private(set) var burnedKcal: Double?
    @Published private(set) var healthLoaded = false
    @Published var selection: Set<UUID> = []
    @Published var importMessage: String?
    let health = HealthReader()
    let backend: Backend?
    private var revision = 0
    private var healthRevision = 0
    init() {
#if DEBUG
        if let scenario = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--ui-test-") }) {
            // Simulator UI tests are fully synthetic and cannot reach a production API.
            backend = nil
            phase = scenario == "--ui-test-login" ? .signedOut : .signedIn
            if phase == .signedIn {
                session = Session(accessToken: "ui-test", refreshToken: "ui-test", owner: UITestFixtures.owner, member: "11111111-1111-4111-8111-111111111111")
                profile = .object(["timezone": .string("UTC"), "birthDate": .string("1990-01-01"), "aiProviderConsent": .bool(scenario == "--ui-test-coach" || scenario == "--ui-test-meal-ai")])
                goals = UITestFixtures.goals(date: dateKey)
                if scenario == "--ui-test-meal" || scenario == "--ui-test-meal-ai" { steps = 1454; burnedKcal = 320 }
                if scenario == "--ui-test-meal" || scenario == "--ui-test-meal-ai" || scenario == "--ui-test-coach" { meals = UITestFixtures.meals(date: dateKey, estimated: scenario == "--ui-test-meal-ai"); workouts = UITestFixtures.workouts(date: dateKey); plans = UITestFixtures.plans(); weightLogs = UITestFixtures.weights(zone: timeZone); recipes = UITestFixtures.recipes() }
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
    /// Real sessions open on the household home screen (like the web app); synthetic test sessions keep the health screens unless asked otherwise.
    var startsOnHealth: Bool {
#if DEBUG
        if let scenario = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--ui-test-") }) { return scenario != "--ui-test-home" }
#endif
        return false
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
    var dayMeals: [HealthRow] { Array(meals.filter { $0.data["date"].stringValue == dateKey }.reversed()).sorted { ($0.data["time"].stringValue ?? "") > ($1.data["time"].stringValue ?? "") } }
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
        do { session = try await backend.login(pin: pin); phase = .signedIn; await refresh(); await PushManager.shared.refresh(); await PushManager.shared.uploadIfPossible() }
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
            async let pf = backend.rows(table: "personal_foods", owner: owner)
            async let rc = backend.rows(table: "recipes", owner: owner)
            let snapshot = try await (m, g, p, w, h)
            let extras = try await (wl, wt)
            let library = try await (pf, rc)
            guard request == revision, session?.owner == owner else { return }
            meals = snapshot.0; goals = snapshot.1; plans = snapshot.2; workouts = snapshot.3; profile = snapshot.4.first?.data ?? .null; profileRow = snapshot.4.first
            waterLogs = extras.0; weightLogs = extras.1; personalFoods = library.0; recipes = library.1
            candidates = pendingAppleWorkouts(candidates, existing: importedIDs)
            selection.formIntersection(Set(candidates.map(\.id)))
            publishToWatch()
        } catch is CancellationError {
            return   // cancelled (for example the pull to refresh was interrupted): not an error to show
        } catch {
            if request == revision, session?.owner == owner, await handleSessionLoss(error) { return }
            if request == revision, session?.owner == owner { self.error = Self.message(error) }
        }
    }
    /// The server no longer accepts this sign-in (for example another sign-in replaced it): go back to the code screen
    /// with an explanation, instead of a vague "could not load" while every request keeps failing.
    @discardableResult
    func handleSessionLoss(_ error: Error) async -> Bool {
        guard let e = error as? BackendError, e == .sessionRequired, phase == .signedIn else { return false }
        await backend?.signOut()
        session = nil; phase = .signedOut
        self.error = "ההתחברות פגה, כנראה כי נכנסת ממכשיר אחר. הקלד את הקוד שוב."
        return true
    }
    /// Today's steps and active calories for the Today screen. Does nothing for the UI-test fixtures, and fails quietly when Health is unavailable or denied.
    func loadTodayActivity() async {
        guard let owner = session?.owner, session?.accessToken != "ui-test" else { return }
        do {
            try await health.requestAccess()
            async let stepCount = health.todaySteps()
            async let energy = health.todayActiveEnergy()
            let (s, e) = (try? await stepCount, try? await energy)
            guard session?.owner == owner else { return }
            if let s { steps = s }
            if let e { burnedKcal = e }
        } catch {}
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
        if let token = PushManager.shared.deviceToken, let owner = session?.owner { try? await backend?.unregisterPushDevice(token: token, owner: owner) }
        revision += 1; healthRevision += 1
        session = nil; meals = []; goals = []; plans = []; workouts = []; profile = .null; profileRow = nil; waterLogs = []; weightLogs = []
        candidates = []; selection = []; steps = nil; burnedKcal = nil; healthLoaded = false; importMessage = nil; error = nil
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
    // MARK: - Apple Watch
    func watchSummary() -> WatchSummary {
        WatchSummary(date: dateKey, kcalConsumed: nutrientTotal(meals: dayMeals, nutrient: "kcal"), kcalTarget: goal["kcal"].doubleValue,
                     waterML: dayWater, waterTarget: waterTarget, steps: steps, updatedAt: Date())
    }
    /// Sends today's numbers to the watch. Always today (not the browsed date), so the watch is never confusing.
    func publishToWatch() {
        guard session != nil, phase == .signedIn else { return }
        let saved = selectedDate
        let today = Self.dateKey(Date(), zone: timeZone)
        let meals = meals.filter { $0.data["date"].stringValue == today }
        let water = waterLogs.filter { $0.data["date"].stringValue == today }.reduce(0.0) { $0 + ($1.data["amount"].doubleValue ?? 0) }
        _ = saved
        PhoneConnectivity.shared.push(WatchSummary(date: today, kcalConsumed: nutrientTotal(meals: meals, nutrient: "kcal"), kcalTarget: goals.filter { ($0.data["date"].stringValue ?? "9999") <= today }.max { ($0.data["date"].stringValue ?? "") < ($1.data["date"].stringValue ?? "") }?.data["kcal"].doubleValue,
                                                      waterML: water, waterTarget: waterTarget, steps: steps, updatedAt: Date()))
    }

    // MARK: - Writes (same rows and edge functions as the web app)
    var waterTarget: Double { profile["waterTarget"].doubleValue ?? 2000 }
    var dayWaterLogs: [HealthRow] { waterLogs.filter { $0.data["date"].stringValue == dateKey } }
    var dayWater: Double { dayWaterLogs.reduce(0) { $0 + ($1.data["amount"].doubleValue ?? 0) } }
    var latestWeight: Double? { weightLogs.max { ($0.data["date"].stringValue ?? "") < ($1.data["date"].stringValue ?? "") }?.data["weight"].doubleValue }

    private var creatingMeal = false
    private var creatingTraining = false
    private var loggingWeight = false
    private var creatingRecipe = false
    private func write(_ failure: String, _ work: (Backend, String) async throws -> Void) async -> Bool {
        guard let owner = session?.owner, let backend else { return false }
        do { try await work(backend, owner); let ok = session?.owner == owner; if ok { publishToWatch() }; return ok }
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
        guard kg.isFinite, kg >= 20, kg <= 400 else { error = "המשקל חייב להיות בין 20 ל־400 ק״ג."; return false }
        guard !loggingWeight else { return false }; loggingWeight = true; defer { loggingWeight = false } // a double tap must not log it twice
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
        } catch {
            if session?.owner == owner {
                if case BackendError.server(let code) = error, code == 502 { self.error = "מאגר המוצרים (Open Food Facts) איטי או לא זמין כרגע. נסה שוב בעוד רגע, או הוסף ידנית." }
                else { self.error = "החיפוש לא הושלם. בדוק חיבור ונסה שוב." }
            }
            return nil
        }
    }
    func saveMeal(kind: String, name: String, food: JSONValue, quantity: Double) async -> Bool {
        guard !creatingMeal else { return false }; creatingMeal = true; defer { creatingMeal = false } // a double tap must not log the meal twice
        guard quantity > 0, quantity <= 10_000 else { return false }
        let date = dateKey
        let item: JSONValue = .object(["id": .string(UUID().uuidString.lowercased()), "food": food, "quantity": .number(quantity)])
        let payload: JSONValue = .object(["date": .string(date), "kind": .string(kind), "name": .string(name), "items": .array([item]), "time": .string(Self.timeKey(Date(), zone: timeZone)), "imagePath": .null])
        let ok = await write("לא הצלחנו לשמור את הארוחה.") { backend, owner in
            let row = try await backend.save(table: "meals", owner: owner, payload: payload)
            if session?.owner == owner { meals.append(row) }
        }
        if ok { await rememberFood(food) }
        return ok
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
        guard !creatingMeal else { return false }; creatingMeal = true; defer { creatingMeal = false } // a double tap must not log the meal twice
        let items = source.data["items"].arrayValue.map { item -> JSONValue in
            guard case .object(var fields) = item else { return item }
            fields["id"] = .string(UUID().uuidString.lowercased()); return .object(fields)
        }
        guard !items.isEmpty else { return false }
        let payload: JSONValue = .object(["date": .string(dateKey), "kind": .string(kind), "name": .string(source.data["name"].stringValue ?? ""), "items": .array(items), "time": .string(Self.timeKey(Date(), zone: timeZone)), "imagePath": source.data["imagePath"]])
        return await write("לא הצלחנו להוסיף את הארוחה.") { backend, owner in
            let row = try await backend.save(table: "meals", owner: owner, payload: payload)
            if session?.owner == owner { meals.append(row) }
        }
    }
    /// Edits name, kind and items of an existing meal; everything else (date, photo, favorite…) is preserved.
    func updateMeal(_ staleRow: HealthRow, name: String, kind: String, items: [JSONValue]) async -> Bool {
        // A sheet may hold an older copy of the meal (e.g. after an AI correction or a time edit): start from the store's latest.
        let row = meals.first(where: { $0.id == staleRow.id }) ?? staleRow
        guard !items.isEmpty, case .object(var fields) = row.data else { return false }
        fields["name"] = .string(name); fields["kind"] = .string(kind); fields["items"] = .array(items)
        let payload = JSONValue.object(fields)
        return await write("לא הצלחנו לשמור את השינויים בארוחה.") { backend, owner in
            let saved = try await backend.save(table: "meals", owner: owner, payload: payload, existing: row)
            if session?.owner == owner, let index = meals.firstIndex(where: { $0.id == row.id }) { meals[index] = saved }
        }
    }
    /// Copies a meal to another day (new item ids, same items and photo).
    func copyMeal(_ source: HealthRow, to date: Date) async -> Bool {
        guard !creatingMeal else { return false }; creatingMeal = true; defer { creatingMeal = false } // a double tap must not log the meal twice
        let items = source.data["items"].arrayValue.map { item -> JSONValue in
            guard case .object(var f) = item else { return item }
            f["id"] = .string(UUID().uuidString.lowercased()); return .object(f)
        }
        guard !items.isEmpty else { return false }
        let payload: JSONValue = .object(["date": .string(Self.dateKey(date, zone: timeZone)), "kind": source.data["kind"], "name": .string(source.data["name"].stringValue ?? ""), "items": .array(items), "time": source.data["time"], "imagePath": .null])
        return await write("לא הצלחנו להעתיק את הארוחה.") { backend, owner in
            let row = try await backend.save(table: "meals", owner: owner, payload: payload)
            if session?.owner == owner { meals.append(row) }
        }
    }
    /// Marks or unmarks a meal as a favorite (listed first when adding a meal).
    func setFavorite(_ row: HealthRow, _ on: Bool) async -> Bool {
        guard case .object(var fields) = row.data else { return false }
        fields["favorite"] = on ? .bool(true) : .null
        if !on { fields.removeValue(forKey: "favorite") }
        let payload = JSONValue.object(fields)
        return await write("לא הצלחנו לעדכן את המועדפים.") { backend, owner in
            let saved = try await backend.save(table: "meals", owner: owner, payload: payload, existing: row)
            if session?.owner == owner, let i = meals.firstIndex(where: { $0.id == row.id }) { meals[i] = saved }
        }
    }
    var favoriteMeals: [HealthRow] {
        var seen = Set<String>()
        return meals.filter { $0.data["favorite"].boolValue == true }.sorted { ($0.data["date"].stringValue ?? "") > ($1.data["date"].stringValue ?? "") }.filter { meal in
            seen.insert(meal.data["name"].stringValue?.isEmpty == false ? meal.data["name"].stringValue! : meal.id).inserted
        }
    }
    // MARK: - Push notifications
    /// Tells the server which member this installation belongs to, so activity can be delivered through APNs.
    func registerPushToken(_ token: String) async {
        guard let owner = session?.owner, let member = session?.member, let backend else { return }
#if DEBUG
        if session?.accessToken == "ui-test" { return }
        let sandbox = true
#else
        let sandbox = false
#endif
        try? await backend.registerPushDevice(token: token, memberID: member, sandbox: sandbox, owner: owner)
    }
    func notificationPrefs() async -> [String: Bool] {
        var prefs: [String: Bool] = ["on_create": true, "on_complete": true, "on_assigned_me": true, "on_shopping": true, "on_delete": true, "on_broadcast": true, "muted": false]
        guard let owner = session?.owner, let member = session?.member, let backend, let row = try? await backend.notificationPrefs(memberID: member, owner: owner) else { return prefs }
        for key in prefs.keys { if let v = row[key].boolValue { prefs[key] = v } }
        return prefs
    }
    func saveNotificationPrefs(_ prefs: [String: Bool]) async -> Bool {
        guard let owner = session?.owner, let member = session?.member, let backend else { return false }
        do { try await backend.saveNotificationPrefs(memberID: member, prefs: prefs, owner: owner); return true } catch { self.error = "לא הצלחנו לשמור את הגדרות ההתראות."; return false }
    }
    // MARK: - Food library (personal foods and recipes)
    /// Remembers a scanned or label product so it can be logged again in one tap (the web app does this when a product is logged).
    func rememberFood(_ food: JSONValue) async {
        guard let barcode = food["barcode"].stringValue, !personalFoods.contains(where: { $0.data["barcode"].stringValue == barcode }) else { return }
        guard let owner = session?.owner, let backend else { return }
        if let row = try? await backend.save(table: "personal_foods", owner: owner, payload: food), session?.owner == owner { personalFoods.append(row) }
    }
    func removePersonalFood(_ row: HealthRow) async -> Bool {
        await write("לא הצלחנו להסיר מהספרייה.") { backend, owner in
            try await backend.softDelete(table: "personal_foods", row: row, owner: owner)
            if session?.owner == owner { personalFoods.removeAll { $0.id == row.id } }
        }
    }
    /// Saves a meal's items as a recipe. Recipes are priced per gram, so every item must be measured in grams (as on the web).
    func saveRecipe(name: String, servings: Double, items: [JSONValue]) async -> Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 200, servings > 0, servings <= 1000, !items.isEmpty, items.count <= 100,
              items.allSatisfy({ ($0["food"]["basis"].stringValue ?? "g") == "g" }) else { error = "מתכון יכול להכיל רק מרכיבים שנמדדים בגרמים."; return false }
        guard !creatingRecipe else { return false }; creatingRecipe = true; defer { creatingRecipe = false } // a double tap must not save it twice
        let payload: JSONValue = .object(["name": .string(clean), "servings": .number(servings), "items": .array(items)])
        return await write("לא הצלחנו לשמור את המתכון.") { backend, owner in
            let row = try await backend.save(table: "recipes", owner: owner, payload: payload)
            if session?.owner == owner { recipes.append(row) }
        }
    }
    func updateRecipe(_ row: HealthRow, name: String, servings: Double, grams: [String: Double]) async -> Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard case .object(var fields) = row.data, !clean.isEmpty, clean.count <= 200, servings > 0, servings <= 1000, grams.values.allSatisfy({ $0 > 0 && $0 <= 10_000 }) else { error = "בדוק את שם המתכון, מספר המנות והכמויות (עד 10,000 גרם לרכיב)."; return false }
        let items = row.data["items"].arrayValue.map { item -> JSONValue in
            guard case .object(var f) = item, let id = f["id"]?.stringValue, let g = grams[id] else { return item }
            f["quantity"] = .number(g); return .object(f)
        }
        fields["name"] = .string(clean); fields["servings"] = .number(servings); fields["items"] = .array(items)
        let payload = JSONValue.object(fields)
        return await write("לא הצלחנו לשמור את המתכון.") { backend, owner in
            let saved = try await backend.save(table: "recipes", owner: owner, payload: payload, existing: row)
            if session?.owner == owner, let i = recipes.firstIndex(where: { $0.id == row.id }) { recipes[i] = saved }
        }
    }
    func removeRecipe(_ row: HealthRow) async -> Bool {
        await write("לא הצלחנו למחוק את המתכון.") { backend, owner in
            try await backend.softDelete(table: "recipes", row: row, owner: owner)
            if session?.owner == owner { recipes.removeAll { $0.id == row.id } }
        }
    }
    /// Logs one serving of a recipe as a meal (each item scaled by 1/servings).
    func logRecipe(_ row: HealthRow, kind: String) async -> Bool {
        guard !creatingMeal else { return false }; creatingMeal = true; defer { creatingMeal = false } // a double tap must not log the meal twice
        let servings = max(row.data["servings"].doubleValue ?? 1, 0.1)
        let items = row.data["items"].arrayValue.map { item -> JSONValue in
            guard case .object(var f) = item else { return item }
            f["id"] = .string(UUID().uuidString.lowercased()); f["quantity"] = .number(((f["quantity"]?.doubleValue ?? 0) / servings * 100).rounded() / 100); return .object(f)
        }
        guard !items.isEmpty else { return false }
        let payload: JSONValue = .object(["date": .string(dateKey), "kind": .string(kind), "name": .string(row.data["name"].stringValue ?? ""), "items": .array(items), "time": .string(Self.timeKey(Date(), zone: timeZone)), "imagePath": .null])
        return await write("לא הצלחנו להוסיף את הארוחה.") { backend, owner in
            let saved = try await backend.save(table: "meals", owner: owner, payload: payload)
            if session?.owner == owner { meals.append(saved) }
        }
    }
    // MARK: - AI trainer (wellness-ai: program / adjust / apply)
    struct TrainingPreferences: Equatable {
        var goal = "muscle", experience = "beginner", split = "auto", notes = ""
        var days: Set<Int> = [0, 2, 4]
        var minutes = 45
        var focus: [String] = []
        var equipment: Set<String> = ["bodyweight", "dumbbell", "machine", "cable"]
        var json: JSONValue {
            .object(["goal": .string(goal), "experience": .string(experience), "days": .array(days.sorted().map { .number(Double($0)) }), "minutes": .number(Double(minutes)),
                     "split": .string(split), "focus": .array(focus.map { .string($0) }), "equipment": .array(equipment.sorted().map { .string($0) }), "avoid": .array([]), "notes": .string(String(notes.prefix(1000)))])
        }
    }
    /// Stores the preferences in the profile first, exactly like the web app, so the server reads the same values.
    func saveTrainingPreferences(_ prefs: TrainingPreferences) async -> Bool {
#if DEBUG
        if backend == nil, session?.accessToken == "ui-test" { return true }
#endif
        guard let row = profileRow, case .object(var fields) = row.data else { self.error = "צריך להשלים פרופיל באפליקציה הרגילה לפני שימוש במאמן."; return false }
        fields["trainingPreferences"] = prefs.json
        return await write("לא הצלחנו לשמור את ההעדפות.") { backend, owner in
            let saved = try await backend.save(table: "health_profiles", owner: owner, payload: .object(fields), existing: row)
            if session?.owner == owner { profileRow = saved; profile = saved.data }
        }
    }

    // MARK: - Profile and nutrition targets
    /// Saves the profile (creating it on first use) and a nutrition goal effective from `goal.date`, like the web app's "profile and targets" flow.
    func saveProfileAndGoal(birthDate: String?, height: Double?, weight: Double?, physiology: String?, activity: String, objective: String, goal: (date: String, kcal: Int, protein: Int, carbs: Int, fat: Int, method: String)) async -> Bool {
        guard goal.kcal >= 500, goal.kcal <= 10_000, goal.protein >= 0, goal.protein <= 500, goal.carbs >= 0, goal.carbs <= 1500, goal.fat >= 0, goal.fat <= 500,
              ["manual", "calculated"].contains(goal.method), ["sedentary", "light", "moderate", "high"].contains(activity), ["lose", "maintain", "gain"].contains(objective),
              height.map({ (80...250).contains($0) }) ?? true, weight.map({ (20...400).contains($0) }) ?? true else { error = "בדוק את הערכים שהוזנו."; return false }
        var fields: [String: JSONValue]
        if let row = profileRow, case .object(let f) = row.data { fields = f } else {
            fields = ["nutritionEnabled": .bool(true), "workoutsEnabled": .bool(true), "timezone": .string(TimeZone.current.identifier), "age": .null, "waterTarget": .number(2000), "aiConsent": .bool(false), "aiProviderConsent": .bool(false)]
        }
        fields["nutritionEnabled"] = .bool(true)
        fields["birthDate"] = birthDate.map { .string($0) } ?? .null
        fields["height"] = height.map { .number($0) } ?? .null; fields["weight"] = weight.map { .number($0) } ?? .null
        fields["physiology"] = physiology.map { .string($0) } ?? .null; fields["activity"] = .string(activity); fields["objective"] = .string(objective)
        let goalPayload: JSONValue = .object(["date": .string(goal.date), "kcal": .number(Double(goal.kcal)), "protein": .number(Double(goal.protein)), "carbs": .number(Double(goal.carbs)), "fat": .number(Double(goal.fat)), "method": .string(goal.method)])
        let existingGoal = goals.first { $0.data["date"].stringValue == goal.date }
        let base = profileRow
#if DEBUG
        if backend == nil, session?.accessToken == "ui-test" { return true }
#endif
        return await write("לא הצלחנו לשמור את הפרופיל והיעדים.") { backend, owner in
            let savedProfile = try await backend.save(table: "health_profiles", owner: owner, payload: .object(fields), existing: base)
            if session?.owner == owner { profileRow = savedProfile; profile = savedProfile.data }
            let savedGoal = try await backend.save(table: "nutrition_goals", owner: owner, payload: goalPayload, existing: existingGoal)
            if session?.owner == owner { goals.removeAll { $0.id == savedGoal.id }; goals.append(savedGoal) }
        }
    }
    var goalHistory: [HealthRow] { goals.sorted { ($0.data["date"].stringValue ?? "") > ($1.data["date"].stringValue ?? "") } }

    // MARK: - Workout plans
    struct PlanExercise: Identifiable, Equatable { var id = UUID(); var name = ""; var catalogId: String?; var muscle = ""; var equipment = ""; var sets = 3; var reps = 10; var weight = 0.0; var rest = 90 }
    func savePlan(name: String, days: Set<Int>, exercises: [PlanExercise]) async -> Bool {
        guard !creatingTraining else { return false }; creatingTraining = true; defer { creatingTraining = false } // a double tap must not create it twice
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let valid = exercises.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !trimmed.isEmpty, trimmed.count <= 150, !valid.isEmpty, valid.count <= 100 else { return false }
        var list: [JSONValue] = []
        for e in valid {
            var fields: [String: JSONValue] = [:]
            fields["id"] = .string(e.id.uuidString.lowercased())
            fields["name"] = .string(String(e.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(150)))
            fields["muscle"] = .string(String(e.muscle.prefix(80)))
            fields["equipment"] = .string(String(e.equipment.prefix(80)))
            fields["kind"] = .string("strength")
            fields["sets"] = .number(Double(min(30, max(1, e.sets))))
            fields["reps"] = .number(Double(min(500, max(1, e.reps))))
            fields["weight"] = .number(min(1000, max(0, e.weight)))
            fields["rest"] = .number(Double(min(1800, max(0, e.rest))))
            fields["duration"] = .number(0)
            fields["distance"] = .number(0)
            fields["notes"] = .string("")
            if let catalogId = e.catalogId { fields["catalogId"] = .string(catalogId) }
            list.append(.object(fields))
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
        guard !creatingTraining else { return nil }; creatingTraining = true; defer { creatingTraining = false } // a double tap must not create it twice
        let exercises = plan.data["exercises"].arrayValue.map { exercise -> JSONValue in
            guard case .object(var fields) = exercise else { return exercise }
            let sets = max(1, Int(fields["sets"]?.doubleValue ?? 3)), reps = fields["reps"]?.doubleValue ?? 10, weight = fields["weight"]?.doubleValue ?? 0
            fields["performed"] = .array((0..<sets).map { _ in .object(["id": .string(UUID().uuidString.lowercased()), "reps": .number(reps), "weight": .number(weight), "done": .bool(false), "duration": .number(0), "distance": .number(0)]) })
            fields["skipped"] = .bool(false)
            return .object(fields)
        }
        guard !exercises.isEmpty else { error = "בתוכנית הזו אין תרגילים. הוסף תרגיל ונסה שוב."; return nil }
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
    func loadTrainingStatus() async {
        if isFixtureSession { return }
        guard let owner = session?.owner, let backend else { return }
        guard let result = try? await backend.invoke("wellness-training", body: .object(["action": .string("status")]), owner: owner), session?.owner == owner else { return }
        trainingEnabled = result["enabled"].boolValue == true
        trainingCount = Int(result["count"].doubleValue ?? 0)
    }
    /// Turning consent off also deletes every shared example (server side).
    func setTrainingConsent(_ on: Bool) async -> Bool {
        if isFixtureSession { trainingEnabled = on; if !on { trainingCount = 0; trainingShared = []; UserDefaults.standard.removeObject(forKey: "trainingSharedMeals") }; return true }
        guard let owner = session?.owner, let backend else { return false }
        do {
            _ = try await backend.invoke("wellness-training", body: .object(["action": .string("consent"), "enabled": .bool(on), "policy": .string("wellness-training-v1")]), owner: owner)
            guard session?.owner == owner else { return false }
            trainingEnabled = on
            if !on { trainingCount = 0; trainingShared = []; UserDefaults.standard.removeObject(forKey: "trainingSharedMeals") }
            await loadTrainingStatus()
            return true
        } catch { if session?.owner == owner { self.error = on ? "לא הצלחנו לאשר את ההשתתפות. נדרש פרופיל עם תאריך לידה (גיל 18 ומעלה)." : "לא הצלחנו לבטל את ההסכמה. נסה שוב." }; return false }
    }
    /// Shares one saved meal (photo + the items as the user corrected them) as a training example the user approved.
    func shareTrainingExample(_ meal: HealthRow) async -> Bool {
        guard trainingEnabled, meal.data["imagePath"].stringValue != nil else { return false }
        func remember() { trainingShared.insert(meal.id); trainingCount += 1; UserDefaults.standard.set(Array(trainingShared), forKey: "trainingSharedMeals") }
        if isFixtureSession { remember(); return true }
        guard let owner = session?.owner, let backend else { return false }
        do {
            _ = try await backend.invoke("wellness-training", body: .object(["action": .string("submit"), "task": .string("nutrition_photo"), "sourceId": .string(meal.id), "description": .string(""), "weighed": .bool(false), "confirmShare": .bool(true)]), owner: owner)
            guard session?.owner == owner else { return false }
            remember(); await loadTrainingStatus()
            return true
        } catch { if session?.owner == owner { self.error = "לא הצלחנו לשתף את הדוגמה. נסה שוב בעוד רגע." }; return false }
    }
    private var isFixtureSession: Bool { backend == nil && session?.accessToken == "ui-test" }
    /// Removes a meal from the screen at once (animated) and deletes it on the server in the background; it comes back if that fails.
    func removeMealWithUndo(_ row: HealthRow) async {
        guard let index = meals.firstIndex(where: { $0.id == row.id }) else { return }
        withAnimation(.snappy) { meals.remove(at: index) }
        undoableMeal = row
        if isFixtureSession { return }
        let ok = await write("לא הצלחנו למחוק את הארוחה.") { backend, owner in try await backend.softDelete(table: "meals", row: row, owner: owner) }
        if !ok {
            withAnimation(.snappy) { meals.insert(row, at: min(index, meals.count)) }
            if undoableMeal?.id == row.id { undoableMeal = nil }
        }
    }
    /// Brings back the meal removed last, as a new row with the same content.
    func undoMealRemoval() async {
        guard let row = undoableMeal else { return }
        undoableMeal = nil
        if isFixtureSession { withAnimation(.snappy) { meals.append(row) }; return }
        _ = await write("לא הצלחנו לשחזר את הארוחה.") { backend, owner in
            let restored = try await backend.save(table: "meals", owner: owner, payload: row.data)
            if session?.owner == owner { withAnimation(.snappy) { meals.append(restored) } }
        }
    }
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
        if backend == nil, session?.accessToken == "ui-test" {
            if function == "wellness-chat" { return .success(UITestFixtures.chatState) }
            if function == "assistant" { return .success(UITestFixtures.assistantReply) }
            if function == "wellness-ai" { return .success(body["action"].stringValue == "apply" ? .object(["ok": .bool(true)]) : UITestFixtures.trainerProposal) }
        }
#endif
        guard let owner = session?.owner, let backend else { return .failure(.sessionRequired) }
        do {
            let result = try await backend.invoke(function, body: body, owner: owner)
            return session?.owner == owner ? .success(result) : .failure(.sessionChanged)
        } catch let error as BackendError { return .failure(error) } catch { return .failure(.connection) }
    }
    enum AnalysisOutcome { case ready(MealAnalysis); case failed(String) }
    var isFixture: Bool { isFixtureSession }
    func reportError(_ message: String) { error = message }
    /// Uploads the photo and analyzes it (used by the older "meal from photo" sheet).
    func analyzeMeal(jpeg: Data, description: String) async -> MealAnalysis? {
        guard aiEligible, aiConsented, let owner = session?.owner, let backend else { return nil }
        do {
            let path = try await backend.uploadImage(jpeg, owner: owner)
            switch await runMealAnalysis(imagePath: path, requestID: UUID().uuidString.lowercased(), description: description) {
            case .ready(let analysis): return analysis
            case .failed(let message): if !message.isEmpty, session?.owner == owner { self.error = message }; return nil
            }
        } catch { if session?.owner == owner { self.error = "הניתוח לא הושלם. בדוק חיבור ונסה שוב." }; return nil }
    }
    /// Runs the AI estimate for an uploaded photo (or, with no image, a text description). The request id makes it safe to
    /// ask again after the app was interrupted: the server returns the stored result, or says it is still busy and we wait.
    func runMealAnalysis(imagePath: String?, requestID: String, description: String) async -> AnalysisOutcome {
        guard aiEligible, aiConsented else { return .failed("ה־AI לא זמין. בדוק את הגיל ואת ההסכמה בהגדרות.") }
        if isFixtureSession {
            try? await Task.sleep(for: .seconds(7))
            return .ready(Self.fixtureAnalysis(imagePath: imagePath ?? ""))
        }
        guard let owner = session?.owner, let backend else { return .failed("לא מחובר. התחבר מחדש ונסה שוב.") }
        var id = requestID, retried = false, busyWaits = 0
        while !Task.isCancelled {
            do {
                var body: [String: JSONValue] = ["requestId": .string(id), "mode": .string(imagePath == nil ? "text" : "meal"), "automatic": .bool(true), "description": .string(description)]
                if let imagePath { body["imagePath"] = .string(imagePath) }
                let raw = try await backend.invoke("nutrition-analyze", body: .object(body), owner: owner)
                guard session?.owner == owner else { return .failed("") }
                let items = raw["items"].arrayValue.compactMap { item -> JSONValue? in
                    guard let name = item["name"].stringValue, let quantity = item["quantity"].doubleValue, quantity > 0, item["per100"] != .null else { return nil }
                    var food: [String: JSONValue] = ["id": .string(UUID().uuidString.lowercased()), "name": .string(name), "basis": item["basis"].stringValue == "ml" ? .string("ml") : .string("g"), "source": item["source"].stringValue.map { .string($0) } ?? .string("ai"), "per100": item["per100"]]
                    if let sourceId = item["sourceId"].stringValue { food["sourceId"] = .string(sourceId) }
                    var fields: [String: JSONValue] = ["id": .string(UUID().uuidString.lowercased()), "food": .object(food), "quantity": .number(min(10_000, quantity))]
                    if let assumption = item["assumption"].stringValue { fields["assumption"] = .string(assumption) }
                    return .object(fields)
                }
                guard let analysisId = raw["analysisId"].stringValue, !items.isEmpty else { return .failed("לא הצלחנו לזהות את הארוחה. אפשר לנסות תמונה אחרת או להוסיף ידנית.") }
                return .ready(MealAnalysis(items: items, needsClarification: raw["needsClarification"].boolValue == true, question: raw["question"].stringValue ?? "", analysisId: analysisId, imagePath: imagePath ?? ""))
            } catch let error as BackendError {
                if case .server(409) = error, busyWaits < 40 { busyWaits += 1; try? await Task.sleep(for: .seconds(3)); continue }
                // A dropped connection may have reached the server: ask again with the SAME id so the job is not analysed (and counted) twice.
                if error == .connection, !retried { retried = true; try? await Task.sleep(for: .seconds(2)); continue }
                if !retried { retried = true; id = UUID().uuidString.lowercased(); continue }
                return .failed("הניתוח לא הושלם. בדוק חיבור ונסה שוב.")
            } catch is CancellationError { return .failed("") }
            catch { if !retried { retried = true; id = UUID().uuidString.lowercased(); continue }; return .failed("הניתוח לא הושלם. בדוק חיבור ונסה שוב.") }
        }
        return .failed("")
    }
    static func fixtureAnalysis(imagePath: String) -> MealAnalysis {
        func item(_ name: String, _ grams: Double, _ per100: [String: Double], note: String? = nil) -> JSONValue {
            var fields: [String: JSONValue] = ["id": .string(UUID().uuidString.lowercased()), "quantity": .number(grams),
                "food": .object(["id": .string(UUID().uuidString.lowercased()), "name": .string(name), "basis": .string("g"), "source": .string("ai"), "per100": .object(per100.mapValues { .number($0) })])]
            if let note { fields["assumption"] = .string(note) }
            return .object(fields)
        }
        return MealAnalysis(items: [
            item("חזה עוף בגריל", 200, ["kcal": 153, "protein": 30, "carbs": 0, "fat": 3.5], note: "הנחה: חזה עוף. אפשר לתקן."),
            item("אורז לבן מבושל", 180, ["kcal": 126, "protein": 2.7, "carbs": 28, "fat": 0.3]),
            item("שמן בישול — הערכת מתכון", 8, ["kcal": 900, "protein": 0, "carbs": 0, "fat": 100], note: "שמן משוער למנה שנאכלה. ניתן לתקן.")],
            needsClarification: false, question: "", analysisId: "fixture-analysis", imagePath: imagePath)
    }
    /// "Fix with AI": sends the user's correction ("this is rice, not pasta") to the server, which re-estimates the saved meal's items.
    func correctMeal(_ staleRow: HealthRow, text: String) async -> Bool {
        let row = meals.first(where: { $0.id == staleRow.id }) ?? staleRow
        let note = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty, aiEligible, aiConsented, let owner = session?.owner, let backend, case .object(var fields) = row.data else { return false }
        busy = true; defer { busy = false }
        let requestID = UUID().uuidString.lowercased()
        do {
            let raw = try await backend.invoke("wellness-ai", body: .object(["action": .string("correct_meal"), "mealId": .string(row.id), "expectedVersion": .number(Double(row.version)), "description": .string(String(note.prefix(2000))), "requestId": .string(requestID)]), owner: owner)
            let items = raw["items"].arrayValue
            guard session?.owner == owner else { return false }
            guard !items.isEmpty else { self.error = "לא הצלחנו לתקן את הארוחה. נסה לנסח אחרת."; return false }
            fields["items"] = .array(items)
            var estimate: [String: JSONValue] = [:]
            if case .object(let old) = row.data["aiEstimate"] { estimate = old }
            estimate["lastCorrectionId"] = .string(requestID)
            fields["aiEstimate"] = .object(estimate)
            let saved = try await backend.save(table: "meals", owner: owner, payload: .object(fields), existing: row)
            if session?.owner == owner, let index = meals.firstIndex(where: { $0.id == row.id }) { meals[index] = saved }
            return true
        } catch {
            if session?.owner == owner {
                if case BackendError.server(let code) = error, code == 502 || code == 400 {
                    self.error = "ה־AI לא הצליח להבין את התיקון. נסה לנסח אחרת, למשל: ״הוסף רוטב טריאקי 15 גרם״ או ״זה היה חזה עוף״."
                } else { self.error = "התיקון לא הושלם. בדוק חיבור ונסה שוב." }
            }
            return false
        }
    }
    static func timeKey(_ date: Date, zone: TimeZone) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = zone; f.dateFormat = "HH:mm"; return f.string(from: date)
    }
    static func mealKind(forTime time: String) -> String {
        let hour = Int(time.prefix(2)) ?? 12
        return hour < 11 ? "breakfast" : hour < 16 ? "lunch" : hour < 21 ? "dinner" : "snack"
    }
    func saveAnalyzedMeal(_ analysis: MealAnalysis, items: [JSONValue], kind: String) async -> Bool {
        await saveAnalyzedMealRow(analysis, items: items, kind: kind, date: nil, time: nil) != nil
    }
    /// Saves an analyzed meal and returns the stored row. `date`/`time` are when the meal was entered (default: the shown day, now).
    func saveAnalyzedMealRow(_ analysis: MealAnalysis, items: [JSONValue], kind: String, date: String?, time: String?) async -> HealthRow? {
        guard !items.isEmpty else { return nil }
        let name = items.first?["food"]["name"].stringValue ?? ""
        var fields: [String: JSONValue] = ["date": .string(date ?? dateKey), "kind": .string(kind), "name": .string(name), "time": .string(time ?? Self.timeKey(Date(), zone: timeZone)), "items": .array(items), "aiEstimate": .object(["analysisId": .string(analysis.analysisId)])]
        if !analysis.imagePath.isEmpty { fields["imagePath"] = .string(analysis.imagePath) }
        let payload: JSONValue = .object(fields)
        if isFixtureSession {
            let row = HealthRow(id: UUID().uuidString.lowercased(), owner_user_id: "ui-test", data: payload, version: 1)
            meals.append(row); return row
        }
        var saved: HealthRow?
        _ = await write("לא הצלחנו לשמור את הארוחה.") { backend, owner in
            let row = try await backend.save(table: "meals", owner: owner, payload: payload)
            if session?.owner == owner { meals.append(row); saved = row }
        }
        return saved
    }
    /// Changes the time the meal was eaten (shown on the card and used to order the day).
    func updateMealTime(_ staleRow: HealthRow, time: String) async -> Bool {
        let row = meals.first(where: { $0.id == staleRow.id }) ?? staleRow
        guard case .object(var fields) = row.data else { return false }
        fields["time"] = .string(time); fields["kind"] = .string(Self.mealKind(forTime: time))
        let payload = JSONValue.object(fields)
        if isFixtureSession, let index = meals.firstIndex(where: { $0.id == row.id }) { meals[index] = HealthRow(id: row.id, owner_user_id: row.owner_user_id, data: payload, version: row.version + 1); return true }
        return await write("לא הצלחנו לעדכן את השעה.") { backend, owner in
            let saved = try await backend.save(table: "meals", owner: owner, payload: payload, existing: row)
            if session?.owner == owner, let index = meals.firstIndex(where: { $0.id == row.id }) { meals[index] = saved }
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
