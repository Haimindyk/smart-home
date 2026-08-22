import Foundation
import Supabase

/// Shared by every service's `restore` call: forces an explicit JSON
/// `null` for `deleted_at` (a plain `nil` value on a normal Optional
/// property gets *omitted* by Swift's synthesized Encodable instead of
/// sent as null, which would leave the row soft-deleted).
struct ClearDeletedAtPatch: Encodable {
    var deleted_at: String?? = .some(nil)
}

/// Sections + tasks (including unlimited-depth subtasks and the
/// shopping-flavored fields) for one area. Mirrors the website's unified
/// `tasks` table design — one realtime feed, one write path for tasks,
/// subtasks, and shopping items alike.
struct WorkspaceService {
    var client: SupabaseClient { SupabaseService.shared }

    // MARK: - Sections

    func fetchSections(areaId: UUID) async throws -> [WorkspaceSection] {
        try await client
            .from("sections")
            .select()
            .eq("area_id", value: areaId.uuidString)
            .is("deleted_at", value: nil)
            .order("position")
            .execute()
            .value
    }

    struct NewSection: Encodable {
        let area_id: String
        let name: String
        let emoji: String?
        let kind: String
        let color: String?
        let position: String
        let created_by: String?
        let updated_by: String?
    }

    @discardableResult
    func createSection(areaId: UUID, name: String, emoji: String?, kind: SectionKind, color: String?, position: String, actorId: UUID?) async throws -> WorkspaceSection {
        try await client
            .from("sections")
            .insert(NewSection(
                area_id: areaId.uuidString, name: name, emoji: emoji, kind: kind.rawValue,
                color: color, position: position,
                created_by: actorId?.uuidString, updated_by: actorId?.uuidString
            ))
            .select()
            .single()
            .execute()
            .value
    }

    func renameSection(id: UUID, name: String, actorId: UUID?) async throws {
        _ = try await client
            .from("sections")
            .update(["name": name, "updated_by": actorId?.uuidString])
            .eq("id", value: id.uuidString)
            .execute()
    }

    func reorderSection(id: UUID, position: String) async throws {
        _ = try await client
            .from("sections")
            .update(["position": position])
            .eq("id", value: id.uuidString)
            .execute()
    }

    func softDeleteSection(id: UUID) async throws {
        _ = try await client
            .from("sections")
            .update(["deleted_at": ISO8601DateFormatter().string(from: Date())])
            .eq("id", value: id.uuidString)
            .execute()
    }

    func restoreSection(id: UUID) async throws {
        _ = try await client
            .from("sections")
            .update(ClearDeletedAtPatch())
            .eq("id", value: id.uuidString)
            .execute()
    }

    /// Bulk-persists a full reordering — simplest-correct approach for a
    /// household-sized list: recompute a fresh, evenly-spaced position for
    /// every item in its new order rather than only the moved one.
    func reorderSections(_ orderedIds: [UUID]) async throws {
        let positions = FractionalIndex.ranksForCount(orderedIds.count)
        for (id, position) in zip(orderedIds, positions) {
            try await reorderSection(id: id, position: position)
        }
    }

    // MARK: - Tasks

    func fetchTasks(areaId: UUID) async throws -> [TaskItem] {
        try await client
            .from("tasks")
            .select()
            .eq("area_id", value: areaId.uuidString)
            .is("deleted_at", value: nil)
            .order("position")
            .execute()
            .value
    }

    struct NewTask: Encodable {
        let area_id: String
        let section_id: String
        let parent_task_id: String?
        let position: String
        let title: String
        let is_note: Bool
        let emoji: String?
        let quantity: Double?
        let unit: String?
        let brand: String?
        let assignee_member_ids: [String]
        let created_by: String?
        let updated_by: String?
    }

