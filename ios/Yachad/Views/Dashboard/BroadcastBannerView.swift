import SwiftUI

/// Shows the latest broadcast from the owner/a manager as a dismissible
/// banner at the top of the dashboard, until this device dismisses it
/// (tracked per-area in UserDefaults — there's no "read receipts" table,
/// consistent with how lightweight the rest of this app's local state is).
struct BroadcastBannerView: View {
    @ObservedObject var store: AreaWorkspaceStore
    @EnvironmentObject private var appState: AppState
    @State private var dismissedId: String?

    private var locale: AppLocale { appState.locale }
    private var latest: BroadcastMessage? { store.broadcasts.first }
    private var seenKey: String { "yachad.lastSeenBroadcast.\(store.area.id.uuidString)" }

    var body: some View {
        if let latest, latest.id.uuidString != dismissedId {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "megaphone.fill")
                    .foregroundStyle(.orange)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(senderLabel(latest))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    BidiText(latest.message)
                        .font(.subheadline)
                }
                Spacer()
                Button {
                    dismiss(latest)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
            .padding(.top, 8)
            .onAppear {
                if dismissedId == nil {
                    dismissedId = UserDefaults.standard.string(forKey: seenKey)
                }
            }
        }
    }

    private func senderLabel(_ broadcast: BroadcastMessage) -> String {
        let sender = store.member(broadcast.sentBy)?.nickname ?? (locale == .he ? "מנהל/ת הפתק" : "A manager")
        return "\(sender) · \(broadcast.createdAt.formatted(date: .omitted, time: .shortened))"
    }

    private func dismiss(_ broadcast: BroadcastMessage) {
        dismissedId = broadcast.id.uuidString
        UserDefaults.standard.set(broadcast.id.uuidString, forKey: seenKey)
    }
}
