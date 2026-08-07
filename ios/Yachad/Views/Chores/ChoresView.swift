import SwiftUI

struct ChoresView: View {
    @ObservedObject var store: AreaWorkspaceStore
    var sectionFilter: UUID?

    @EnvironmentObject private var appState: AppState
    @State private var showNewChore = false
    @State private var completingId: UUID?

    private var locale: AppLocale { appState.locale }

    private var chores: [Chore] {
        let all = sectionFilter.map { filter in store.chores.filter { $0.sectionId == filter } } ?? store.chores
        return all.sorted { $0.nextDueAt < $1.nextDueAt }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(chores) { chore in
                    choreRow(chore)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(locale == .he ? "מטלות בית" : "Chores")
            .toolbar {
                if store.canWrite {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showNewChore = true } label: { Image(systemName: "plus") }
                    }
                }
            }
            .overlay {
                if chores.isEmpty {
                    ContentUnavailableView(
                        locale == .he ? "אין מטלות" : "No chores",
                        systemImage: "checklist"
                    )
                }
            }
            .refreshable { await store.loadAll() }
            .sheet(isPresented: $showNewChore) {
                ChoreEditorView(store: store, presetSectionId: sectionFilter)
            }
        }
    }

    private func choreRow(_ chore: Chore) -> some View {
        HStack {
            Button {
                Task { await complete(chore) }
            } label: {
                Image(systemName: "checkmark.circle")
                    .font(.title2)
                    .foregroundStyle(isOverdue(chore) ? .red : .accentColor)
            }
            .buttonStyle(.plain)
            .disabled(!store.canWrite || completingId == chore.id)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if let emoji = chore.emoji { Text(emoji) }
                    Text(chore.title)
                }
                HStack(spacing: 6) {
                    Text(chore.freq.label(locale))
                    Text("·")
                    Text(chore.nextDueAt.formatted(date: .abbreviated, time: .omitted))
                    if let assignee = store.member(chore.assigneeMemberId) {
                        Text("·")
                        Text(assignee.nickname)
                    }
                }
                .font(.caption)
                .foregroundStyle(isOverdue(chore) ? .red : .secondary)
            }
            Spacer()
        }
    }

    private func isOverdue(_ chore: Chore) -> Bool {
        chore.nextDueAt < Date()
    }

    private func complete(_ chore: Chore) async {
        completingId = chore.id
        defer { completingId = nil }
        try? await ChoreService().complete(choreId: chore.id, completedBy: store.myMemberId)
        await store.loadAll()
    }
}
