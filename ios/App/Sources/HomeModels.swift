import Foundation
import WellnessCore

// Household domain (shared with the web app): sections, tasks, chores, events, members.

enum DateParsing {
    private static let fractional: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    private static let plain: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }()
    static func timestamp(_ s: String?) -> Date? { s.flatMap { fractional.date(from: $0) ?? plain.date(from: $0) } }
    static func iso(_ d: Date) -> String { plain.string(from: d) }
    /// Calendar day strings (yyyy-MM-dd) are interpreted in the given zone.
    static func day(_ s: String?, zone: TimeZone) -> Date? {
        guard let s else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = zone; f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(s.prefix(10)))
    }
    static func dayString(_ d: Date, zone: TimeZone) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = zone; f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}

extension JSONValue {
    func str(_ key: String) -> String? { self[key].stringValue }
    func flag(_ key: String) -> Bool { self[key].boolValue == true }
    func num(_ key: String) -> Double? { self[key].doubleValue }
    func strings(_ key: String) -> [String] { self[key].arrayValue.compactMap(\.stringValue) }
}

struct HSection: Identifiable, Equatable {
    let id: String; var name: String; var emoji: String?; var kind: String; var position: String; var color: String?
    init?(_ j: JSONValue) {
        guard let id = j.str("id"), let name = j.str("name") else { return nil }
        self.id = id; self.name = name; emoji = j.str("emoji"); kind = j.str("kind") ?? "tasks"; position = j.str("position") ?? ""; color = j.str("color")
    }
}

struct HTask: Identifiable, Equatable {
    let id: String; var sectionID: String; var parentID: String?; var title: String; var notes: String?; var emoji: String?
    var priority: Int?; var dueAt: Date?; var isCompleted: Bool; var completedAt: Date?
    var assigneeKind: String; var assigneeIDs: [String]; var quantity: Double?; var unit: String?; var price: Double?
    var position: String; var isNote: Bool; var tags: [String]
    init?(_ j: JSONValue) {
        guard let id = j.str("id"), let section = j.str("section_id"), let title = j.str("title") else { return nil }
        self.id = id; sectionID = section; parentID = j.str("parent_task_id"); self.title = title; notes = j.str("notes"); emoji = j.str("emoji")
        priority = j.num("priority").map { Int($0) }; dueAt = DateParsing.timestamp(j.str("due_at")); isCompleted = j.flag("is_completed"); completedAt = DateParsing.timestamp(j.str("completed_at"))
        assigneeKind = j.str("assignee_kind") ?? "unassigned"
        var ids = j.strings("assignee_member_ids"); if ids.isEmpty, let single = j.str("assignee_member_id") { ids = [single] }
        assigneeIDs = ids; quantity = j.num("quantity"); unit = j.str("unit"); price = j.num("price")
        position = j.str("position") ?? ""; isNote = j.flag("is_note"); tags = j.strings("tags")
    }
}

struct HChore: Identifiable, Equatable {
    let id: String; var sectionID: String; var title: String; var emoji: String?; var freq: String; var intervalN: Int
    var nextDue: Date?; var assigneeKind: String; var assigneeIDs: [String]; var notes: String?; var position: String
    init?(_ j: JSONValue) {
        guard let id = j.str("id"), let section = j.str("section_id"), let title = j.str("title") else { return nil }
        self.id = id; sectionID = section; self.title = title; emoji = j.str("emoji"); freq = j.str("freq") ?? "weekly"; intervalN = Int(j.num("interval_n") ?? 1)
        nextDue = DateParsing.timestamp(j.str("next_due_at")); assigneeKind = j.str("assignee_kind") ?? "anyone"
        var ids = j.strings("assignee_member_ids"); if ids.isEmpty, let single = j.str("assignee_member_id") { ids = [single] }
        assigneeIDs = ids; notes = j.str("notes"); position = j.str("position") ?? ""
    }
}

struct HEvent: Identifiable, Equatable {
    let id: String; var title: String; var emoji: String?; var kind: String; var eventDate: String; var endDate: String?; var recurrence: String; var notes: String?
    init?(_ j: JSONValue) {
        guard let id = j.str("id"), let title = j.str("title"), let date = j.str("event_date") else { return nil }
        self.id = id; self.title = title; emoji = j.str("emoji"); kind = j.str("kind") ?? "other"; eventDate = String(date.prefix(10)); endDate = j.str("end_date").map { String($0.prefix(10)) }
        recurrence = j.str("recurrence") ?? "none"; notes = j.str("notes")
    }
    /// First occurrence on or after `from` (yearly events repeat on the same month/day; Feb 29 falls back to Feb 28).
    func nextOccurrence(from: Date, zone: TimeZone) -> Date? {
        guard let base = DateParsing.day(eventDate, zone: zone) else { return nil }
        guard recurrence == "yearly" else { return base }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        let start = cal.startOfDay(for: from)
        let c = cal.dateComponents([.month, .day], from: base)
        for offset in 0...1 {
            var comps = DateComponents(); comps.year = cal.component(.year, from: start) + offset; comps.month = c.month; comps.day = c.day
            if let d = cal.date(from: comps), cal.component(.month, from: d) == c.month, d >= start { return d }
            comps.day = (c.day == 29 && c.month == 2) ? 28 : c.day
            if let d = cal.date(from: comps), d >= start { return d }
        }
        return nil
    }
}

struct HMember: Identifiable, Equatable {
    let id: String; var name: String; var emoji: String?; var color: String; var photoURL: URL?
    init?(_ j: JSONValue) {
        guard let id = j.str("id"), let name = j.str("display_name") else { return nil }
        self.id = id; self.name = name; emoji = j.str("avatar_emoji"); color = j.str("color") ?? "#888888"
        photoURL = j.str("avatar_photo_url").flatMap { URL(string: $0) }.flatMap { $0.scheme == "https" ? $0 : nil }
    }
}

struct HActivity: Identifiable, Equatable {
    let id: String; var action: String; var entityType: String; var summary: String; var actorID: String?; var createdAt: Date?
    init?(_ j: JSONValue) {
        guard let id = j.str("id") else { return nil }
        self.id = id; action = j.str("action") ?? ""; entityType = j.str("entity_type") ?? ""; summary = j.str("summary") ?? ""
        actorID = j.str("actor_id"); createdAt = DateParsing.timestamp(j.str("created_at"))
    }
}

struct HSuggestion: Identifiable, Equatable {
    let id: String; var emoji: String?; var summary: String; var action: JSONValue
    init?(_ j: JSONValue) {
        guard let id = j.str("id"), let summary = j.str("summary") else { return nil }
        self.id = id; emoji = j.str("emoji"); self.summary = summary; action = j["action"]
    }
    /// Action types the app can apply itself (the same vocabulary as the web app's applyProposedAction).
    var isApplicable: Bool { ["create_task", "create_chore", "create_family_event", "complete_chore", "toggle_task_completed", "create_section"].contains(action.str("type") ?? "") }
}

struct HPrivateNote: Identifiable, Equatable {
    let id: String; var memberID: String; var summary: String
    init?(_ j: JSONValue) {
        guard let id = j.str("id"), let member = j.str("member_id"), let summary = j.str("summary") else { return nil }
        self.id = id; memberID = member; self.summary = summary
    }
}
