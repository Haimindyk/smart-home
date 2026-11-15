import Foundation

enum CalendarEventKind: String, Codable, CaseIterable, Identifiable {
    case birthday
    case medical
    case other

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .birthday: return "🎂"
        case .medical: return "🩺"
        case .other: return "📅"
        }
    }
}

enum CalendarEventRecurrence: String, Codable, CaseIterable {
    case none
    case yearly
}

struct CalendarEvent: Codable, Identifiable, Hashable {
    let id: UUID
    var areaId: UUID
    var title: String
    var emoji: String?
    var notes: String?
    var kind: CalendarEventKind
    var eventDate: Date
    var endDate: Date?
    var recurrence: CalendarEventRecurrence
    var deletedAt: Date?
    var createdBy: UUID?
    var updatedBy: UUID?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, emoji, notes, kind, recurrence
        case areaId = "area_id"
        case eventDate = "event_date"
        case endDate = "end_date"
        case deletedAt = "deleted_at"
        case createdBy = "created_by"
        case updatedBy = "updated_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
