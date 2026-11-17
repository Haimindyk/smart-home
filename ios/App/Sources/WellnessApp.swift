import SwiftUI

@main
struct WellnessApp: App {
    @StateObject private var store = AppStore()
    init() {}
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            AppRoot()
                .task { PhoneConnectivity.shared.start(store: store) }
                .environmentObject(store)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.locale, Locale(identifier: "he_IL"))
                .tint(Color.wellnessInk)
                .overlay {
                    // Keep meals and Health data out of the app-switcher snapshot.
                    if scenePhase != .active { Color.wellnessCanvas.ignoresSafeArea().overlay(Image(systemName: "heart.fill").font(.largeTitle)) }
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

private enum HomeTab: String, CaseIterable {
    case today = "היום", workouts = "אימונים", health = "פעילות", progress = "התקדמות"
    var icon: String { switch self { case .today: "house.fill"; case .workouts: "dumbbell.fill"; case .health: "heart.text.square.fill"; case .progress: "chart.xyaxis.line" } }
}
private struct HomeShell: View {
    @State private var tab: HomeTab = .today
    @Namespace private var pill
    @State private var adding = false
    @EnvironmentObject private var store: AppStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Group {
            switch tab {
            case .today: TodayScreen()
            case .workouts: WorkoutsScreen()
            case .health: ActivityScreen()
            case .progress: ProgressScreen()
            }
        }
        .transition(.opacity)
        .sensoryFeedback(.selection, trigger: tab)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 12) {
            HStack(spacing: 2) {
                ForEach(HomeTab.allCases, id: \.self) { item in
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.8)) { tab = item }
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: item.icon).font(.title3).symbolEffect(.bounce, value: tab == item)
                            if !typeSize.isAccessibilitySize { Text(item.rawValue).font(.caption.weight(.semibold)).lineLimit(1) }
                        }
                        .foregroundStyle(tab == item ? Color.wellnessInk : Color.wellnessInk.opacity(0.8))
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background {
                            if tab == item { Capsule().fill(Color.primary.opacity(0.08)).matchedGeometryEffect(id: "pill", in: pill) }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.rawValue).accessibilityAddTraits(tab == item ? [.isSelected] : [])
                    .accessibilityIdentifier("tab-\(String(describing: item))")
                }
            }
            .padding(6).background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.wellnessHairline))
            .shadow(color: .black.opacity(0.08), radius: 18, y: 6)
            Button { adding = true } label: {
                Image(systemName: "plus").font(.title2.weight(.bold)).foregroundStyle(Color.wellnessOnInk)
                    .frame(width: 66, height: 66).background(Color.wellnessInk, in: Circle()).shadow(color: .black.opacity(0.18), radius: 12, y: 5)
            }.buttonStyle(PressableStyle()).accessibilityLabel("הוספת ארוחה").accessibilityIdentifier("add-meal")
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 5)
            .background(alignment: .bottom) {
                LinearGradient(colors: [Color.wellnessCanvas.opacity(0), Color.wellnessCanvas.opacity(0.96), Color.wellnessCanvas], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            }
        }
        .sheet(isPresented: $adding) { AddMealSheet().environmentObject(store).presentationDragIndicator(.visible) }
    }
}
