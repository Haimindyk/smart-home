import SwiftUI

struct CalendarView: View {
    @ObservedObject var store: AreaWorkspaceStore
    @EnvironmentObject private var appState: AppState
    @State private var showNewEvent = false

    private var locale: AppLocale { appState.locale }

    private var upcoming: [CalendarEvent] {
        store.events.sorted { $0.eventDate < $1.eventDate }
    }

    private var grouped: [(String, [CalendarEvent])] {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = locale == .he ? "MMMM yyyy" : "MMMM yyyy"
        formatter.locale = Locale(identifier: locale == .he ? "he_IL" : "en_US")

        var order: [String] = []
        var buckets: [String: [CalendarEvent]] = [:]
        for event in upcoming {
            let key = formatter.string(from: event.eventDate)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(event)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(grouped, id: \.0) { month, events in
                    Section(month) {
                        ForEach(events) { event in
                            eventRow(event)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(locale == .he ? "יומן" : "Calendar")
            .toolbar {
                if store.canWrite {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showNewEvent = true } label: { Image(systemName: "plus") }
                    }
                }
            }
            .overlay {
                if upcoming.isEmpty {
                    ContentUnavailableView(locale == .he ? "אין אירועים" : "No events", systemImage: "calendar")
                }
            }
            .refreshable { await store.loadAll() }
            .sheet(isPresented: $showNewEvent) {
                EventEditorView(store: store)
            }
        }
    }

    private func eventRow(_ event: CalendarEvent) -> some View {
        HStack {
            Text(event.emoji ?? event.kind.emoji).font(.title2)
            VStack(alignment: .leading) {
                Text(event.title)
                Text(event.eventDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .swipeActions {
            if store.canWrite {
                Button(role: .destructive) {
                    Task {
                        try? await CalendarService().softDelete(id: event.id)
                        await store.loadAll()
                        store.showUndo(message: locale == .he ? "\"\(event.title)\" נמחק" : "\"\(event.title)\" deleted") {
                            try? await CalendarService().restore(id: event.id)
                        }
                    }
                } label: {
                    Label(locale == .he ? "מחיקה" : "Delete", systemImage: "trash")
                }
            }
        }
    }
}
