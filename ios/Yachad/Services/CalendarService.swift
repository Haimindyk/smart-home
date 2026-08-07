import Foundation
import Supabase

struct CalendarService {
    var client: SupabaseClient { SupabaseService.shared }

    func fetchEvents(areaId: UUID) async throws -> [CalendarEvent] {
        try await client
            .from("calendar_events")
            .select()
            .eq("area_id", value: areaId.uuidString)
            .is("deleted_at", value: nil)
            .order("event_date")
            .execute()
            .value
    }

    struct NewEvent: Encodable {
        let area_id: String
        let title: String
        let emoji: String?
        let notes: String?
        let kind: String
        let event_date: String
        let end_date: String?
        let recurrence: String
        let created_by: String?
        let updated_by: String?
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    @discardableResult
    func createEvent(areaId: UUID, title: String, emoji: String?, notes: String?, kind: CalendarEventKind, date: Date, endDate: Date?, recurrence: CalendarEventRecurrence, actorId: UUID?) async throws -> CalendarEvent {
        try await client
            .from("calendar_events")
            .insert(NewEvent(
                area_id: areaId.uuidString, title: title, emoji: emoji, notes: notes,
                kind: kind.rawValue, event_date: Self.dayFormatter.string(from: date),
                end_date: endDate.map(Self.dayFormatter.string(from:)), recurrence: recurrence.rawValue,
                created_by: actorId?.uuidString, updated_by: actorId?.uuidString
            ))
            .select()
            .single()
            .execute()
            .value
    }

    func softDelete(id: UUID) async throws {
        _ = try await client
            .from("calendar_events")
            .update(["deleted_at": ISO8601DateFormatter().string(from: Date())])
            .eq("id", value: id.uuidString)
            .execute()
    }
}
