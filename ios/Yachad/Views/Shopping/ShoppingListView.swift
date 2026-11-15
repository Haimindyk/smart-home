import SwiftUI

struct ShoppingListView: View {
    @ObservedObject var store: AreaWorkspaceStore
    let section: WorkspaceSection

    @EnvironmentObject private var appState: AppState
    @State private var quickAddTitle = ""
    @State private var editingTask: TaskItem?
    @State private var isAdding = false

    private var locale: AppLocale { appState.locale }

    private var items: [TaskItem] {
        store.tasks(in: section.id)
            .filter { $0.parentTaskId == nil }
            .sorted { a, b in
                if a.isCompleted != b.isCompleted { return !a.isCompleted }
                return a.position < b.position
            }
    }

    var body: some View {
        List {
            ForEach(items) { item in
                row(item)
            }
            .onDelete { offsets in
                Task { await delete(at: offsets) }
            }
            .onMove { offsets, newOffset in
                Task { await reorder(from: offsets, to: newOffset) }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(section.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if store.canWrite && items.count > 1 {
                ToolbarItem(placement: .primaryAction) { EditButton() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if store.canWrite {
                HStack {
                    TextField(locale == .he ? "מוצר חדש..." : "New item...", text: $quickAddTitle)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await addItem() } }
                    Button { Task { await addItem() } } label: {
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }
                    .disabled(quickAddTitle.trimmingCharacters(in: .whitespaces).isEmpty || isAdding)
                }
                .padding()
                .background(.bar)
            }
        }
        .sheet(item: $editingTask) { task in
            TaskEditorView(store: store, task: task)
        }
    }

    private func row(_ item: TaskItem) -> some View {
        HStack(spacing: 10) {
            Button {
                Task { await toggle(item) }
            } label: {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "cart.circle")
                    .foregroundStyle(item.isCompleted ? .green : .accentColor)
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .disabled(!store.canWrite)

            VStack(alignment: .leading, spacing: 2) {
                BidiText(item.title).strikethrough(item.isCompleted)
                HStack(spacing: 6) {
                    if let quantity = item.quantity {
                        Text("\(quantity.formatted())\(item.unit.map { " \($0)" } ?? "")")
                    }
                    if let brand = item.brand, !brand.isEmpty {
                        Text(brand)
                    }
                    if let price = item.price {
                        Text(price, format: .currency(code: item.currency ?? "ILS"))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { editingTask = item }
    }

    private func addItem() async {
        let title = quickAddTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        isAdding = true
        defer { isAdding = false }
        let position = FractionalIndex.rankAtEnd(after: items.map(\.position).max())
        try? await WorkspaceService().createTask(
            areaId: store.area.id, sectionId: section.id, parentTaskId: nil, position: position,
            title: title, actorId: store.myMemberId
        )
        quickAddTitle = ""
        await store.loadAll()
    }

    private func toggle(_ item: TaskItem) async {
        try? await WorkspaceService().setCompleted(id: item.id, isCompleted: !item.isCompleted, actorId: store.myMemberId)
        await store.loadAll()
    }

    private func delete(at offsets: IndexSet) async {
        let deleted = offsets.map { items[$0] }
        for item in deleted {
            try? await WorkspaceService().softDeleteTask(id: item.id)
        }
        await store.loadAll()

        let message = deleted.count == 1
            ? (locale == .he ? "\"\(deleted[0].title)\" נמחק" : "\"\(deleted[0].title)\" deleted")
            : (locale == .he ? "\(deleted.count) פריטים נמחקו" : "\(deleted.count) items deleted")
        store.showUndo(message: message) {
            for item in deleted {
                try? await WorkspaceService().restoreTask(id: item.id)
            }
        }
    }

    private func reorder(from offsets: IndexSet, to newOffset: Int) async {
        var reordered = items.map(\.id)
        reordered.move(fromOffsets: offsets, toOffset: newOffset)
        try? await WorkspaceService().reorderTasks(reordered)
        await store.loadAll()
    }
}
