import Foundation
import Combine
import WellnessCore

/// Household data (shared with the web app). Reads through the signed-in member's session; every write is
/// optimistic and rolled back if the server rejects it.
@MainActor
final class HomeStore: ObservableObject {
    /// Set by the home screen's wellness card; the root shell switches to the health tab and clears it.
    @Published var openHealthRequested = false
    @Published var sections: [HSection] = []
    @Published var tasks: [HTask] = []
    @Published var chores: [HChore] = []
    @Published var events: [HEvent] = []
    @Published var members: [HMember] = []
    @Published private(set) var loading = false
    @Published var error: String?
    @Published var selectedSectionID: String?
    @Published var activity: [HActivity] = []
    @Published var suggestions: [HSuggestion] = []
    @Published var notes: [HPrivateNote] = []
    private weak var app: AppStore?
    private var revision = 0
    func bind(_ app: AppStore) { self.app = app }

    var me: HMember? { members.first { $0.id == app?.session?.member } }
    var timeZone: TimeZone { app?.timeZone ?? .current }
    var currentSection: HSection? { sections.first { $0.id == selectedSectionID } ?? sections.first }
    func member(_ id: String) -> HMember? { members.first { $0.id == id } }
    func tasks(in section: String) -> [HTask] { tasks.filter { $0.sectionID == section }.sorted { $0.position < $1.position } }
    func chores(in section: String) -> [HChore] { chores.filter { $0.sectionID == section }.sorted { ($0.nextDue ?? .distantFuture) < ($1.nextDue ?? .distantFuture) } }

    // MARK: Loading
    func refresh() async {
        guard let app, let owner = app.session?.owner else { return }
#if DEBUG
        if app.backend == nil, app.session?.accessToken == "ui-test" { loadFixtures(); return }
#endif
        guard let backend = app.backend else { return }
        revision += 1; let request = revision; loading = true
        defer { if request == revision { loading = false } }
        do {
            async let s = backend.householdRows(table: "sections", owner: owner, order: "position.asc")
            async let t = backend.householdRows(table: "tasks", owner: owner, order: "position.asc")
            async let c = backend.householdRows(table: "chores", owner: owner, order: "next_due_at.asc")
            async let e = backend.householdRows(table: "family_events", owner: owner, order: "event_date.asc")
            async let m = backend.householdRows(table: "members", owner: owner, order: "display_name.asc")
            async let sg = backend.householdRows(table: "ai_suggestions", owner: owner, filters: [.init(name: "status", value: "eq.open")], order: "created_at.desc", limit: 20, singlePage: true)
            async let pn = backend.householdRows(table: "ai_private_messages", owner: owner, filters: [.init(name: "member_id", value: "eq.\(app.session?.member ?? "")"), .init(name: "read_at", value: "is.null")], order: "created_at.desc", limit: 20, singlePage: true)
            let result = try await (s, t, c, e, m)
            let assistant = (try? await (sg, pn)) ?? ([], [])
            guard request == revision, app.session?.owner == owner else { return }
            sections = result.0.compactMap(HSection.init).sorted { $0.position < $1.position }
            tasks = result.1.compactMap(HTask.init); chores = result.2.compactMap(HChore.init)
            events = result.3.compactMap(HEvent.init); members = result.4.compactMap(HMember.init)
            suggestions = assistant.0.compactMap(HSuggestion.init); notes = assistant.1.compactMap(HPrivateNote.init)
            if selectedSectionID == nil || !sections.contains(where: { $0.id == selectedSectionID }) { selectedSectionID = sections.first?.id }
        } catch { if request == revision, app.session?.owner == owner { self.error = "לא הצלחנו לטעון את נתוני הבית. אפשר למשוך לרענון." } }
    }
    func reset() { revision += 1; sections = []; tasks = []; chores = []; events = []; members = []; suggestions = []; notes = []; selectedSectionID = nil; error = nil }

    func loadActivity() async {
        guard let app, let owner = app.session?.owner else { return }
#if DEBUG
        if app.backend == nil, app.session?.accessToken == "ui-test" { return }
#endif
        guard let backend = app.backend else { return }
        do {
            let rows = try await backend.householdRows(table: "activity_log", owner: owner, order: "created_at.desc", limit: 100, singlePage: true)
            if app.session?.owner == owner { activity = rows.compactMap(HActivity.init) }
        } catch { if app.session?.owner == owner { self.error = "לא הצלחנו לטעון את ההיסטוריה." } }
    }

