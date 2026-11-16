import SwiftUI

@main
struct WellnessApp: App {
    @StateObject private var store = AppStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            AppRoot()
                .environmentObject(store)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "he_IL"))
                .preferredColorScheme(.light)
                .tint(.black)
                .overlay {
                    // Keep meals and Health data out of the app-switcher snapshot.
                    if scenePhase != .active { Color.white.ignoresSafeArea().overlay(Image(systemName: "heart.fill").font(.largeTitle)) }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active, store.phase == .signedIn { Task { await store.refresh() } }
                }
        }
    }
}

private struct AppRoot: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        Group {
            switch store.phase {
            case .starting: ProgressView("פותחים את היום שלך…")
            case .signedOut: LoginScreen()
            case .signedIn: HomeShell()
            case .retry:
                ContentUnavailableView {
                    Label("החיבור לא הושלם", systemImage: "wifi.exclamationmark")
                } description: { Text(store.error ?? "אפשר לנסות שוב") }
                actions: { Button("נסה שוב") { Task { await store.start() } }.buttonStyle(PrimaryButton()) }
            }
        }
        .task { await store.start() }
        .alert("לא הצלחנו להשלים", isPresented: Binding(get: { store.error != nil && store.phase != .retry }, set: { if !$0 { store.error = nil } })) {
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
            Image(systemName: "heart.fill").font(.system(size: 40)).padding(28).background(Color.wellnessCanvas, in: Circle())
            VStack(spacing: 8) {
                Text("טוב שחזרת").font(.largeTitle.bold())
                Text("אותו קוד, אותם נתונים").foregroundStyle(.secondary)
            }
            SecureField("הקוד האישי שלך", text: $pin)
                .keyboardType(.numberPad).textContentType(.password)
                .multilineTextAlignment(.center).font(.title2.monospacedDigit())
                .padding(22).background(Color.wellnessCanvas, in: RoundedRectangle(cornerRadius: 20))
                .privacySensitive()
                .onChange(of: pin) { _, value in pin = String(value.filter { $0.isASCII && $0.isNumber }.prefix(4)) }
            Button { Task { let code = pin; pin = ""; await store.login(code) } } label: {
                if store.busy { ProgressView().tint(.white) } else { Text("כניסה") }
            }.buttonStyle(PrimaryButton()).disabled(pin.count != 4 || store.busy)
            Spacer(); Spacer()
        }.padding(28).frame(maxWidth: 480)
    }
}

private enum HomeTab: String, CaseIterable {
    case today = "היום", workouts = "אימונים", health = "פעילות", settings = "הגדרות"
    var icon: String { switch self { case .today: "house.fill"; case .workouts: "dumbbell.fill"; case .health: "heart.text.square.fill"; case .settings: "gearshape.fill" } }
}
private struct HomeShell: View {
    @State private var tab: HomeTab = .today
    var body: some View {
        Group {
            switch tab {
            case .today: TodayScreen()
            case .workouts: WorkoutsScreen()
            case .health: ActivityScreen()
            case .settings: SettingsScreen()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 2) {
                ForEach(HomeTab.allCases, id: \.self) { item in
                    Button { tab = item } label: {
                        VStack(spacing: 5) {
                            Image(systemName: item.icon).font(.title3)
                            Text(item.rawValue).font(.caption.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background(tab == item ? Color.black.opacity(0.07) : .clear, in: Capsule())
                    }
                    .accessibilityAddTraits(tab == item ? [.isSelected] : [])
                }
            }
            .padding(6).background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.08)))
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 5)
        }
    }
}

struct PrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity).frame(minHeight: 54)
            .foregroundStyle(.white).background(Color.black.opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.35), in: Capsule())
    }
}
extension Color { static let wellnessCanvas = Color(white: 0.97) }
extension View {
    func wellnessCard() -> some View {
        self.padding(20).background(.white, in: RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.055), radius: 14, y: 5)
    }
}
