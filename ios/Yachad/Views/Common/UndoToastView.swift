import SwiftUI

/// Bottom banner shown for a few seconds after any delete, across every
/// tab (mounted once in `AreaDashboardView`, driven by the shared store).
struct UndoToastView: View {
    @ObservedObject var store: AreaWorkspaceStore
    @EnvironmentObject private var appState: AppState

    private var locale: AppLocale { appState.locale }

    var body: some View {
        if let undo = store.pendingUndo {
            HStack {
                Text(undo.message)
                    .font(.subheadline)
                Spacer()
                Button(locale == .he ? "בטל" : "Undo") {
                    Task { await store.performUndo() }
                }
                .fontWeight(.semibold)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(radius: 3)
            .padding(.horizontal)
            .padding(.vertical, 6)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: undo.id)
        }
    }
}
