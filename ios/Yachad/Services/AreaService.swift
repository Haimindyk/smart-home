import Foundation
import Supabase

/// Everything about creating an area, inviting people to it via link/QR,
/// and the owner approving joiners with a role. All of this goes through
/// the RPCs defined in ios/backend/migrations/0002_access_control.sql —
/// there is no direct insert into `areas` / `area_members` from the client.
struct AreaService {
    let device: DeviceIdentity
    var client: SupabaseClient { SupabaseService.shared }

    // MARK: - My areas

    /// area_members joined with its parent area, restricted (by RLS) to
    /// rows for this device — i.e. every area I've created or requested to
    /// join, in any status.
    func fetchMyAreas() async throws -> [AreaMembership] {
        let rows: [AreaMemberWithArea] = try await client
            .from("area_members")
            .select("*, areas(*)")
            .eq("device_id", value: device.id.uuidString)
            .order("requested_at", ascending: false)
            .execute()
            .value

        return rows.compactMap { row in
            guard let area = row.areas else { return nil }
            return AreaMembership(area: area, membership: row.asAreaMember)
        }
    }

    // MARK: - Create / join

    private struct CreateAreaParams: Encodable {
        let p_name: String
        let p_emoji: String?
        let p_nickname: String
    }

    @discardableResult
    func createArea(name: String, emoji: String?, nickname: String) async throws -> Area {
        try await client
            .rpc("create_area", params: CreateAreaParams(p_name: name, p_emoji: emoji, p_nickname: nickname))
            .execute()
            .value
    }

    struct AreaPreview: Decodable, Identifiable {
        let id: UUID
        let name: String
        let emoji: String?
    }

    private struct PreviewParams: Encodable { let p_invite_code: String }

    func previewArea(inviteCode: String) async throws -> AreaPreview? {
        let rows: [AreaPreview] = try await client
            .rpc("area_preview_by_invite_code", params: PreviewParams(p_invite_code: inviteCode))
            .execute()
            .value
        return rows.first
    }

    private struct JoinParams: Encodable { let p_invite_code: String; let p_nickname: String }

    @discardableResult
    func requestJoin(inviteCode: String, nickname: String) async throws -> AreaMember {
        try await client
            .rpc("request_join_area", params: JoinParams(p_invite_code: inviteCode, p_nickname: nickname))
            .execute()
            .value
    }

    // MARK: - Membership management (owner)

    func fetchMembers(areaId: UUID) async throws -> [AreaMember] {
        try await client
            .from("area_members")
            .select()
            .eq("area_id", value: areaId.uuidString)
            .order("requested_at", ascending: true)
            .execute()
            .value
    }

    private struct ApproveParams: Encodable { let p_member_id: String; let p_role: String }

    @discardableResult
    func approve(memberId: UUID, role: AreaRole) async throws -> AreaMember {
        precondition(role != .owner)
        return try await client
            .rpc("approve_area_member", params: ApproveParams(p_member_id: memberId.uuidString, p_role: role.rawValue))
            .execute()
            .value
    }

    func reject(memberId: UUID) async throws {
        _ = try await client
            .from("area_members")
            .update(["status": "rejected"])
            .eq("id", value: memberId.uuidString)
            .execute()
    }

    func removeOrLeave(memberId: UUID) async throws {
        _ = try await client
            .from("area_members")
            .delete()
            .eq("id", value: memberId.uuidString)
            .execute()
    }

    func updateMyNickname(memberId: UUID, nickname: String) async throws {
        _ = try await client
            .from("area_members")
            .update(["nickname": nickname])
            .eq("id", value: memberId.uuidString)
            .execute()
    }
}

/// Decoding shim for the `area_members` <-> `areas` embedded-select shape
/// returned by PostgREST (`select("*, areas(*)")`).
private struct AreaMemberWithArea: Decodable {
    let id: UUID
    let areaId: UUID
    let deviceId: UUID
    let nickname: String
    let role: AreaRole
    let status: AreaMemberStatus
    let color: String
    let avatarEmoji: String?
    let requestedAt: Date
    let approvedAt: Date?
    let areas: Area?

    enum CodingKeys: String, CodingKey {
        case id, nickname, role, status, color, areas
        case areaId = "area_id"
        case deviceId = "device_id"
        case avatarEmoji = "avatar_emoji"
        case requestedAt = "requested_at"
        case approvedAt = "approved_at"
    }

    var asAreaMember: AreaMember {
        AreaMember(
            id: id, areaId: areaId, deviceId: deviceId, nickname: nickname, role: role,
            status: status, color: color, avatarEmoji: avatarEmoji,
            requestedAt: requestedAt, approvedAt: approvedAt
        )
    }
}
