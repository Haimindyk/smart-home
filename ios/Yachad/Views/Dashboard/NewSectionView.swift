import SwiftUI

struct NewSectionView: View {
    @ObservedObject var store: AreaWorkspaceStore
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kind: SectionKind = .tasks
    @State private var isSaving = false
    @State private var error: String?

    private var locale: AppLocale { appState.locale }

    var body: some View {
        NavigationStack {
            Form {
                TextField(locale == .he ? "שם" : "Name", text: $name)
                Picker(locale == .he ? "סוג" : "Kind", selection: $kind) {
                    ForEach(SectionKind.allCases) { kind in
                        Text("\(kind.defaultEmoji) \(kind.label(locale))").tag(kind)
                    }
                }
                if let error {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }
            }
            .navigationTitle(locale == .he ? "מדור חדש" : "New section")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(locale == .he ? "ביטול" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(locale == .he ? "יצירה" : "Create") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let position = FractionalIndex.rankAtEnd(after: store.sections.map(\.position).max())
            try await WorkspaceService().createSection(
                areaId: store.area.id, name: name.trimmingCharacters(in: .whitespaces),
                emoji: kind.defaultEmoji, kind: kind, color: nil, position: position,
                actorId: store.myMemberId
            )
            await store.loadAll()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
