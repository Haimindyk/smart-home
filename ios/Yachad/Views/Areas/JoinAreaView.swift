import SwiftUI

struct JoinAreaView: View {
    var prefilledCode: String?

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("yachad.myNickname") private var myNickname: String = ""

    @State private var codeText = ""
    @State private var nickname = ""
    @State private var preview: AreaService.AreaPreview?
    @State private var isCheckingPreview = false
    @State private var isJoining = false
    @State private var error: String?
    @State private var showScanner = false
    @State private var joined = false

    private var locale: AppLocale { appState.locale }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField(locale == .he ? "קוד או קישור הזמנה" : "Invite code or link", text: $codeText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: codeText) { _, _ in Task { await loadPreview() } }
                        Button {
                            showScanner = true
                        } label: {
                            Image(systemName: "qrcode.viewfinder")
                        }
                    }
                } header: {
                    Text(locale == .he ? "הזמנה" : "Invite")
                } footer: {
                    Text(locale == .he
                         ? "אפשר להדביק קישור, להקליד את הקוד, או לסרוק QR."
                         : "Paste a link, type the code, or scan a QR.")
                }

                if isCheckingPreview {
                    ProgressView()
                } else if let preview {
                    Section(locale == .he ? "מצטרפים אל" : "Joining") {
                        HStack {
                            Text(preview.emoji ?? "🏠").font(.title2)
                            Text(preview.name).font(.body.weight(.medium))
                        }
                    }
                }

                Section(locale == .he ? "איך לקרוא לך באזור הזה" : "How to address you in this area") {
                    TextField(locale == .he ? "שם/כינוי" : "Name/nickname", text: $nickname)
                }

                if let error {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }
            }
            .navigationTitle(locale == .he ? "הצטרפות לאזור" : "Join an area")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(locale == .he ? "ביטול" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(locale == .he ? "בקשת הצטרפות" : "Ask to join") { Task { await join() } }
                        .disabled(preview == nil || nickname.trimmingCharacters(in: .whitespaces).isEmpty || isJoining)
                }
            }
            .onAppear {
                if nickname.isEmpty { nickname = myNickname }
                if let prefilledCode { codeText = prefilledCode }
            }
            .task { if !codeText.isEmpty { await loadPreview() } }
            .sheet(isPresented: $showScanner) {
                NavigationStack {
                    QRScannerView { code in
                        if let normalized = InviteLink.normalizedCode(fromPastedText: code) {
                            codeText = normalized
                        }
                        showScanner = false
                    }
                    .ignoresSafeArea()
                    .navigationTitle(locale == .he ? "סריקת QR" : "Scan QR")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(locale == .he ? "ביטול" : "Cancel") { showScanner = false }
                        }
                    }
                }
            }
            .alert(locale == .he ? "הבקשה נשלחה" : "Request sent", isPresented: $joined) {
                Button(locale == .he ? "אישור" : "OK") { dismiss() }
            } message: {
                Text(locale == .he
                     ? "מי שיצר/ה את האזור יצטרך/תצטרך לאשר אותך."
                     : "The area's owner needs to approve you.")
            }
        }
    }

    private func loadPreview() async {
        guard let code = InviteLink.normalizedCode(fromPastedText: codeText) else {
            preview = nil
            return
        }
        isCheckingPreview = true
        error = nil
        defer { isCheckingPreview = false }
        do {
            preview = try await appState.areaService.previewArea(inviteCode: code)
            if preview == nil {
                error = locale == .he ? "לא נמצא אזור עם הקוד הזה" : "No area found with that code"
            }
        } catch {
            self.error = error.localizedDescription
            preview = nil
        }
    }

    private func join() async {
        guard let code = InviteLink.normalizedCode(fromPastedText: codeText) else { return }
        isJoining = true
        error = nil
        defer { isJoining = false }
        do {
            _ = try await appState.areaService.requestJoin(inviteCode: code, nickname: nickname.trimmingCharacters(in: .whitespaces))
            await appState.refreshAreas()
            joined = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}
