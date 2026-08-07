import SwiftUI

/// Renders one task and (recursively, indented) its subtasks — unlimited
/// depth, same as the website.
struct TaskRowView: View {
    let node: TaskNode
    @ObservedObject var store: AreaWorkspaceStore
    let depth: Int
    let onEdit: (TaskItem) -> Void

    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if !node.children.isEmpty {
                    Button {
                        withAnimation { isExpanded.toggle() }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.forward")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 12)
                }

                if !node.task.isNote {
                    Button {
                        Task { await toggle() }
                    } label: {
                        Image(systemName: node.task.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(node.task.isCompleted ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(!store.canWrite)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if let emoji = node.task.emoji { Text(emoji) }
                        BidiText(node.task.title)
                            .strikethrough(node.task.isCompleted)
                            .foregroundStyle(node.task.isCompleted ? .secondary : .primary)
                    }
                    HStack(spacing: 6) {
                        if let due = node.task.dueAt {
                            Label(due.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                        }
                        if let assignee = store.member(node.task.assigneeMemberId) {
                            Label(assignee.nickname, systemImage: "person")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.leading, CGFloat(depth) * 20)
            .contentShape(Rectangle())
            .onTapGesture { onEdit(node.task) }

            if isExpanded {
                ForEach(node.children) { child in
                    TaskRowView(node: child, store: store, depth: depth + 1, onEdit: onEdit)
                }
            }
        }
    }

    private func toggle() async {
        do {
            try await WorkspaceService().setCompleted(id: node.task.id, isCompleted: !node.task.isCompleted, actorId: store.myMemberId)
            await store.loadAll()
        } catch {
            store.lastError = error.localizedDescription
        }
    }
}
