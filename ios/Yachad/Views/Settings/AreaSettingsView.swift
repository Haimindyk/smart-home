import SwiftUI

struct AreaSettingsView: View {
    @ObservedObject var store: AreaWorkspaceStore
    @EnvironmentObject private var appState: AppState
    @State private var showInvite = false
    @State private var showLeaveConfirm = false
    @State private var isLeaving = false

    private var locale: AppLocale { appState.locale }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        MemberAvatarView(member: store.myMembership, size: 40)
                        VStack(alignment: .leading) {
                            Text(store.myMembership.nickname).font(.body.weight(.medium))
                            Text(store.myMembership.role.label(locale))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button {
                        showInvite = true
                    } label: {
                        Label(locale == .he ? "הזמנת אנשים" : "Invite people", systemImage: "person.badge.plus")
                    }
                    NavigationLink {
                        MembersApprovalView(store: store)
                    } label: {
                        HStack {
                            Label(locale == .he ? "חברים והרשאות" : "Members & permissions", systemImage: "person.2")
                            if !store.pendingMembers.isEmpty {
                                Spacer()
                                Text("\(store.pendingMembers.count)")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 8).padding(.vertical, 2)
                                    .background(Color.orange, in: Capsule())
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    NavigationLink {
                        ActivityLogView(store: store)
                    } label: {
                        Label(locale == .he ? "פעילות אחרונה" : "Recent activity", systemImage: "clock.arrow.circlepath")
                    }
                }

                Section(locale == .he ? "שפה" : "Language") {
                    Picker("", selection: Binding(get: { locale }, set: { appState.setLocale($0) })) {
                        Text("עברית").tag(AppLocale.he)
                        Text("English").tag(AppLocale.en)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Button(role: .destructive) {
                        showLeaveConfirm = true
                    } label: {
                        Text(store.myMembership.role == .owner
                             ? (locale == .he ? "מחיקת האזור" : "Delete area")
                             : (locale == .he ? "עזיבת האזור" : "Leave area"))
                    }
                    .disabled(isLeaving)
                }
            }
            .navigationTitle(locale == .he ? "הגדרות" : "Settings")
            .sheet(isPresented: $showInvite) {
                AreaInviteShareView(area: store.area)
            }
            .confirmationDialog(
                store.myMembership.role == .owner
                    ? (locale == .he ? "למחוק את האזור לצמיתות?" : "Delete this area permanently?")
                    : (locale == .he ? "לעזוב את האזור?" : "Leave this area?"),
                isPresented: $showLeaveConfirm,
                titleVisibility: .visible
            ) {
                Button(locale == .he ? "אישור" : "Confirm", role: .destructive) {
                    Task { await leave() }
                }
            }
        }
    }

    private func leave() async {
        isLeaving = true
        defer { isLeaving = false }
        try? await appState.areaService.removeOrLeave(memberId: store.myMembership.id)
        await appState.refreshAreas()
    }
}

private struct ActivityLogView: View {
    @ObservedObject var store: AreaWorkspaceStore
    @EnvironmentObject private var appState: AppState
    private var locale: AppLocale { appState.locale }

    var body: some View {
        List(store.recentActivity) { entry in
            VStack(alignment: .leading, spacing: 2) {
                Text(summary(entry))
                Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(locale == .he ? "פעילות אחרונה" : "Recent activity")
        .overlay {
            if store.recentActivity.isEmpty {
                ContentUnavailableView(locale == .he ? "אין פעילות עדיין" : "No activity yet", systemImage: "clock")
            }
        }
    }

    private func summary(_ entry: ActivityLogEntry) -> String {
        let actor = store.member(entry.actorId)?.nickname ?? (locale == .he ? "מישהו" : "Someone")
        let what = entry.summary ?? entry.entityType
        switch (entry.action, locale) {
        case ("created", .he): return "\(actor) יצר/ה את \"\(what)\""
        case ("created", .en): return "\(actor) created \"\(what)\""
        case ("completed", .he): return "\(actor) סימן/ה כבוצע את \"\(what)\""
        case ("completed", .en): return "\(actor) completed \"\(what)\""
        case ("uncompleted", .he): return "\(actor) ביטל/ה את \"\(what)\""
        case ("uncompleted", .en): return "\(actor) un-completed \"\(what)\""
        case ("deleted", .he): return "\(actor) מחק/ה את \"\(what)\""
        case ("deleted", .en): return "\(actor) deleted \"\(what)\""
        case ("approved", .he): return "\(actor) אושר/ה להצטרף"
        case ("approved", .en): return "\(actor) was approved to join"
        default: return "\(actor) — \(entry.action) \(what)"
        }
    }
}
