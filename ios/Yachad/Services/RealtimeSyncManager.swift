import Foundation
import Supabase

/// Subscribes to Supabase Realtime for every collaborative table, scoped to
/// one area, and calls `onChange` whenever anything in it changes.
///
/// Simplification vs. the website: the website reconciles each changed row
/// into an optimistic client store. Here we just refetch the affected
/// screen's data on any change (debounced) — for the household-sized
/// membership this app targets, "always correct, occasionally one extra
/// round trip" beats hand-rolling row-level reconciliation twice.
@MainActor
final class RealtimeSyncManager {
    private var channel: RealtimeChannelV2?
    private var listenTask: Task<Void, Never>?

    private var client: SupabaseClient { SupabaseService.shared }

    func start(areaId: UUID, onChange: @escaping () -> Void) {
        stop()

        let channel = client.channel("area-\(areaId.uuidString)")
        self.channel = channel

        let tables = ["sections", "tasks", "chores", "chore_completions", "calendar_events", "area_members", "activity_log"]
        let filter = "area_id=eq.\(areaId.uuidString)"

        listenTask = Task {
            await withTaskGroup(of: Void.self) { group in
                for table in tables {
                    // area_members filters on area_id too; a device's own
                    // pending row also matches since it belongs to this area.
                    let changes = channel.postgresChange(AnyAction.self, schema: "public", table: table, filter: filter)
                    group.addTask {
                        var lastFire = Date.distantPast
                        for await _ in changes {
                            // Cheap debounce: Realtime can deliver several
                            // events in a burst (e.g. bulk reorder).
                            let now = Date()
                            if now.timeIntervalSince(lastFire) < 0.15 {
                                try? await Task.sleep(nanoseconds: 200_000_000)
                            }
                            lastFire = Date()
                            onChange()
                        }
                    }
                }
            }
        }

        Task { await channel.subscribe() }
    }

    func stop() {
        listenTask?.cancel()
        listenTask = nil
        if let channel {
            Task { await channel.unsubscribe() }
        }
        channel = nil
    }
}
