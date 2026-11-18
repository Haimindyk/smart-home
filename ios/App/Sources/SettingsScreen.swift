import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var home: HomeStore
    @Environment(\.dismiss) private var dismiss
    var isSheet = false
    @State private var confirmLogout = false
    @State private var showGoals = false
    @State private var weightText = ""
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        MemberAvatar(member: home.me, size: 64)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(home.me?.name ?? "החשבון שלי").font(.hb(.title2, .bold)).tracking(-0.4)
                            Text("גרסה 0.1.0").font(.hb(.footnote)).foregroundStyle(Color.wellnessSecondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(.vertical, 8).accessibilityElement(children: .combine)
                }
                Section("החשבון שלך") {
                    LabeledContent("אזור זמן", value: store.timeZone.identifier)
                    Text("הארוחות, התוכניות והאימונים מסונכרנים עם החשבון הקיים.").foregroundStyle(Color.wellnessSecondary)
                }
                Section("משקל") {
                    if let weight = store.latestWeight { LabeledContent("משקל אחרון", value: String(format: "%.1f ק״ג", weight)) }
                    HStack {
                        TextField("ק״ג", text: $weightText).keyboardType(.decimalPad).multilineTextAlignment(.leading)
                        Button("שמירה") {
                            let value = Double(weightText.replacingOccurrences(of: ",", with: ".")) ?? 0
                            Task { if await store.logWeight(value) { weightText = "" } }
                        }.disabled((Double(weightText.replacingOccurrences(of: ",", with: ".")) ?? 0) < 20)
                    }
                }
                Section { Button { showGoals = true } label: { Label("הפרופיל והיעדים שלי", systemImage: "target") }.accessibilityIdentifier("profile-goals") }
                Section { NavigationLink { FoodLibraryScreen() } label: { Label("הספרייה שלי (מועדפים ומתכונים)", systemImage: "books.vertical") }.accessibilityIdentifier("food-library") }
                Section("פרטיות") {
                    Text("קוד הכניסה לא נשמר. פרטי ההתחברות מוגנים ב־Keychain של המכשיר.")
                    Text("המידע מבריאות מיובא רק אחרי בחירת אימונים ואישור שלך.")
                }
                Section {
                    Button("רענון נתונים") { Task { await store.refresh() } }.disabled(store.loading)
                    Button("יציאה מהחשבון", role: .destructive) { confirmLogout = true }
                }
            }.wellnessList().navigationTitle("הגדרות").navigationBarTitleDisplayMode(isSheet ? .inline : .large)
                .toolbar { if isSheet { ToolbarItem(placement: .confirmationAction) { Button("סיום") { dismiss() } } } }
                .sheet(isPresented: $showGoals) { ProfileGoalsSheet().environmentObject(store) }
                .confirmationDialog("לצאת מהחשבון?", isPresented: $confirmLogout, titleVisibility: .visible) {
                    Button("יציאה", role: .destructive) { Task { await store.logout() } }
                }
        }
    }
}
