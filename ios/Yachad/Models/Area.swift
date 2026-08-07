import Foundation

struct Area: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var emoji: String?
    var inviteCode: String
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, emoji
        case inviteCode = "invite_code"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum AreaRole: String, Codable, CaseIterable, Identifiable {
    case owner
    case editor
    case viewer

    var id: String { rawValue }

    /// Owner and editor can create/edit/complete/delete content; viewer is read-only.
    var canWrite: Bool { self != .viewer }

    func label(_ locale: AppLocale) -> String {
        switch (self, locale) {
        case (.owner, .he): return "בעל/ת האזור"
        case (.owner, .en): return "Owner"
        case (.editor, .he): return "קריאה וכתיבה"
        case (.editor, .en): return "Read & write"
        case (.viewer, .he): return "קריאה בלבד"
        case (.viewer, .en): return "Read only"
        }
    }
}

enum AreaMemberStatus: String, Codable {
    case pending
    case approved
    case rejected
}

struct AreaMember: Codable, Identifiable, Hashable {
    let id: UUID
    var areaId: UUID
    var deviceId: UUID
    var nickname: String
    var role: AreaRole
    var status: AreaMemberStatus
    var color: String
    var avatarEmoji: String?
    var requestedAt: Date
    var approvedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, nickname, role, status, color
        case areaId = "area_id"
        case deviceId = "device_id"
        case avatarEmoji = "avatar_emoji"
        case requestedAt = "requested_at"
        case approvedAt = "approved_at"
    }
}

/// One area plus "my" membership row in it — the shape the areas list and
/// dashboard actually need (which role am I, am I still pending approval).
struct AreaMembership: Codable, Identifiable, Hashable {
    var area: Area
    var membership: AreaMember

    var id: UUID { area.id }
}
