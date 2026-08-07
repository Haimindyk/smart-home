import SwiftUI

/// The entire "sign up" flow: pick a nickname. Nothing else — no email, no
/// password, no account. This nickname is just the default suggestion used
/// when creating or joining an area; it's stored per-device, not verified
/// by anyone.
struct NicknameOnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var nickname: String
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var locale: AppLocale { appState.locale }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("👋")
                .font(.system(size: 64))

            Text(locale == .he ? "איך קוראים לך?" : "What should we call you?")
                .font(.title2.bold())

            Text(locale == .he
                 ? "בלי הרשמה ובלי סיסמה — רק שם או כינוי כדי שאחרים יידעו מי עשה מה."
                 : "No sign-up, no password — just a name so others know who did what.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            TextField(locale == .he ? "השם או הכינוי שלך" : "Your name or nickname", text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .submitLabel(.done)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .onSubmit(save)

            Button(locale == .he ? "המשך" : "Continue", action: save)
                .buttonStyle(.borderedProminent)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)

            Spacer()
            Spacer()

            Picker("", selection: Binding(get: { locale }, set: { appState.setLocale($0) })) {
                Text("עברית").tag(AppLocale.he)
                Text("English").tag(AppLocale.en)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
        }
        .padding()
        .onAppear { focused = true }
    }

    private func save() {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        nickname = trimmed
    }
}
