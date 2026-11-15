import SwiftUI

/// Shown right after creating an area, and reachable again from area
/// settings — the QR code and link people scan/tap to ask to join.
struct AreaInviteShareView: View {
    let area: Area
    var isFirstTime = false

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    private var locale: AppLocale { appState.locale }
    private var inviteURL: URL { InviteLink.url(forInviteCode: area.inviteCode) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if isFirstTime {
                        Text(locale == .he ? "\(area.name) נוצר 🎉" : "\(area.name) was created 🎉")
                            .font(.title3.bold())
                        Text(locale == .he
                             ? "שתפו את הקוד או ה-QR כדי שאחרים יוכלו לבקש להצטרף. תצטרכו לאשר כל אחד ולבחור אם יש לו הרשאת קריאה בלבד או קריאה וכתיבה."
                             : "Share the code or QR so others can ask to join. You'll approve each one and choose read-only or read & write.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    QRCode.image(for: inviteURL.absoluteString)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 220, height: 220)
                        .padding(16)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(radius: 2)

                    VStack(spacing: 4) {
                        Text(locale == .he ? "קוד הצטרפות" : "Invite code")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(area.inviteCode)
                            .font(.system(.title3, design: .monospaced))
                            .textSelection(.enabled)
                    }

                    ShareLink(item: InviteLink.shareText(areaName: area.name, code: area.inviteCode, locale: locale)) {
                        Label(locale == .he ? "שיתוף" : "Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle(locale == .he ? "הזמנה" : "Invite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(locale == .he ? "סיום" : "Done") { dismiss() }
                }
            }
        }
    }
}
