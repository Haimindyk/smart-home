import Foundation

enum SectionKind: String, Codable, CaseIterable, Identifiable {
    case tasks
    case shopping
    case chores
    case info

    var id: String { rawValue }

    var defaultEmoji: String {
        switch self {
        case .tasks: return "✅"
        case .shopping: return "🛒"
        case .chores: return "🧹"
        case .info: return "📌"
        }
    }

    func label(_ locale: AppLocale) -> String {
        switch (self, locale) {
        case (.tasks, .he): return "משימות"
        case (.tasks, .en): return "Tasks"
        case (.shopping, .he): return "קניות"
        case (.shopping, .en): return "Shopping"
        case (.chores, .he): return "מטלות בית"
        case (.chores, .en): return "Chores"
        case (.info, .he): return "מידע"
        case (.info, .en): return "Info"
        }
    }
}

struct WorkspaceSection: Codable, Identifiable, Hashable {
    let id: UUID
    var areaId: UUID
    var name: String
    var emoji: String?
    var kind: SectionKind
    var color: String?
    var description: String?
    var position: String
    var deletedAt: Date?
    var createdBy: UUID?
    var updatedBy: UUID?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, emoji, kind, color, description, position
        case areaId = "area_id"
        case deletedAt = "deleted_at"
        case createdBy = "created_by"
        case updatedBy = "updated_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct TaskItem: Codable, Identifiable, Hashable {
    let id: UUID
    var areaId: UUID
    var sectionId: UUID
    var parentTaskId: UUID?
    var position: String

    var title: String
    var notes: String?
    var emoji: String?
    var priority: Int?
    var dueAt: Date?
    var dueEndAt: Date?
    var tags: [String]
    /// Server-derived (see the `extract_links` trigger) — never set by the
    /// client, just auto-extracted URLs from `title`/`notes`.
    var detectedLinks: [String]
    var isNote: Bool

    var assigneeMemberIds: [UUID]

    var isCompleted: Bool
    var completedAt: Date?
    var completedBy: UUID?

    // Shopping-flavored fields (nil outside shopping sections).
    var quantity: Double?
    var unit: String?
    var price: Double?
    var currency: String?
    var brand: String?

    var deletedAt: Date?
    var createdBy: UUID?
    var updatedBy: UUID?
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, position, title, notes, emoji, priority, tags
        case areaId = "area_id"
        case sectionId = "section_id"
        case parentTaskId = "parent_task_id"
        case dueAt = "due_at"
        case dueEndAt = "due_end_at"
        case detectedLinks = "detected_links"
        case isNote = "is_note"
        case assigneeMemberIds = "assignee_member_ids"
        case isCompleted = "is_completed"
        case completedAt = "completed_at"
        case completedBy = "completed_by"
        case quantity, unit, price, currency, brand
        case deletedAt = "deleted_at"
        case createdBy = "created_by"
        case updatedBy = "updated_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// A task with its children materialized into a tree (client-side only,
/// mirrors the website's `buildTaskTree`).
struct TaskNode: Identifiable, Hashable {
    var task: TaskItem
    var children: [TaskNode]

    var id: UUID { task.id }
}

func buildTaskTree(_ tasks: [TaskItem]) -> [TaskNode] {
    var byParent: [UUID?: [TaskItem]] = [:]
    for task in tasks {
        byParent[task.parentTaskId, default: []].append(task)
    }
    for key in byParent.keys {
        byParent[key]?.sort { a, b in
            if a.isCompleted != b.isCompleted { return !a.isCompleted }
            return a.position < b.position
        }
    }
    func attach(_ parentId: UUID?) -> [TaskNode] {
        (byParent[parentId] ?? []).map { TaskNode(task: $0, children: attach($0.id)) }
    }
    return attach(nil)
}
