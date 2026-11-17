import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var store: AppStore
    @State private var confirmLogout = false
    @State private var weightText = ""
    var body: some View {
        NavigationStack {
            List {
                Section("החשבון שלך") {
                    LabeledContent("אזור זמן", value: store.timeZone.identifier)
                    LabeledContent("גרסה", value: "0.1.0")
                    Text("הארוחות, התוכניות והאימונים מסונכרנים עם החשבון הקיים.").foregroundStyle(.secondary)
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
                Section("פרטיות") {
                    Text("קוד הכניסה לא נשמר. פרטי ההתחברות מוגנים ב־Keychain של המכשיר.")
                    Text("המידע מבריאות מיובא רק אחרי בחירת אימונים ואישור שלך.")
                }
                Section {
                    Button("רענון נתונים") { Task { await store.refresh() } }.disabled(store.loading)
                    Button("יציאה מהחשבון", role: .destructive) { confirmLogout = true }
                }
            }.wellnessList().navigationTitle("הגדרות")
                .confirmationDialog("לצאת מהחשבון?", isPresented: $confirmLogout, titleVisibility: .visible) {
                    Button("יציאה", role: .destructive) { Task { await store.logout() } }
                }
        }
    }
}