    // MARK: Shopping helpers
    struct ScannedProduct { let name: String; let price: Double? }
    /// Family-taught names and per-chain prices first (barcode_products), then the shared food-lookup function (Open Food Facts).
    func lookupBarcode(_ code: String) async -> ScannedProduct? {
        guard code.count >= 8, code.count <= 14, code.allSatisfy(\.isNumber), let app, let owner = app.session?.owner else { return nil }
        if let backend = app.backend,
           let row = try? await backend.householdRows(table: "barcode_products", owner: owner, filters: [.init(name: "barcode", value: "eq.\(code)")], limit: 1, singlePage: true).first, let name = row.str("product_name") {
            let prices = ["price_rami_levy", "price_shufersal", "price_osher_ad", "price_carrefour", "price_super_pharm"].compactMap { row.num($0) }
            return ScannedProduct(name: name, price: prices.min())
        }
        if let foods = await app.searchFoods(query: code, barcode: code), let name = foods.first?["name"].stringValue { return ScannedProduct(name: name, price: nil) }
        return nil
    }
    func addShoppingItem(title: String, price: Double?, section: HSection) async {
        let before = Set(tasks.map(\.id))
        await addTask(title: title, section: section)
        if let price, let added = tasks.first(where: { !before.contains($0.id) && $0.title == title }) {
            await update(added, fields: ["price": .number(price), "currency": .string("ILS")]) { $0.price = price }
        }
    }
    func shareText(for section: HSection) -> String {
        let open = tasks(in: section.id).filter { $0.parentID == nil && !$0.isCompleted }
        let lines = open.map { t -> String in
            var line = "• \(t.title)"
            if let q = t.quantity { line += " ×\(q.formatted())" + (t.unit.map { " \($0)" } ?? "") }
            return line
        }
        return "\(section.emoji ?? "🛒") \(section.name)\n" + lines.joined(separator: "\n")
    }

    // MARK: Ordering
    /// Moves a top-level task one step up or down inside its section; the new rank sits between its new neighbours (same scheme as the web app).
    func move(_ task: HTask, in section: HSection, by step: Int) async {
        let siblings = tasks.filter { $0.sectionID == section.id && $0.parentID == nil && !$0.isCompleted }.sorted { $0.position < $1.position }
        guard let index = siblings.firstIndex(where: { $0.id == task.id }) else { return }
        let target = index + step
        guard siblings.indices.contains(target) else { return }
        let before: String?, after: String?
        if step < 0 { before = target > 0 ? siblings[target - 1].position : nil; after = siblings[target].position }
        else { before = siblings[target].position; after = target + 1 < siblings.count ? siblings[target + 1].position : nil }
        guard let position = try? FractionalIndex.between(before, after) else { return }
        await update(task, fields: ["position": .string(position)]) { $0.position = position }
    }

