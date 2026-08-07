import SwiftUI

struct ChoreEditorView: View {
    @ObservedObject var store: AreaWorkspaceStore
    var presetSectionId: UUID?

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var sectionId: UUID?
    @State private var freq: ChoreFrequency = .weekly
    @State private var assigneeId: UUID?
    @State private var isSaving = false
    @State private var error: String?

    private var locale: AppLocale { appState.locale }
    private var choreSections: [WorkspaceSection] { store.sections.filter { $0.kind == .chores } }

    var body: some View {
        NavigationStack {
            Form {
                TextField(locale == .he ? "כותרת" : "Title", text: $title)

                if !choreSections.isEmpty {
                    Picker(locale == .he ? "קבוצה" : "Group", selection: $sectionId) {
                        ForEach(choreSections) { section in
                            Text(section.name).tag(UUID?.some(section.id))
                        }
                    }
                }

                Picker(locale == .he ? "תדירות" : "Frequency", selection: $freq) {
                    ForEach(ChoreFrequency.allCases) { freq in
                        Text(freq.label(locale)).tag(freq)
                    }
                }

                Picker(locale == .he ? "אחראי/ת" : "Assignee", selection: $assigneeId) {
                    Text(locale == .he ? "כל אחד" : "Anyone").tag(UUID?.none)
                    ForEach(store.members.filter { $0.status == .approved }) { member in
                        Text(member.nickname).tag(UUID?.some(member.id))
                    }
                }

                if let error {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }
            }
            .navigationTitle(locale == .he ? "מטלה חדשה" : "New chore")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(locale == .he ? "ביטול" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(locale == .he ? "יצירה" : "Create") { Task { await save() } }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear {
                sectionId = presetSectionId ?? choreSections.first?.id
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let resolvedSectionId: UUID
            if let sectionId = sectionId ?? choreSections.first?.id {
                resolvedSectionId = sectionId
            } else {
                let sectionPosition = FractionalIndex.rankAtEnd(after: store.sections.map(\.position).max())
                let created = try await WorkspaceService().createSection(
                    areaId: store.area.id, name: locale == .he ? "מטלות בית" : "Chores",
                    emoji: SectionKind.chores.defaultEmoji, kind: .chores, color: nil,
                    position: sectionPosition, actorId: store.myMemberId
                )
                resolvedSectionId = created.id
            }
            let position = FractionalIndex.rankAtEnd(after: store.chores.map(\.position).max())
            try await ChoreService().createChore(
                areaId: store.area.id, sectionId: resolvedSectionId, title: title.trimmingCharacters(in: .whitespaces),
                emoji: nil, position: position, assigneeMemberId: assigneeId, freq: freq, actorId: store.myMemberId
            )
            await store.loadAll()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
