import SwiftUI

/// The dashboard shows sections as a card grid (for browsing), which
/// SwiftUI has no native drag-to-reorder for — so reordering happens here
/// instead, in a plain reorderable list, exactly like the website's
/// section drag-and-drop.
struct ReorderSectionsView: View {
    @ObservedObject var store: AreaWorkspaceStore
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var orderedIds: [UUID]

    init(store: AreaWorkspaceStore) {
        self.store = store
        _orderedIds = State(initialValue: store.sections.map(\.id))
    }

    private var locale: AppLocale { appState.locale }
    private var orderedSections: [WorkspaceSection] {
        orderedIds.compactMap { id in store.sections.first { $0.id == id } }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(orderedSections) { section in
                    HStack {
                        Text(section.emoji ?? section.kind.defaultEmoji)
                        Text(section.name)
                    }
                }
                .onMove { offsets, newOffset in
                    orderedIds.move(fromOffsets: offsets, toOffset: newOffset)
                    Task { try? await WorkspaceService().reorderSections(orderedIds) }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(locale == .he ? "סידור מדורים" : "Reorder sections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(locale == .he ? "סיום" : "Done") { dismiss() }
                }
            }
            .onDisappear { Task { await store.loadAll() } }
        }
    }
}