    // MARK: Assistant suggestions and notes
    func dismiss(_ suggestion: HSuggestion) async {
        let backup = suggestions; suggestions.removeAll { $0.id == suggestion.id }
        _ = await run("לא הצלחנו לדחות את ההצעה.", rollback: { [weak self] in self?.suggestions = backup }) { backend, owner in
            _ = try await backend.householdUpdate(table: "ai_suggestions", owner: owner, id: suggestion.id, fields: ["status": .string("dismissed")])
        }
    }
    func markRead(_ note: HPrivateNote) async {
        let backup = notes; notes.removeAll { $0.id == note.id }
        _ = await run("לא הצלחנו לסמן את ההודעה כנקראה.", rollback: { [weak self] in self?.notes = backup }) { backend, owner in
            _ = try await backend.householdUpdate(table: "ai_private_messages", owner: owner, id: note.id, fields: ["read_at": .string(DateParsing.iso(Date()))])
        }
    }
    static let applicableActions: Set<String> = ["create_task", "create_chore", "create_family_event", "complete_chore", "toggle_task_completed", "create_section"]
    /// Short Hebrew description of an action, shown before the person confirms it.
    func describe(_ a: JSONValue) -> String {
        let section = sections.first { $0.id == a.str("sectionId") }?.name
        switch a.str("type") ?? "" {
        case "create_task": return "להוסיף משימה: \(a.str("title") ?? "")" + (section.map { " (במדור \($0))" } ?? "")
        case "create_chore": return "להוסיף מטלה חוזרת: \(a.str("title") ?? "")" + (section.map { " (במדור \($0))" } ?? "")
        case "create_family_event": return "להוסיף אירוע: \(a.str("title") ?? "") ב־\(a.str("eventDate") ?? "")"
        case "create_section": return "ליצור מדור חדש: \(a.str("name") ?? "")"
        case "complete_chore": return "לסמן כבוצעה: \(chores.first { $0.id == a.str("choreId") }?.title ?? "מטלה")"
        case "toggle_task_completed": return "לשנות סימון של: \(tasks.first { $0.id == a.str("taskId") }?.title ?? "משימה")"
        default: return "פעולה לא נתמכת"
        }
    }
    /// Performs one proposed action through the same writes a person would make. Returns false if it cannot be applied here.
    @discardableResult
    func perform(_ a: JSONValue) async -> Bool {
        switch a.str("type") ?? "" {
        case "create_task":
            guard let section = sections.first(where: { $0.id == a.str("sectionId") }), let title = a.str("title") else { return false }
            await addTask(title: title, section: section, quantity: a.num("quantity")); return true
        case "create_chore":
            guard let section = sections.first(where: { $0.id == a.str("sectionId") }), let title = a.str("title") else { return false }
            await addChore(title: title, section: section, freq: ["daily", "weekly", "monthly"].contains(a.str("freq") ?? "") ? a.str("freq")! : "weekly", interval: 1); return true
        case "create_family_event":
            guard let title = a.str("title"), let day = DateParsing.day(a.str("eventDate"), zone: timeZone) else { return false }
            await saveEvent(id: nil, title: title, kind: a.str("kind") ?? "other", date: day, yearly: a.str("kind") == "birthday", notes: "", emoji: nil); return true
        case "complete_chore":
            guard let chore = chores.first(where: { $0.id == a.str("choreId") }) else { return false }
            await complete(chore); return true
        case "toggle_task_completed":
            guard let task = tasks.first(where: { $0.id == a.str("taskId") }) else { return false }
            await toggle(task); return true
        case "create_section":
            guard let name = a.str("name") else { return false }
            await addSection(name: name, emoji: a.str("emoji") ?? "", kind: ["tasks", "shopping", "chores", "info"].contains(a.str("kind") ?? "") ? a.str("kind")! : "tasks"); return true
        default: return false
        }
    }
    /// Applies a suggestion, then marks it applied (or dismissed if it cannot be applied).
    func apply(_ suggestion: HSuggestion) async {
        guard await perform(suggestion.action) else { await dismiss(suggestion); return }
        let backup = suggestions; suggestions.removeAll { $0.id == suggestion.id }
        _ = await run("לא הצלחנו לסמן את ההצעה כמיושמת.", rollback: { [weak self] in self?.suggestions = backup }) { backend, owner in
            _ = try await backend.householdUpdate(table: "ai_suggestions", owner: owner, id: suggestion.id, fields: ["status": .string("applied")])
        }
    }

    // MARK: Sections
    func addSection(name: String, emoji: String, kind: String) async {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 80, ["tasks", "shopping", "chores", "info"].contains(kind), let position = try? FractionalIndex.atEnd(sections.map(\.position).max()) else { return }
        let id = UUID().uuidString.lowercased()
        var fields: [String: JSONValue] = ["id": .string(id), "name": .string(clean), "kind": .string(kind), "position": .string(position)]
        let icon = emoji.trimmingCharacters(in: .whitespaces); if !icon.isEmpty { fields["emoji"] = .string(String(icon.prefix(8))) }
        if let me { fields["created_by"] = .string(me.id) }
        guard let section = HSection(.object(fields)) else { return }
        let backup = sections; sections.append(section); selectedSectionID = id
        _ = await run("לא הצלחנו ליצור את המדור.", rollback: { [weak self] in self?.sections = backup; self?.selectedSectionID = backup.first?.id }) { backend, owner in
            _ = try await backend.householdInsert(table: "sections", owner: owner, fields: fields)
        }
    }
    func rename(_ section: HSection, name: String, emoji: String) async {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 80, let index = sections.firstIndex(where: { $0.id == section.id }) else { return }
        let backup = sections; sections[index].name = clean; sections[index].emoji = emoji.isEmpty ? nil : emoji
        var fields: [String: JSONValue] = ["name": .string(clean), "emoji": emoji.isEmpty ? .null : .string(String(emoji.prefix(8)))]
        if let me { fields["updated_by"] = .string(me.id) }
        _ = await run("לא הצלחנו לשמור את שם המדור.", rollback: { [weak self] in self?.sections = backup }) { backend, owner in
            _ = try await backend.householdUpdate(table: "sections", owner: owner, id: section.id, fields: fields)
        }
    }
    func delete(_ section: HSection) async {
        let backup = sections; let tasksBackup = tasks; let choresBackup = chores
        sections.removeAll { $0.id == section.id }; tasks.removeAll { $0.sectionID == section.id }; chores.removeAll { $0.sectionID == section.id }
        if selectedSectionID == section.id { selectedSectionID = sections.first?.id }
        _ = await run("לא הצלחנו למחוק את המדור.", rollback: { [weak self] in self?.sections = backup; self?.tasks = tasksBackup; self?.chores = choresBackup }) { backend, owner in
            _ = try await backend.householdUpdate(table: "sections", owner: owner, id: section.id, fields: ["deleted_at": .string(DateParsing.iso(Date()))])
        }
    }

