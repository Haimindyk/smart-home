import SwiftUI

enum RootTab: String, CaseIterable {
    case home = "הבית", calendar = "לוח שנה", health = "בריאות"
    var icon: String { switch self { case .home: "house.fill"; case .calendar: "calendar"; case .health: "heart.text.square.fill" } }
}
enum HealthTab: String, CaseIterable {
    case today = "היום", workouts = "אימונים", health = "פעילות", progress = "התקדמות"
}

/// Top-level navigation: household home, calendar, health. The add button adapts to the current tab.
struct RootShell: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var home: HomeStore
    @State private var tab: RootTab = .home
    @State private var started = false
    @State private var addingMeal = false
    @State private var addingTask = false
    @State private var addingEvent = false
    @StateObject private var network = NetworkMonitor()
    @ObservedObject private var analysis = MealAnalysisCenter.shared
    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            switch tab {
            case .home: HomeScreen()
            case .calendar: CalendarScreen()
            case .health: HealthShell()
            }
        }
        .transition(.opacity)
        .sensoryFeedback(.selection, trigger: tab)
        .onChange(of: scenePhase) { _, phase in if phase == .active, started { Task { await home.refreshIfLive() }; analysis.resumeIfNeeded(store: store) } }
        // Other household members' changes show up without pulling to refresh (the web app uses realtime; this polls while the home or calendar is open).
        .task(id: tab) { guard tab != .health else { return }; while !Task.isCancelled { try? await Task.sleep(for: .seconds(25)); if !Task.isCancelled, scenePhase == .active { await home.refreshIfLive() } } }
        .onChange(of: home.openHealthRequested) { _, requested in if requested { home.openHealthRequested = false; withAnimation(.snappy) { tab = .health } } }
        .task { home.bind(store); if !started { started = true; tab = store.startsOnHealth ? .health : .home; analysis.resumeIfNeeded(store: store); await home.refresh(); await PushManager.shared.refresh(); await PushManager.shared.uploadIfPossible() } }
        .safeAreaInset(edge: .bottom, spacing: 0) { bar }
        .safeAreaInset(edge: .top, spacing: 0) { if !network.online { OfflineBanner().transition(.move(edge: .top).combined(with: .opacity)) } }
        .animation(.snappy, value: network.online)
        .onChange(of: network.online) { _, online in if online, started { Task { await home.refreshIfLive() } } }
        .fullScreenCover(isPresented: $addingMeal) { MealCameraScreen().environmentObject(store).environmentObject(home) }
        .sheet(item: Binding(get: { analysis.presentingMealID.flatMap { id in store.meals.first { $0.id == id } } }, set: { if $0 == nil { analysis.presentingMealID = nil } })) { meal in
            NavigationStack { MealDetailScreen(initial: meal) }.environmentObject(store).presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $analysis.presenting) { MealReviewSheet(center: analysis).environmentObject(store).presentationDragIndicator(.visible) }
        .overlay(alignment: .bottom) { MealAnalysisBanner(center: analysis).padding(.bottom, 104).animation(.snappy, value: analysis.phase) }
        .sheet(isPresented: $addingTask) { QuickAddSheet().environmentObject(home).presentationDetents([.medium]).presentationDragIndicator(.visible) }
        .sheet(isPresented: $addingEvent) { EventEditorSheet(event: nil).environmentObject(home).presentationDragIndicator(.visible) }
    }
    private var bar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                ForEach(RootTab.allCases, id: \.self) { item in
                    Button { withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.8)) { tab = item } } label: {
                        VStack(spacing: 5) {
                            Image(systemName: item.icon).font(.hb(.title3)).symbolEffect(.bounce, value: tab == item)
                            if !typeSize.isAccessibilitySize { Text(item.rawValue).font(.hb(.caption, .semibold)).lineLimit(1) }
                        }
                        .foregroundStyle(tab == item ? Color.wellnessInk : Color.wellnessInk.opacity(0.8))
                        .frame(maxWidth: .infinity).padding(.vertical, 11)
                        .background { if tab == item { Capsule().fill(Color.primary.opacity(0.08)).matchedGeometryEffect(id: "pill", in: pill) } }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain).accessibilityLabel(item.rawValue).accessibilityAddTraits(tab == item ? [.isSelected] : [])
                    .accessibilityIdentifier("root-\(String(describing: item))")
                }
            }
            .padding(6).background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.wellnessHairline))
            .shadow(color: .black.opacity(0.08), radius: 18, y: 6)
            Button {
                switch tab { case .home: addingTask = true; case .calendar: addingEvent = true; case .health: addingMeal = true }
            } label: {
                Image(systemName: "plus").font(.hb(.title2, .bold)).foregroundStyle(Color.wellnessOnPrimary)
                    .frame(width: 66, height: 66).background(Color.wellnessPrimary, in: Circle()).shadow(color: .black.opacity(0.18), radius: 12, y: 5)
            }.buttonStyle(PressableStyle())
                .accessibilityLabel(tab == .home ? "הוספת משימה" : tab == .calendar ? "הוספת אירוע" : "הוספת ארוחה").accessibilityIdentifier("add-meal")
        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 5)
        .background(alignment: .bottom) {
            LinearGradient(colors: [Color.wellnessCanvas.opacity(0), Color.wellnessCanvas.opacity(0.96), Color.wellnessCanvas], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
        }
    }
}

/// Shared selection for the health module's top tabs.
final class HealthNav: ObservableObject { @Published var tab: HealthTab = .today }

/// The health module: nutrition day, workouts, Apple Health activity, progress.
struct HealthShell: View {
    @StateObject private var nav = HealthNav()
    var body: some View {
        Group {
            switch nav.tab {
            case .today: TodayScreen()
            case .workouts: WorkoutsScreen()
            case .health: ActivityScreen()
            case .progress: ProgressScreen()
            }
        }
        .environmentObject(nav)
        .sensoryFeedback(.selection, trigger: nav.tab)
    }
}

/// Pill tabs shown at the top of each health root screen. Attached inside each screen's navigation stack,
/// so pushed detail screens (meal, plan) cover it instead of hiding their navigation bar behind it.
struct HealthTabBar: View {
    @EnvironmentObject private var nav: HealthNav
    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(HealthTab.allCases, id: \.self) { item in
                    Button { withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.82)) { nav.tab = item } } label: {
                        Text(item.rawValue).font(.hb(.subheadline, .semibold)).padding(.horizontal, 14).frame(minHeight: 36)
                            .foregroundStyle(nav.tab == item ? Color.wellnessInk : Color.wellnessSecondary)
                            .background { if nav.tab == item { Capsule().fill(Color.wellnessCard).overlay(Capsule().strokeBorder(Color.wellnessInk, lineWidth: 1.5)).matchedGeometryEffect(id: "seg", in: pill) } else { Capsule().strokeBorder(Color.wellnessHairline) } }
                    }.buttonStyle(.plain).accessibilityAddTraits(nav.tab == item ? [.isSelected] : [])
                        .accessibilityIdentifier("tab-\(String(describing: item))")
                }
            }.padding(.horizontal, 16).padding(.vertical, 4)
        }.frame(height: 48).background(Color.wellnessCanvas)
    }
}
