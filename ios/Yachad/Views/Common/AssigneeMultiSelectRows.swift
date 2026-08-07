import SwiftUI

/// Toggleable list of approved members for a multi-assignee picker — drop
/// straight into a `Form` `Section`. Used by both the task and chore
/// editors (a task/chore can have any number of assignees, or none).
struct AssigneeMultiSelectRows: View {
    @ObservedObject var store: AreaWorkspaceStore
    @Binding var selected: [UUID]

    var body: some View {
        ForEach(store.members.filter { $0.status == .approved }) { member in
            Button {
                toggle(member.id)
            } label: {
                HStack {
                    MemberAvatarView(member: member, size: 24)
                    Text(member.nickname).foregroundStyle(.primary)
                    Spacer()
                    if selected.contains(member.id) {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func toggle(_ id: UUID) {
        if let index = selected.firstIndex(of: id) {
            selected.remove(at: index)
        } else {
            selected.append(id)
        }
    }
}