    // MARK: Writes
    private func now() -> String { DateParsing.iso(Date()) }
    private func run(_ failure: String, rollback: @escaping @MainActor () -> Void, _ work: (Backend, String) async throws -> Void) async -> Bool {
        guard let app, let owner = app.session?.owner else { rollback(); return false }
#if DEBUG
        if app.backend == nil, app.session?.accessToken == "ui-test" { return true }
#endif
        guard let backend = app.backend else { rollback(); return false }
        do { try await work(backend, owner); return app.session?.owner == owner }
        catch { rollback(); if app.session?.owner == owner { self.error = failure }; return false }
    }

    func addTask(title: String, section: HSection, parent: HTask? = nil, isNote: Bool = false, quantity: Double? = nil) async {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 500, let position = try? FractionalIndex.atEnd(tasks.filter { $0.sectionID == section.id && $0.parentID == parent?.id }.map(\.position).max()) else { return }
        let id = UUID().uuidString.lowercased()
        var fields: [String: JSONValue] = ["id": .string(id), "section_id": .string(section.id), "parent_task_id": parent.map { .string($0.id) } ?? .null, "position": .string(position), "title": .string(clean)]
        if let me = me { fields["created_by"] = .string(me.id) }
        if isNote { fields["is_note"] = .bool(true) }
        if let quantity { fields["quantity"] = .number(quantity) }
        let local = HTask(.object(fields).withDefaults)
        if let local { tasks.append(local) }
        _ = await run("לא הצלחנו להוסיף את המשימה.", rollback: { [weak self] in self?.tasks.removeAll { $0.id == id } }) { backend, owner in
            _ = try await backend.householdInsert(table: "tasks", owner: owner, fields: fields)
        }
    }
    func toggle(_ task: HTask) async {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let old = tasks[index], willComplete = !old.isCompleted
        tasks[index].isCompleted = willComplete; tasks[index].completedAt = willComplete ? Date() : nil
        var fields: [String: JSONValue] = ["is_completed": .bool(willComplete), "completed_at": willComplete ? .string(now()) : .null, "completed_by": willComplete ? (me.map { .string($0.id) } ?? .null) : .null]
        if let me { fields["updated_by"] = .string(me.id) }
        _ = await run("לא הצלחנו לעדכן את המשימה.", rollback: { [weak self] in if let i = self?.tasks.firstIndex(where: { $0.id == old.id }) { self?.tasks[i] = old } }) { backend, owner in
            _ = try await backend.householdUpdate(table: "tasks", owner: owner, id: task.id, fields: fields)
        }
    }
    func update(_ task: HTask, fields: [String: JSONValue], apply: (inout HTask) -> Void) async {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        let old = tasks[index]; apply(&tasks[index])
        var payload = fields; if let me { payload["updated_by"] = .string(me.id) }
        _ = await run("לא הצלחנו לשמור את השינויים.", rollback: { [weak self] in if let i = self?.tasks.firstIndex(where: { $0.id == old.id }) { self?.tasks[i] = old } }) { backend, owner in
            _ = try await backend.householdUpdate(table: "tasks", owner: owner, id: task.id, fields: payload)
        }
    }
    func delete(_ task: HTask) async {
        let removed = tasks.filter { $0.id == task.id || $0.parentID == task.id }
        tasks.removeAll { $0.id == task.id || $0.parentID == task.id }
        var fields: [String: JSONValue] = ["deleted_at": .string(now())]; if let me { fields["updated_by"] = .string(me.id) }
        _ = await run("לא הצלחנו למחוק את המשימה.", rollback: { [weak self] in self?.tasks.append(contentsOf: removed) }) { backend, owner in
            for item in removed { _ = try await backend.householdUpdate(table: "tasks", owner: owner, id: item.id, fields: fields) }
        }
    }
    func clearCompleted(in section: HSection) async { for task in tasks.filter({ $0.sectionID == section.id && $0.isCompleted && $0.parentID == nil }) { await delete(task) } }

