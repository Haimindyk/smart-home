import SwiftUI

struct SectionsHomeView: View {
    @ObservedObject var store: AreaWorkspaceStore
    @EnvironmentObject private var appState: AppState
    @State private var showNewSection = false
    @State private var showReorder = false

    private var locale: AppLocale { appState.locale }
    private var visibleSections: [WorkspaceSection] { store.sections.filter { $0.kind != .chores } }

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.sections.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        BroadcastBannerView(store: store)
                            .padding(.top, 4)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                            ForEach(visibleSections) { section in
                                NavigationLink(value: section) {
                                    SectionCardView(section: section, tasks: store.tasks(in: section.id), locale: locale)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    if store.canWrite {
                                        Button(role: .destructive) {
                                            Task { await deleteSection(section) }
                                        } label: {
                                            Label(locale == .he ? "מחיקת מדור" : "Delete section", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
            .background(AmbientBackgroundView())
            .navigationTitle(store.area.name)
            .toolbar {
                if store.canWrite {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showNewSection = true } label: { Image(systemName: "plus") }
                    }
                    if visibleSections.count > 1 {
                        ToolbarItem(placement: .secondaryAction) {
                            Button { showReorder = true } label: { Image(systemName: "arrow.up.arrow.down") }
                        }
                    }
                }
            }
            .refreshable { await store.loadAll() }
            .sheet(isPresented: $showNewSection) {
                NewSectionView(store: store)
            }
            .sheet(isPresented: $showReorder) {
                ReorderSectionsView(store: store)
            }
            .navigationDestination(for: WorkspaceSection.self) { section in
                switch section.kind {
                case .shopping:
                    ShoppingListView(store: store, section: section)
                case .tasks, .info:
                    TaskListView(store: store, section: section)
                case .chores:
                    ChoresView(store: store, sectionFilter: section.id)
                }
            }
        }
    }

    private func deleteSection(_ section: WorkspaceSection) async {
        try? await WorkspaceService().softDeleteSection(id: section.id)
        await store.loadAll()
        store.showUndo(message: locale == .he ? "\"\(section.name)\" נמחק" : "\"\(section.name)\" deleted") {
            try? await WorkspaceService().restoreSection(id: section.id)
        }
    }
}

/// Mirrors the website's dashboard `SectionPanel` treatment: a translucent
/// "glass" card with a thin colored strip along the top and a colored
/// emoji badge, the color picked by section *kind* (not the app's own
/// accent) so cards stay visually distinguishable from one another.
struct SectionCardView: View {
    let section: WorkspaceSection
    let tasks: [TaskItem]
    let locale: AppLocale

    private var topLevel: [TaskItem] { tasks.filter { $0.parentTaskId == nil } }
    private var completed: Int { topLevel.filter(\.isCompleted).count }
    private var kindColor: Color { Theme.SectionKindColor.forKind(section.kind) }

    var body: some View {
        ZStack(alignment: .top) {
            kindColor.frame(height: 4)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(section.emoji ?? section.kind.defaultEmoji)
                        .font(.title3)
                        .frame(width: 34, height: 34)
                        .background(kindColor, in: RoundedRectangle(cornerRadius: 11))
                    Spacer()
                }
                Text(section.name)
                    .font(.headline)
                    .lineLimit(1)
                if !topLevel.isEmpty {
                    ProgressView(value: Double(completed), total: Double(topLevel.count))
                        .tint(kindColor)
                    Text(locale == .he ? "\(completed) מתוך \(topLevel.count)" : "\(completed) of \(topLevel.count)")
                        .font(.caption)
                        .foregroundStyle(Theme.mutedForeground)
                } else {
                    Text(locale == .he ? "ריק" : "Empty")
                        .font(.caption)
                        .foregroundStyle(Theme.mutedForeground)
                }
            }
            .padding(14)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card)
                .strokeBorder(Theme.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
    }
}
