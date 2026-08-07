import SwiftUI

struct TaskListView: View {
    @ObservedObject var store: AreaWorkspaceStore
    let section: WorkspaceSection

    @EnvironmentObject private var appState: AppState
    @State private var quickAddTitle = ""
    @State private var editingTask: TaskItem?
    @State private var isAdding = false

    private var locale: AppLocale { appState.locale }

    private var tree: [TaskNode] {
        buildTaskTree(store.tasks(in: section.id))
    }

    var body: some View {
        List {
            ForEach(tree) { node in
                TaskRowView(node: node, store: store, depth: 0, onEdit: { editingTask = $0 })
            }
            .onDelete { offsets in
                Task { await delete(at: offsets) }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(section.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if store.canWrite {
                quickAddBar
            }
        }
        .sheet(item: $editingTask) { task in
            TaskEditorView(store: store, task: task)
        }
    }

    private var quickAddBar: some View {
        HStack {
            TextField(section.kind == .info ? (locale == .he ? "פתק חדש..." : "New note...") : (locale == .he ? "משימה חדשה..." : "New task..."), text: $quickAddTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await addTask() } }
            Button {
                Task { await addTask() }
            } label: {
                Image(systemName: "plus.circle.fill").font(.title2)
            }
            .disabled(quickAddTitle.trimmingCharacters(in: .whitespaces).isEmpty || isAdding)
        }
        .padding()
        .background(.bar)
    }

    private func addTask() async {
        let title = quickAddTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        isAdding = true
        defer { isAdding = false }
        do {
            let siblings = store.tasks(in: section.id).filter { $0.parentTaskId == nil }
            let position = FractionalIndex.rankAtEnd(after: siblings.map(\.position).max())
            try await WorkspaceService().createTask(
                areaId: store.area.id, sectionId: section.id, parentTaskId: nil, position: position,
                title: title, isNote: section.kind == .info, actorId: store.myMemberId
            )
            quickAddTitle = ""
            await store.loadAll()
        } catch {
            store.lastError = error.localizedDescription
        }
    }

    private func delete(at offsets: IndexSet) async {
        for index in offsets {
            let task = tree[index].task
            try? await WorkspaceService().softDeleteTask(id: task.id)
        }
        await store.loadAll()
    }
}
