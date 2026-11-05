import SwiftUI

/// Owner/manager-only: sends a short announcement to every approved member
/// of the area (a dashboard banner + push notification, not a chat).
struct BroadcastComposeView: View {
    @ObservedObject var store: AreaWorkspaceStore
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var message = ""
    @State private var isSending = false
    @State private var error: String?

    private var locale: AppLocale { appState.locale }
    private var recipientCount: Int { store.members.filter { $0.status == .approved }.count }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(locale == .he ? "מה ההודעה?" : "What's the message?", text: $message, axis: .vertical)
                        .lineLimit(3...8)
                } footer: {
                    Text(locale == .he
                         ? "יישלח ל-\(recipientCount) חברים באזור, כהתראה ובאנר בדף הבית."
                         : "Goes to \(recipientCount) members in this area, as a push notification and a dashboard banner.")
                }
                if let error {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }
            }
            .navigationTitle(locale == .he ? "הודעת שידור" : "Broadcast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(locale == .he ? "ביטול" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(locale == .he ? "שליחה" : "Send") { Task { await send() } }
                        .disabled(message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                }
            }
        }
    }

    private func send() async {
        isSending = true
        defer { isSending = false }
        do {
            try await BroadcastService().send(
                areaId: store.area.id,
                message: message.trimmingCharacters(in: .whitespacesAndNewlines),
                actorId: store.myMemberId
            )
            await store.loadAll()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
