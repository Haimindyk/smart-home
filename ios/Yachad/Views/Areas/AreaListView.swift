import SwiftUI

struct AreaListView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("yachad.myNickname") private var myNickname: String = ""

    @State private var showCreate = false
    @State private var showJoin = false
    @State private var pendingInviteCode: String?

    private var locale: AppLocale { appState.locale }

    var body: some View {
        NavigationStack {
            Group {
                if appState.isLoadingAreas && appState.myAreas.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if appState.myAreas.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle(locale == .he ? "יחד" : "Yachad")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            showCreate = true
                        } label: {
                            Label(locale == .he ? "אזור חדש" : "New area", systemImage: "plus.circle")
                        }
                        Button {
                            showJoin = true
                        } label: {
                            Label(locale == .he ? "הצטרפות לאזור" : "Join an area", systemImage: "qrcode.viewfinder")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable { await appState.refreshAreas() }
            .sheet(isPresented: $showCreate) {
                CreateAreaView()
            }
            .sheet(isPresented: $showJoin) {
                JoinAreaView(prefilledCode: pendingInviteCode)
            }
            .onReceive(NotificationCenter.default.publisher(for: .yachadOpenInviteURL)) { note in
                guard let url = note.object as? URL, let code = InviteLink.inviteCode(from: url) else { return }
                pendingInviteCode = code
                showJoin = true
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Text("📝").font(.system(size: 56))
            Text(locale == .he ? "שלום, \(myNickname)" : "Hi, \(myNickname)")
                .font(.title3.bold())
            Text(locale == .he
                 ? "עדיין אין לך אזורים משותפים. צרו אזור חדש או הצטרפו לאזור של מישהו אחר בעזרת קישור או קוד QR."
                 : "You don't have any shared areas yet. Create one, or join someone else's with a link or QR code.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            HStack {
                Button(locale == .he ? "אזור חדש" : "New area") { showCreate = true }
                    .buttonStyle(.borderedProminent)
                Button(locale == .he ? "הצטרפות" : "Join") { showJoin = true }
                    .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            let approved = appState.myAreas.filter { $0.membership.status == .approved }
            let pending = appState.myAreas.filter { $0.membership.status == .pending }

            if !pending.isEmpty {
                Section(locale == .he ? "ממתין לאישור" : "Waiting for approval") {
                    ForEach(pending) { membership in
                        NavigationLink(value: membership) {
                            AreaRow(membership: membership, locale: locale)
                        }
                    }
                }
            }

            Section(locale == .he ? "האזורים שלי" : "My areas") {
                ForEach(approved) { membership in
                    NavigationLink(value: membership) {
                        AreaRow(membership: membership, locale: locale)
                    }
                }
            }
        }
        .navigationDestination(for: AreaMembership.self) { membership in
            if membership.membership.status == .approved {
                AreaDashboardView(area: membership.area, myMembership: membership.membership)
            } else {
                PendingApprovalView(membership: membership)
            }
        }
    }
}

private struct AreaRow: View {
    let membership: AreaMembership
    let locale: AppLocale

    var body: some View {
        HStack {
            Text(membership.area.emoji ?? "🏠").font(.title2)
            VStack(alignment: .leading) {
                Text(membership.area.name).font(.body.weight(.medium))
                Text(membership.membership.role.label(locale))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if membership.membership.status == .pending {
                Image(systemName: "clock")
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }
}
