import SwiftUI

@main
struct WellnessApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var home = HomeStore()
    init() {}
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            AppRoot()
                .task { PhoneConnectivity.shared.start(store: store) }
                .environmentObject(store)
                .environmentObject(home)
                .task { home.bind(store) }
                .onChange(of: store.phase) { _, phase in if phase != .signedIn { home.reset() } }
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "he_IL"))
                .tint(Color.wellnessInk)
                .overlay {
                    // Keep meals and Health data out of the app-switcher snapshot.
                    if scenePhase != .active { Color.wellnessCanvas.ignoresSafeArea().overlay(Image(systemName: "heart.fill").font(.largeTitle)) }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active, store.phase == .signedIn { Task { await store.refresh(); await home.refresh() } }
                }
        }
    }
}

private struct AppRoot: View {
    @EnvironmentObject private var store: AppStore
    private var showAlert: Binding<Bool> {
        Binding(get: { store.error != nil && store.phase != .retry }, set: { if !$0 { store.error = nil } })
    }
    @ViewBuilder private var content: some View {
        switch store.phase {
        case .starting, .signingOut:
            ProgressView("פותחים את היום שלך…").frame(maxWidth: .infinity, maxHeight: .infinity).wellnessScreen()
        case .signedOut: LoginScreen()
        case .signedIn: RootShell()
        case .retry:
            ContentUnavailableView {
                Label("החיבור לא הושלם", systemImage: "wifi.exclamationmark")
            } description: { Text(store.error ?? "אפשר לנסות שוב") }
            actions: { Button("נסה שוב") { Task { await store.start() } }.buttonStyle(PrimaryButton()) }
        }
    }
    var body: some View {
        content
            .task { await store.start() }
            .sensoryFeedback(.success, trigger: store.phase) { old, new in old == .signedOut && new == .signedIn }
            .alert("לא הצלחנו להשלים", isPresented: showAlert) {
                Button("סגור", role: .cancel) { store.error = nil }
            } message: { Text(store.error ?? "") }
    }
}

private struct LoginScreen: View {
    @EnvironmentObject private var store: AppStore
    @State private var pin = ""
    var body: some View {
        VStack(spacing: 26) {
            Spacer()
            Image(systemName: "heart.fill").font(.largeTitle.weight(.semibold)).imageScale(.large).foregroundStyle(.flame).padding(30).background(Color.wellnessCard, in: Circle()).shadow(color: .black.opacity(0.06), radius: 18, y: 8)
            VStack(spacing: 8) {
                Text("טוב שחזרת").font(.system(.largeTitle, design: .rounded).bold())
                Text("אותו קוד, אותם נתונים").foregroundStyle(Color.wellnessSecondary)
            }
            HStack(spacing: 14) {
                ForEach(0..<4, id: \.self) { index in
                    Circle().fill(index < pin.count ? Color.wellnessInk : Color.primary.opacity(0.15)).frame(width: 14, height: 14)
                        .scaleEffect(index < pin.count ? 1.15 : 1).animation(.spring(response: 0.25, dampingFraction: 0.6), value: pin.count)
                }
            }.accessibilityHidden(true).sensoryFeedback(.selection, trigger: pin.count)
            SecureField("הקוד האישי שלך", text: $pin)
                .keyboardType(.numberPad).textContentType(.password)
                .multilineTextAlignment(.center).font(.title2.monospacedDigit())
                .padding(22).background(Color.wellnessCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous)).shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .privacySensitive()
                .onChange(of: pin) { _, value in pin = String(value.filter { $0.isASCII && $0.isNumber }.prefix(4)) }
            Button { Task { let code = pin; pin = ""; await store.login(code) } } label: {
                if store.busy { ProgressView().tint(Color.wellnessOnInk) } else { Text("כניסה") }
            }.buttonStyle(PrimaryButton()).disabled(pin.count != 4 || store.busy)
            Spacer(); Spacer()
        }.padding(28).frame(maxWidth: 480).frame(maxWidth: .infinity).wellnessScreen()
    }
}
