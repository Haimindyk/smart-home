import SwiftUI
import UserNotifications
import UIKit

struct AreaSettingsView: View {
    @ObservedObject var store: AreaWorkspaceStore
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var pushService: PushService
    @State private var showInvite = false
    @State private var showLeaveConfirm = false
    @State private var isLeaving = false
    @State private var isUpdatingJoinPolicy = false
    @State private var showBroadcastCompose = false

    private var locale: AppLocale { appState.locale }
    private var isOwner: Bool { store.myMembership.role == .owner }
    private var canManage: Bool { store.myMembership.role.canManageMembers }

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
                    if canManage {
                        Button {
                            showBroadcastCompose = true
                        } label: {
                            Label(locale == .he ? "הודעת שידור לכולם" : "Broadcast to everyone", systemImage: "megaphone")
                        }
                    }
                }

                if canManage {
                    Section {
                        Picker(locale == .he ? "הצטרפות לאזור" : "Joining the area", selection: joinPolicyBinding) {
                            Text(locale == .he ? "דורש אישור" : "Requires approval").tag(AreaJoinPolicy.manual)
                            Text(locale == .he ? "אוטומטית" : "Automatic").tag(AreaJoinPolicy.auto)
                        }
                        if store.area.joinPolicy == .auto {
                            Picker(locale == .he ? "הרשאה אוטומטית" : "Automatic permission", selection: autoJoinRoleBinding) {
                                Text(AreaRole.viewer.label(locale)).tag(AreaRole.viewer)
                                Text(AreaRole.editor.label(locale)).tag(AreaRole.editor)
                            }
                        }
                    } header: {
                        Text(locale == .he ? "מדיניות הצטרפות" : "Join policy")
                    } footer: {
                        Text(store.area.joinPolicy == .auto
                             ? (locale == .he
                                ? "כל מי שמקבל את הקישור או סורק את ה-QR מצטרף מיד, בלי לחכות לאישור."
                                : "Anyone with the link or QR joins immediately, without waiting for approval.")
                             : (locale == .he
                                ? "כל בקשת הצטרפות תחכה לאישור שלך או של מנהל/ת פתק אחר/ת."
                                : "Every join request waits for you or another manager to approve it."))
                    }
                    .disabled(isUpdatingJoinPolicy)
                }

                Section {
                    notificationsRow
                } footer: {
                    Text(locale == .he
                         ? "התראות על בקשות הצטרפות, אישור, שיוך למשימה, ותזכורות יומיות למה שמגיע היום."
                         : "Notifications for join requests, approval, task assignments, and a daily reminder of what's due today.")
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
                        Text(isOwner
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
            .sheet(isPresented: $showBroadcastCompose) {
                BroadcastComposeView(store: store)
            }
            .confirmationDialog(
                isOwner
                    ? (locale == .he ? "למחוק את האזור לצמיתות? הפעולה תמחק את כל התוכן ולא ניתן לבטל אותה." : "Delete this area permanently? This removes everything in it and can't be undone.")
                    : (locale == .he ? "לעזוב את האזור?" : "Leave this area?"),
                isPresented: $showLeaveConfirm,
                titleVisibility: .visible
            ) {
                Button(locale == .he ? "אישור" : "Confirm", role: .destructive) {
                    Task { await leaveOrDelete() }
                }
            }
        }
    }

    @ViewBuilder
    private var notificationsRow: some View {
        switch pushService.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            Label(locale == .he ? "התראות פעילות" : "Notifications on", systemImage: "bell.fill")
                .foregroundStyle(.secondary)
        case .denied:
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label(locale == .he ? "התראות כבויות — פתיחת הגדרות" : "Notifications off — open Settings", systemImage: "bell.slash")
            }
        case .notDetermined:
            Button {
                Task { await pushService.requestAuthorization() }
            } label: {
                Label(locale == .he ? "הפעלת התראות" : "Enable notifications", systemImage: "bell")
            }
        @unknown default:
            EmptyView()
        }
    }

    private var joinPolicyBinding: Binding<AreaJoinPolicy> {
        Binding(
            get: { store.area.joinPolicy },
            set: { newPolicy in Task { await updateJoinPolicy(policy: newPolicy, autoJoinRole: store.area.autoJoinRole) } }
        )
    }

    private var autoJoinRoleBinding: Binding<AreaRole> {
        Binding(
            get: { store.area.autoJoinRole },
            set: { newRole in Task { await updateJoinPolicy(policy: store.area.joinPolicy, autoJoinRole: newRole) } }
        )
    }

    private func updateJoinPolicy(policy: AreaJoinPolicy, autoJoinRole: AreaRole) async {
        isUpdatingJoinPolicy = true
        defer { isUpdatingJoinPolicy = false }
        do {
            try await appState.areaService.updateJoinPolicy(areaId: store.area.id, policy: policy, autoJoinRole: autoJoinRole)
            await store.loadAll()
        } catch {
            store.lastError = error.localizedDescription
        }
    }

    private func leaveOrDelete() async {
        isLeaving = true
        defer { isLeaving = false }
        do {
            if isOwner {
                try await appState.areaService.deleteArea(areaId: store.area.id)
            } else {
                try await appState.areaService.removeOrLeave(memberId: store.myMembership.id)
            }
            await appState.refreshAreas()
        } catch {
            store.lastError = error.localizedDescription
        }
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
