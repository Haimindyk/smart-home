import SwiftUI

/// The owner's screen: pending join requests to approve/reject (choosing
/// read-only vs read & write), plus the current roster with the ability to
/// change someone's permission or remove them.
struct MembersApprovalView: View {
    @ObservedObject var store: AreaWorkspaceStore
    @EnvironmentObject private var appState: AppState
    @State private var busyMemberId: UUID?
    @State private var error: String?

    private var locale: AppLocale { appState.locale }
    private var isOwner: Bool { store.myMembership.role == .owner }

    var body: some View {
        List {
            if !store.pendingMembers.isEmpty {
                Section(locale == .he ? "בקשות ממתינות" : "Pending requests") {
                    ForEach(store.pendingMembers) { member in
                        pendingRow(member)
                    }
                }
            }

            Section(locale == .he ? "חברים" : "Members") {
                ForEach(store.members.filter { $0.status == .approved }) { member in
                    approvedRow(member)
                }
            }

            if let error {
                Text(error).foregroundStyle(.red).font(.footnote)
            }
        }
        .navigationTitle(locale == .he ? "חברים והרשאות" : "Members & permissions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ShareLink(item: InviteLink.shareText(areaName: store.area.name, code: store.area.inviteCode, locale: locale)) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
    }

    private func pendingRow(_ member: AreaMember) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(member.nickname).font(.body.weight(.medium))
            if isOwner {
                HStack {
                    Button {
                        Task { await approve(member, role: .viewer) }
                    } label: {
                        Label(AreaRole.viewer.label(locale), systemImage: "eye")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task { await approve(member, role: .editor) }
                    } label: {
                        Label(AreaRole.editor.label(locale), systemImage: "pencil")
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()

                    Button(role: .destructive) {
                        Task { await reject(member) }
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                }
                .disabled(busyMemberId == member.id)
            } else {
                Text(locale == .he ? "ממתין לאישור בעל/ת האזור" : "Waiting for the owner")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func approvedRow(_ member: AreaMember) -> some View {
        HStack {
            MemberAvatarView(member: member)
            VStack(alignment: .leading) {
                Text(member.nickname)
                Text(member.role.label(locale)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if isOwner && member.role != .owner {
                Menu {
                    Button(AreaRole.viewer.label(locale)) { Task { await approve(member, role: .viewer) } }
                    Button(AreaRole.editor.label(locale)) { Task { await approve(member, role: .editor) } }
                    Button(role: .destructive) {
                        Task { await remove(member) }
                    } label: {
                        Text(locale == .he ? "הסרה" : "Remove")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private func approve(_ member: AreaMember, role: AreaRole) async {
        busyMemberId = member.id
        defer { busyMemberId = nil }
        do {
            try await appState.areaService.approve(memberId: member.id, role: role)
            await store.loadAll()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func reject(_ member: AreaMember) async {
        busyMemberId = member.id
        defer { busyMemberId = nil }
        do {
            try await appState.areaService.reject(memberId: member.id)
            await store.loadAll()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func remove(_ member: AreaMember) async {
        busyMemberId = member.id
        defer { busyMemberId = nil }
        do {
            try await appState.areaService.removeOrLeave(memberId: member.id)
            await store.loadAll()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
