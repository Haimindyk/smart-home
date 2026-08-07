import Foundation

enum ChoreFrequency: String, Codable, CaseIterable, Identifiable {
    case daily
    case weekly
    case monthly
    case custom
    case asNeeded = "as_needed"

    var id: String { rawValue }

    func label(_ locale: AppLocale) -> String {
        switch (self, locale) {
        case (.daily, .he): return "יומי"
        case (.daily, .en): return "Daily"
        case (.weekly, .he): return "שבועי"
        case (.weekly, .en): return "Weekly"
        case (.monthly, .he): return "חודשי"
        case (.monthly, .en): return "Monthly"
        case (.custom, .he): return "מותאם אישית"
        case (.custom, .en): return "Custom"
        case (.asNeeded, .he): return "לפי הצורך"
        case (.asNeeded, .en): return "As needed"
        }
    }
}

struct Chore: Codable, Identifiable, Hashable {
    let id: UUID
    var areaId: UUID
    var sectionId: UUID
    var title: String
    var notes: String?
    var emoji: String?
    var position: String

    var assigneeMemberIds: [UUID]

    var freq: ChoreFrequency
    var intervalN: Int
    var weekdays: [Int]?
    var monthDay: Int?
    var anchorDate: Date
    var nextDueAt: Date

    var deletedAt: Date?
    var createdBy: UUID?
    var updatedBy: UUID?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, notes, emoji, position, freq, weekdays
        case areaId = "area_id"
        case sectionId = "section_id"
        case assigneeMemberIds = "assignee_member_ids"
        case intervalN = "interval_n"
        case monthDay = "month_day"
        case anchorDate = "anchor_date"
        case nextDueAt = "next_due_at"
        case deletedAt = "deleted_at"
        case createdBy = "created_by"
        case updatedBy = "updated_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ChoreCompletion: Codable, Identifiable, Hashable {
    let id: UUID
    var areaId: UUID
    var choreId: UUID
    var completedBy: UUID
    var completedAt: Date
    var dueAt: Date
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case areaId = "area_id"
        case choreId = "chore_id"
        case completedBy = "completed_by"
        case completedAt = "completed_at"
        case dueAt = "due_at"
        case createdAt = "created_at"
    }
}
