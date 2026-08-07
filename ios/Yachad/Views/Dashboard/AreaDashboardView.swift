import SwiftUI

/// The main shell once inside an approved area: sections/tasks, chores,
/// calendar, search, and settings (members & permissions), all sharing one
/// live AreaWorkspaceStore.
struct AreaDashboardView: View {
    let area: Area
    let myMembership: AreaMember

    @EnvironmentObject private var appState: AppState
    @StateObject private var store: AreaWorkspaceStore

    init(area: Area, myMembership: AreaMember) {
        self.area = area
        self.myMembership = myMembership
        _store = StateObject(wrappedValue: AreaWorkspaceStore(area: area, myMembership: myMembership, device: DeviceIdentity.shared))
    }

    private var locale: AppLocale { appState.locale }

    var body: some View {
        TabView {
            SectionsHomeView(store: store)
                .tabItem { Label(locale == .he ? "בית" : "Home", systemImage: "house") }

            ChoresView(store: store)
                .tabItem { Label(locale == .he ? "מטלות" : "Chores", systemImage: "checklist") }

            CalendarView(store: store)
                .tabItem { Label(locale == .he ? "יומן" : "Calendar", systemImage: "calendar") }

            GlobalSearchView(store: store)
                .tabItem { Label(locale == .he ? "חיפוש" : "Search", systemImage: "magnifyingglass") }

            AreaSettingsView(store: store)
                .tabItem { Label(locale == .he ? "הגדרות" : "Settings", systemImage: "gearshape") }
        }
        .task { await store.start() }
        .onDisappear { store.stop() }
    }
}