    func complete(_ chore: HChore) async {
        guard let me else { return }
        let ok = await run("לא הצלחנו לסמן את המטלה כבוצעה.", rollback: {}) { backend, owner in
            try await backend.householdRPC("complete_chore", owner: owner, args: ["p_chore_id": .string(chore.id), "p_completed_by": .string(me.id)])
        }
        if ok { await refresh() }
    }
    func addChore(title: String, section: HSection, freq: String, interval: Int) async {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 300, ["daily", "weekly", "monthly"].contains(freq),
              let position = try? FractionalIndex.atEnd(chores.filter { $0.sectionID == section.id }.map(\.position).max()) else { return }
        let id = UUID().uuidString.lowercased()
        var fields: [String: JSONValue] = ["id": .string(id), "section_id": .string(section.id), "position": .string(position), "title": .string(clean), "freq": .string(freq),
                                           "interval_n": .number(Double(max(1, min(60, interval)))), "assignee_kind": .string("anyone"), "anchor_date": .string(DateParsing.dayString(Date(), zone: timeZone)), "next_due_at": .string(now())]
        if let me { fields["created_by"] = .string(me.id) }
        let ok = await run("לא הצלחנו להוסיף את המטלה.", rollback: {}) { backend, owner in _ = try await backend.householdInsert(table: "chores", owner: owner, fields: fields) }
        if ok { await refresh() }
    }
    func delete(_ chore: HChore) async {
        let old = chores; chores.removeAll { $0.id == chore.id }
        _ = await run("לא הצלחנו למחוק את המטלה.", rollback: { [weak self] in self?.chores = old }) { backend, owner in
            _ = try await backend.householdUpdate(table: "chores", owner: owner, id: chore.id, fields: ["deleted_at": .string(DateParsing.iso(Date()))])
        }
    }

    func saveEvent(id: String?, title: String, kind: String, date: Date, yearly: Bool, notes: String, emoji: String?) async {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 300, ["birthday", "medical", "other"].contains(kind) else { return }
        var fields: [String: JSONValue] = ["title": .string(clean), "kind": .string(kind), "event_date": .string(DateParsing.dayString(date, zone: timeZone)), "recurrence": .string(yearly ? "yearly" : "none"),
                                           "notes": notes.isEmpty ? .null : .string(String(notes.prefix(2000))), "emoji": emoji.map { .string($0) } ?? .null]
        let backup = events
        if let id {
            if let me { fields["updated_by"] = .string(me.id) }
            if let i = events.firstIndex(where: { $0.id == id }), let updated = HEvent(.object(fields.merging(["id": .string(id)]) { $1 })) { events[i] = updated }
            _ = await run("לא הצלחנו לשמור את האירוע.", rollback: { [weak self] in self?.events = backup }) { backend, owner in _ = try await backend.householdUpdate(table: "family_events", owner: owner, id: id, fields: fields) }
        } else {
            let newID = UUID().uuidString.lowercased(); fields["id"] = .string(newID); if let me { fields["created_by"] = .string(me.id) }
            if let created = HEvent(.object(fields)) { events.append(created) }
            _ = await run("לא הצלחנו להוסיף את האירוע.", rollback: { [weak self] in self?.events = backup }) { backend, owner in _ = try await backend.householdInsert(table: "family_events", owner: owner, fields: fields) }
        }
    }
    func delete(_ event: HEvent) async {
        let backup = events; events.removeAll { $0.id == event.id }
        _ = await run("לא הצלחנו למחוק את האירוע.", rollback: { [weak self] in self?.events = backup }) { backend, owner in
            _ = try await backend.householdUpdate(table: "family_events", owner: owner, id: event.id, fields: ["deleted_at": .string(DateParsing.iso(Date()))])
        }
    }
}

private extension JSONValue {
    /// Adds the server-side defaults an optimistic local row needs before the server replies.
    var withDefaults: JSONValue {
        guard case .object(var f) = self else { return self }
        f["is_completed"] = f["is_completed"] ?? .bool(false); f["assignee_kind"] = f["assignee_kind"] ?? .string("unassigned")
        return .object(f)
    }
}
