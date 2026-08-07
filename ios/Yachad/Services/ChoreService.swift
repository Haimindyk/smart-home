import Foundation
import Supabase

struct ChoreService {
    var client: SupabaseClient { SupabaseService.shared }

    func fetchChores(areaId: UUID) async throws -> [Chore] {
        try await client
            .from("chores")
            .select()
            .eq("area_id", value: areaId.uuidString)
            .is("deleted_at", value: nil)
            .order("next_due_at")
            .execute()
            .value
    }

    func fetchRecentCompletions(choreId: UUID, limit: Int = 20) async throws -> [ChoreCompletion] {
        try await client
            .from("chore_completions")
            .select()
            .eq("chore_id", value: choreId.uuidString)
            .order("completed_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    struct NewChore: Encodable {
        let area_id: String
        let section_id: String
        let title: String
        let emoji: String?
        let position: String
        let assignee_member_id: String?
        let freq: String
        let interval_n: Int
        let weekdays: [Int]?
        let month_day: Int?
        let created_by: String?
        let updated_by: String?
    }

    @discardableResult
    func createChore(areaId: UUID, sectionId: UUID, title: String, emoji: String?, position: String, assigneeMemberId: UUID?, freq: ChoreFrequency, intervalN: Int = 1, weekdays: [Int]? = nil, monthDay: Int? = nil, actorId: UUID?) async throws -> Chore {
        try await client
            .from("chores")
            .insert(NewChore(
                area_id: areaId.uuidString, section_id: sectionId.uuidString, title: title,
                emoji: emoji, position: position, assignee_member_id: assigneeMemberId?.uuidString,
                freq: freq.rawValue, interval_n: intervalN, weekdays: weekdays, month_day: monthDay,
                created_by: actorId?.uuidString, updated_by: actorId?.uuidString
            ))
            .select()
            .single()
            .execute()
            .value
    }

    func softDelete(id: UUID) async throws {
        _ = try await client
            .from("chores")
            .update(["deleted_at": ISO8601DateFormatter().string(from: Date())])
            .eq("id", value: id.uuidString)
            .execute()
    }

    private struct CompleteChoreParams: Encodable { let p_chore_id: String; let p_completed_by: String }

    /// Records a completion and advances `next_due_at` server-side (never
    /// trust the client's clock for scheduling).
    func complete(choreId: UUID, completedBy: UUID) async throws {
        _ = try await client
            .rpc("complete_chore", params: CompleteChoreParams(p_chore_id: choreId.uuidString, p_completed_by: completedBy.uuidString))
            .execute()
    }
}
