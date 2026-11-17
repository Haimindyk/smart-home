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
    private var showAlert: Binding<Bool> {
        Binding(get: { store.error != nil && store.phase != .retry }, set: { if !$0 { store.error = nil } })
    }
    @ViewBuilder private var content: some View {
        switch store.phase {
        case .starting, .signingOut:
            ProgressView("פותחים את היום שלך…").frame(maxWidth: .infinity, maxHeight: .infinity).wellnessScreen()
        case .signedOut: LoginScreen()
        case .signedIn: HomeShell()
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
            Image(systemName: "heart.fill").font(.system(size: 40)).foregroundStyle(.flame).padding(30).background(.white, in: Circle()).shadow(color: .black.opacity(0.06), radius: 18, y: 8)
            VStack(spacing: 8) {
                Text("טוב שחזרת").font(.system(.largeTitle, design: .rounded).bold())
                Text("אותו קוד, אותם נתונים").foregroundStyle(.secondary)
            }
            SecureField("הקוד האישי שלך", text: $pin)
                .keyboardType(.numberPad).textContentType(.password)
                .multilineTextAlignment(.center).font(.title2.monospacedDigit())
                .padding(22).background(.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous)).shadow(color: .black.opacity(0.04), radius: 12, y: 4)
                .privacySensitive()
                .onChange(of: pin) { _, value in pin = String(value.filter { $0.isASCII && $0.isNumber }.prefix(4)) }
            Button { Task { let code = pin; pin = ""; await store.login(code) } } label: {
                if store.busy { ProgressView().tint(.white) } else { Text("כניסה") }
            }.buttonStyle(PrimaryButton()).disabled(pin.count != 4 || store.busy)
            Spacer(); Spacer()
        }.padding(28).frame(maxWidth: 480).frame(maxWidth: .infinity).wellnessScreen()
    }
}

private enum HomeTab: String, CaseIterable {
    case today = "היום", workouts = "אימונים", health = "פעילות", settings = "הגדרות"
    var icon: String { switch self { case .today: "house.fill"; case .workouts: "dumbbell.fill"; case .health: "heart.text.square.fill"; case .settings: "gearshape.fill" } }
}
private struct HomeShell: View {
    @State private var tab: HomeTab = .today
    @Namespace private var pill
    @State private var adding = false
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Group {
            switch tab {
            case .today: TodayScreen()
            case .workouts: WorkoutsScreen()
            case .health: ActivityScreen()
            case .settings: SettingsScreen()
            }
        }
        .transition(.opacity)
        .sensoryFeedback(.selection, trigger: tab)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 2) {
                ForEach(HomeTab.allCases, id: \.self) { item in
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.8)) { tab = item }
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: item.icon).font(.title3).symbolEffect(.bounce, value: tab == item)
                            Text(item.rawValue).font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(tab == item ? Color.wellnessInk : Color.wellnessInk.opacity(0.62))
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background {
                            if tab == item { Capsule().fill(Color.black.opacity(0.07)).matchedGeometryEffect(id: "pill", in: pill) }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(tab == item ? [.isSelected] : [])
                    .accessibilityIdentifier("tab-\(String(describing: item))")
                }
            }
            .padding(6).background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.06)))
            .shadow(color: .black.opacity(0.08), radius: 18, y: 6)
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 5)
        }
        .overlay(alignment: .bottomLeading) {
            Button { adding = true } label: {
                Image(systemName: "plus").font(.title2.weight(.bold)).foregroundStyle(.white)
                    .frame(width: 62, height: 62).background(Color.wellnessInk, in: Circle()).shadow(color: .black.opacity(0.2), radius: 14, y: 6)
            }.buttonStyle(PressableStyle()).padding(.leading, 20).padding(.bottom, 80)
                .accessibilityLabel("הוספת ארוחה").accessibilityIdentifier("add-meal")
        }
        .sheet(isPresented: $adding) { AddMealSheet().environmentObject(store).presentationDragIndicator(.visible) }
    }
}
