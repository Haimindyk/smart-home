import Foundation
import Supabase

struct BroadcastService {
    var client: SupabaseClient { SupabaseService.shared }

    func fetchRecent(areaId: UUID, limit: Int = 20) async throws -> [BroadcastMessage] {
        try await client
            .from("broadcasts")
            .select()
            .eq("area_id", value: areaId.uuidString)
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    struct NewBroadcast: Encodable {
        let area_id: String
        let message: String
        let sent_by: String?
    }

    @discardableResult
    func send(areaId: UUID, message: String, actorId: UUID?) async throws -> BroadcastMessage {
        try await client
            .from("broadcasts")
            .insert(NewBroadcast(area_id: areaId.uuidString, message: message, sent_by: actorId?.uuidString))
            .select()
            .single()
            .execute()
            .value
    }
}
