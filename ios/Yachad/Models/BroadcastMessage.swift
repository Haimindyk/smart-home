import Foundation

struct BroadcastMessage: Codable, Identifiable, Hashable {
    let id: UUID
    var areaId: UUID
    var message: String
    var sentBy: UUID?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, message
        case areaId = "area_id"
        case sentBy = "sent_by"
        case createdAt = "created_at"
    }
}