    /// New tasks default to assigning whoever created them (matches the
    /// website's behavior) — pass `assigneeIds` to override, e.g. an empty
    /// array for an explicitly-unassigned subtask.
    @discardableResult
    func createTask(areaId: UUID, sectionId: UUID, parentTaskId: UUID?, position: String, title: String, isNote: Bool = false, emoji: String? = nil, quantity: Double? = nil, unit: String? = nil, brand: String? = nil, assigneeIds: [UUID]? = nil, actorId: UUID?) async throws -> TaskItem {
        let assignees = assigneeIds ?? actorId.map { [$0] } ?? []
        return try await client
            .from("tasks")
            .insert(NewTask(
                area_id: areaId.uuidString, section_id: sectionId.uuidString,
                parent_task_id: parentTaskId?.uuidString, position: position, title: title,
                is_note: isNote, emoji: emoji, quantity: quantity, unit: unit, brand: brand,
                assignee_member_ids: assignees.map(\.uuidString),
                created_by: actorId?.uuidString, updated_by: actorId?.uuidString
            ))
            .select()
            .single()
            .execute()
            .value
    }

    /// Freeform patch for editing a task in the editor sheet — only the
    /// fields the sheet actually surfaces, keyed exactly like the `tasks`
    /// columns so no translation layer is needed server-side.
    struct TaskPatch: Encodable {
        var title: String? = nil
        var notes: String?? = nil
        var emoji: String?? = nil
        var priority: Int?? = nil
        var due_at: String?? = nil
        var tags: [String]? = nil
        var assignee_member_ids: [String]? = nil
        var quantity: Double?? = nil
        var unit: String?? = nil
        var price: Double?? = nil
        var brand: String?? = nil
        var updated_by: String? = nil
    }

    func updateTask(id: UUID, patch: TaskPatch) async throws {
        _ = try await client
            .from("tasks")
            .update(patch)
            .eq("id", value: id.uuidString)
            .execute()
    }

    func setCompleted(id: UUID, isCompleted: Bool, actorId: UUID?) async throws {
        struct CompletionPatch: Encodable {
            let is_completed: Bool
            let completed_at: String?
            let completed_by: String?
            let updated_by: String?
        }
        let patch = CompletionPatch(
            is_completed: isCompleted,
            completed_at: isCompleted ? ISO8601DateFormatter().string(from: Date()) : nil,
            completed_by: isCompleted ? actorId?.uuidString : nil,
            updated_by: actorId?.uuidString
        )
        _ = try await client
            .from("tasks")
            .update(patch)
            .eq("id", value: id.uuidString)
            .execute()
    }

    func moveTask(id: UUID, toSectionId: UUID, position: String) async throws {
        _ = try await client
            .from("tasks")
            .update(["section_id": toSectionId.uuidString, "position": position])
            .eq("id", value: id.uuidString)
            .execute()
    }

    func reorderTask(id: UUID, position: String) async throws {
        _ = try await client
            .from("tasks")
            .update(["position": position])
            .eq("id", value: id.uuidString)
            .execute()
    }

    /// Bulk-persists a full reordering of a flat list of siblings (top-level
    /// tasks in a section, or shopping items) — see `reorderSections` for
    /// why this recomputes every position instead of just the moved one.
    func reorderTasks(_ orderedIds: [UUID]) async throws {
        let positions = FractionalIndex.ranksForCount(orderedIds.count)
        for (id, position) in zip(orderedIds, positions) {
            try await reorderTask(id: id, position: position)
        }
    }

    private struct TaskIdParams: Encodable { let p_task_id: String }

    /// Cascading soft-delete of a task and its whole subtask subtree.
    func softDeleteTask(id: UUID) async throws {
        _ = try await client.rpc("soft_delete_task", params: TaskIdParams(p_task_id: id.uuidString)).execute()
    }

    func restoreTask(id: UUID) async throws {
        _ = try await client.rpc("restore_task", params: TaskIdParams(p_task_id: id.uuidString)).execute()
    }
}
