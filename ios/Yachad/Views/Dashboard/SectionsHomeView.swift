import SwiftUI

struct SectionsHomeView: View {
    @ObservedObject var store: AreaWorkspaceStore
    @EnvironmentObject private var appState: AppState
    @State private var showNewSection = false

    private var locale: AppLocale { appState.locale }

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.sections.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                            ForEach(store.sections.filter { $0.kind != .chores }) { section in
                                NavigationLink(value: section) {
                                    SectionCardView(section: section, tasks: store.tasks(in: section.id), locale: locale)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle(store.area.name)
            .toolbar {
                if store.canWrite {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showNewSection = true } label: { Image(systemName: "plus") }
                    }
                }
            }
            .refreshable { await store.loadAll() }
            .sheet(isPresented: $showNewSection) {
                NewSectionView(store: store)
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
}

struct SectionCardView: View {
    let section: WorkspaceSection
    let tasks: [TaskItem]
    let locale: AppLocale

    private var topLevel: [TaskItem] { tasks.filter { $0.parentTaskId == nil } }
    private var completed: Int { topLevel.filter(\.isCompleted).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(section.emoji ?? section.kind.defaultEmoji).font(.title)
                Spacer()
            }
            Text(section.name).font(.headline).lineLimit(1)
            if !topLevel.isEmpty {
                ProgressView(value: Double(completed), total: Double(topLevel.count))
                Text(locale == .he ? "\(completed) מתוך \(topLevel.count)" : "\(completed) of \(topLevel.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(locale == .he ? "ריק" : "Empty")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(sectionColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var sectionColor: Color {
        section.color.flatMap(Color.init(hex:)) ?? .indigo
    }
}
