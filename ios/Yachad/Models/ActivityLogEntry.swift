import Foundation

struct ActivityLogEntry: Codable, Identifiable, Hashable {
    let id: UUID
    var areaId: UUID
    var entityType: String
    var entityId: UUID
    var action: String
    var actorId: UUID?
    var summary: String?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, action, summary
        case areaId = "area_id"
        case entityType = "entity_type"
        case entityId = "entity_id"
        case actorId = "actor_id"
        case createdAt = "created_at"
    }
}
