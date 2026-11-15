import SwiftUI

struct TaskEditorView: View {
    let task: TaskItem
    @ObservedObject var store: AreaWorkspaceStore

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var notes: String
    @State private var priority: Int
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var assigneeIds: [UUID]
    @State private var quantity: String
    @State private var unit: String
    @State private var price: String
    @State private var brand: String
    @State private var newSubtaskTitle = ""
    @State private var isSaving = false

    init(store: AreaWorkspaceStore, task: TaskItem) {
        self.store = store
        self.task = task
        _title = State(initialValue: task.title)
        _notes = State(initialValue: task.notes ?? "")
        _priority = State(initialValue: task.priority ?? 0)
        _hasDueDate = State(initialValue: task.dueAt != nil)
        _dueDate = State(initialValue: task.dueAt ?? Date())
        _assigneeIds = State(initialValue: task.assigneeMemberIds)
        _quantity = State(initialValue: task.quantity.map { String($0) } ?? "")
        _unit = State(initialValue: task.unit ?? "")
        _price = State(initialValue: task.price.map { String($0) } ?? "")
        _brand = State(initialValue: task.brand ?? "")
    }

    private var locale: AppLocale { appState.locale }
    private var section: WorkspaceSection? { store.sections.first { $0.id == task.sectionId } }
    private var isShopping: Bool { section?.kind == .shopping }
    private var subtasks: [TaskItem] { store.tasks.filter { $0.parentTaskId == task.id } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(locale == .he ? "כותרת" : "Title", text: $title)
                    TextField(locale == .he ? "הערות" : "Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                if !task.detectedLinks.isEmpty {
                    Section(locale == .he ? "קישורים" : "Links") {
                        ForEach(task.detectedLinks, id: \.self) { link in
                            if let url = URL(string: link) {
                                Link(destination: url) {
                                    Label(link, systemImage: "link")
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                        }
                    }
                }

                if isShopping {
                    Section(locale == .he ? "פרטי קנייה" : "Shopping details") {
                        HStack {
                            TextField(locale == .he ? "כמות" : "Qty", text: $quantity).keyboardType(.decimalPad)
                            TextField(locale == .he ? "יחידה" : "Unit", text: $unit)
                        }
                        TextField(locale == .he ? "מותג" : "Brand", text: $brand)
                        TextField(locale == .he ? "מחיר" : "Price", text: $price).keyboardType(.decimalPad)
                    }
                }

                Section {
                    Toggle(locale == .he ? "תאריך יעד" : "Due date", isOn: $hasDueDate.animation())
                    if hasDueDate {
                        DatePicker(locale == .he ? "תאריך" : "Date", selection: $dueDate, displayedComponents: .date)
                    }
                    Picker(locale == .he ? "עדיפות" : "Priority", selection: $priority) {
                        Text(locale == .he ? "ללא" : "None").tag(0)
                        Text(locale == .he ? "נמוכה" : "Low").tag(1)
                        Text(locale == .he ? "בינונית" : "Medium").tag(2)
                        Text(locale == .he ? "גבוהה" : "High").tag(3)
                    }
                }

                Section(locale == .he ? "אחראים" : "Assignees") {
                    AssigneeMultiSelectRows(store: store, selected: $assigneeIds)
                }

                if !task.isNote {
                    Section(locale == .he ? "תת-משימות" : "Subtasks") {
                        ForEach(subtasks) { sub in
                            HStack {
                                Button {
                                    Task { await toggle(sub) }
                                } label: {
                                    Image(systemName: sub.isCompleted ? "checkmark.circle.fill" : "circle")
                                }
                                .buttonStyle(.plain)
                                Text(sub.title).strikethrough(sub.isCompleted)
                            }
                        }
                        if store.canWrite {
                            HStack {
                                TextField(locale == .he ? "תת-משימה חדשה..." : "New subtask...", text: $newSubtaskTitle)
                                Button {
                                    Task { await addSubtask() }
                                } label: {
                                    Image(systemName: "plus.circle")
                                }
                                .disabled(newSubtaskTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                    }
                }

                if store.canWrite {
                    Section {
                        Button(role: .destructive) {
                            Task { await deleteTask() }
                        } label: {
                            Text(locale == .he ? "מחיקה" : "Delete")
                        }
                    }
                }
            }
            .disabled(!store.canWrite)
            .navigationTitle(locale == .he ? "עריכה" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(locale == .he ? "סגירה" : "Close") { dismiss() }
                }
                if store.canWrite {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(locale == .he ? "שמירה" : "Save") { Task { await save() } }
                            .disabled(isSaving)
                    }
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let patch = WorkspaceService.TaskPatch(
            title: title,
            notes: .some(notes.isEmpty ? nil : notes),
            priority: .some(priority == 0 ? nil : priority),
            due_at: .some(hasDueDate ? ISO8601DateFormatter().string(from: dueDate) : nil),
            assignee_member_ids: assigneeIds.map(\.uuidString),
            quantity: isShopping ? .some(Double(quantity)) : nil,
            unit: isShopping ? .some(unit.isEmpty ? nil : unit) : nil,
            price: isShopping ? .some(Double(price)) : nil,
            brand: isShopping ? .some(brand.isEmpty ? nil : brand) : nil,
            updated_by: store.myMemberId.uuidString
        )
        do {
            try await WorkspaceService().updateTask(id: task.id, patch: patch)
            await store.loadAll()
            dismiss()
        } catch {
            store.lastError = error.localizedDescription
        }
    }

    private func toggle(_ sub: TaskItem) async {
        try? await WorkspaceService().setCompleted(id: sub.id, isCompleted: !sub.isCompleted, actorId: store.myMemberId)
        await store.loadAll()
    }

    private func addSubtask() async {
        let title = newSubtaskTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let siblingPositions = subtasks.map(\.position)
        let position = FractionalIndex.rankAtEnd(after: siblingPositions.max())
        try? await WorkspaceService().createTask(
            areaId: store.area.id, sectionId: task.sectionId, parentTaskId: task.id, position: position,
            title: title, actorId: store.myMemberId
        )
        newSubtaskTitle = ""
        await store.loadAll()
    }

    private func deleteTask() async {
        try? await WorkspaceService().softDeleteTask(id: task.id)
        await store.loadAll()
        dismiss()
        store.showUndo(message: locale == .he ? "\"\(task.title)\" נמחקה" : "\"\(task.title)\" deleted") {
            try? await WorkspaceService().restoreTask(id: task.id)
        }
    }
}
