import SwiftUI

/// Shown while a joiner is waiting for the area's owner to approve them.
struct PendingApprovalView: View {
    let membership: AreaMembership

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var isLeaving = false

    private var locale: AppLocale { appState.locale }

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("⏳").font(.system(size: 56))
            Text(membership.area.name).font(.title3.bold())
            Text(locale == .he
                 ? "הבקשה שלך ממתינה לאישור מבעל/ת האזור."
                 : "Your request is waiting for the area owner's approval.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Button(role: .destructive) {
                Task { await leave() }
            } label: {
                Text(locale == .he ? "ביטול הבקשה" : "Cancel request")
            }
            .disabled(isLeaving)
        }
        .padding()
        .refreshable { await appState.refreshAreas() }
        .task {
            // Poll gently while this screen is open — approval also arrives
            // instantly via Realtime once the dashboard is reachable, but
            // there's no live subscription for a *pending* member yet.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                await appState.refreshAreas()
            }
        }
    }

    private func leave() async {
        isLeaving = true
        defer { isLeaving = false }
        try? await appState.areaService.removeOrLeave(memberId: membership.membership.id)
        await appState.refreshAreas()
        dismiss()
    }
}
