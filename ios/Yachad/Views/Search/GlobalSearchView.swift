import SwiftUI

/// Instant client-side search across tasks, chores, and calendar events.
/// Simplified vs. the website's fuzzy (fuse.js) search — plain
/// case-/diacritic-insensitive substring matching, which is enough for a
/// household-sized list and needs no extra dependency.
struct GlobalSearchView: View {
    @ObservedObject var store: AreaWorkspaceStore
    @EnvironmentObject private var appState: AppState
    @State private var query = ""
    @State private var editingTask: TaskItem?

    private var locale: AppLocale { appState.locale }

    private var matchingTasks: [TaskItem] {
        guard !query.isEmpty else { return [] }
        return store.tasks.filter { $0.deletedAt == nil && matches($0.title) }
    }

    private var matchingChores: [Chore] {
        guard !query.isEmpty else { return [] }
        return store.chores.filter { matches($0.title) }
    }

    private var matchingEvents: [CalendarEvent] {
        guard !query.isEmpty else { return [] }
        return store.events.filter { matches($0.title) }
    }

    private func matches(_ text: String) -> Bool {
        text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    var body: some View {
        NavigationStack {
            List {
                if !matchingTasks.isEmpty {
                    Section(locale == .he ? "משימות" : "Tasks") {
                        ForEach(matchingTasks) { task in
                            Button {
                                editingTask = task
                            } label: {
                                HStack {
                                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(task.isCompleted ? .green : .secondary)
                                    Text(task.title).foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                }
                if !matchingChores.isEmpty {
                    Section(locale == .he ? "מטלות" : "Chores") {
                        ForEach(matchingChores) { chore in
                            Text(chore.title)
                        }
                    }
                }
                if !matchingEvents.isEmpty {
                    Section(locale == .he ? "יומן" : "Calendar") {
                        ForEach(matchingEvents) { event in
                            Text(event.title)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: locale == .he ? "חיפוש" : "Search")
            .navigationTitle(locale == .he ? "חיפוש" : "Search")
            .overlay {
                if query.isEmpty {
                    ContentUnavailableView(
                        locale == .he ? "חפשו משהו" : "Search for something",
                        systemImage: "magnifyingglass"
                    )
                } else if matchingTasks.isEmpty && matchingChores.isEmpty && matchingEvents.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .sheet(item: $editingTask) { task in
                TaskEditorView(store: store, task: task)
            }
        }
    }
}
