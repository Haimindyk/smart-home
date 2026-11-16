import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var store: AppStore
    @State private var confirmLogout = false
    var body: some View {
        NavigationStack {
            List {
                Section("החשבון שלך") {
                    LabeledContent("אזור זמן", value: store.timeZone.identifier)
                    LabeledContent("גרסה", value: "0.1.0")
                    Text("הארוחות, התוכניות והאימונים מסונכרנים עם החשבון הקיים.").foregroundStyle(.secondary)
                }
                Section("פרטיות") {
                    Text("קוד הכניסה לא נשמר. פרטי ההתחברות מוגנים ב־Keychain של המכשיר.")
                    Text("המידע מבריאות מיובא רק אחרי בחירת אימונים ואישור שלך.")
                }
                Section {
                    Button("רענון נתונים") { Task { await store.refresh() } }.disabled(store.loading)
                    Button("יציאה מהחשבון", role: .destructive) { confirmLogout = true }
                }
            }.navigationTitle("הגדרות")
                .confirmationDialog("לצאת מהחשבון?", isPresented: $confirmLogout, titleVisibility: .visible) {
                    Button("יציאה", role: .destructive) { Task { await store.logout() } }
                }
        }
    }
}
