import Foundation
import Supabase

struct ActivityService {
    var client: SupabaseClient { SupabaseService.shared }

    func fetchRecent(areaId: UUID, limit: Int = 30) async throws -> [ActivityLogEntry] {
        try await client
            .from("activity_log")
            .select()
            .eq("area_id", value: areaId.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }
}
