import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var home: HomeStore
    @Environment(\.dismiss) private var dismiss
    var isSheet = false
    @State private var confirmLogout = false
    @State private var showGoals = false
    @State private var weightText = ""
    /// The real version and build number from the app bundle, not a hard-coded string.
    private static var versionLabel: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Profile hero
                    HStack(spacing: 16) {
                        MemberAvatar(member: home.me, size: 72)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(home.me?.name ?? "החשבון שלי").font(.hb(.title2, .bold)).tracking(-0.4)
                            HStack(spacing: 8) {
                                chip(store.timeZone.identifier, "globe")
                                chip("גרסה \(Self.versionLabel)", "app.badge")
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.wellnessCard(padding: 18).accessibilityElement(children: .combine)

                    // Quick links
                    VStack(spacing: 0) {
                        Button { showGoals = true } label: { row("הפרופיל והיעדים שלי", "target", Color.kcalAmber, chevron: false) }
                            .buttonStyle(PressableStyle()).accessibilityIdentifier("profile-goals")
                        divider
                        NavigationLink { NotificationSettingsScreen() } label: { row("התראות", "bell.fill", Color.fatCoral) }
                            .buttonStyle(PressableStyle()).accessibilityIdentifier("notification-settings")
                        divider
                        NavigationLink { TrainingDataScreen() } label: { row("שיפור המודל", "wand.and.stars", Color.purple, detail: "שתף תיקונים כדי שהזיהוי ישתפר") }
                            .buttonStyle(PressableStyle()).accessibilityIdentifier("training-data")
                        divider
                        NavigationLink { FoodLibraryScreen() } label: { row("הספרייה שלי", "books.vertical.fill", Color.proteinBlue, detail: "מועדפים ומתכונים") }
                            .buttonStyle(PressableStyle()).accessibilityIdentifier("food-library")
                    }.wellnessCard(padding: 6)

                    // Weight
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            sectionIcon("scalemass.fill", Color.carbsGold)
                            Text("משקל").font(.hb(.headline, .semibold))
                            Spacer()
                            if let weight = store.latestWeight {
                                Text(String(format: "%.1f", weight)).font(.hb(.title2, .bold)).monospacedDigit()
                                Text("ק״ג").font(.hb(.subheadline)).foregroundStyle(Color.wellnessSecondary)
                            }
                        }
                        HStack(spacing: 10) {
                            TextField("משקל חדש בק״ג", text: $weightText).keyboardType(.decimalPad).padding(.horizontal, 14).frame(height: 46)
                                .background(Color.wellnessChip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            let canSave = (Double(weightText.replacingOccurrences(of: ",", with: ".")) ?? 0) >= 20
                            Button {
                                let value = Double(weightText.replacingOccurrences(of: ",", with: ".")) ?? 0
                                Task { if await store.logWeight(value) { weightText = "" } }
                            } label: {
                                Text("שמירה").font(.hb(.subheadline, .semibold)).foregroundStyle(Color.wellnessOnPrimary)
                                    .padding(.horizontal, 20).frame(height: 46)
                                    .background(canSave ? Color.wellnessPrimary : Color.primary.opacity(0.18), in: Capsule())
                            }.buttonStyle(PressableStyle()).disabled(!canSave).fixedSize()
                        }
                    }.wellnessCard(padding: 16)

                    // Privacy
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) { sectionIcon("lock.shield.fill", Color.proteinBlue); Text("פרטיות").font(.hb(.headline, .semibold)) }
                        Text("קוד הכניסה לא נשמר. פרטי ההתחברות מוגנים ב־Keychain של המכשיר.").font(.hb(.subheadline)).foregroundStyle(Color.wellnessSecondary)
                        Text("המידע מבריאות מיובא רק אחרי בחירת אימונים ואישור שלך.").font(.hb(.subheadline)).foregroundStyle(Color.wellnessSecondary)
                        Text("הארוחות, התוכניות והאימונים מסונכרנים עם החשבון הקיים.").font(.hb(.subheadline)).foregroundStyle(Color.wellnessSecondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).wellnessCard(padding: 16)

                    // Account actions
                    VStack(spacing: 10) {
                        Button { Task { await store.refresh() } } label: { Label("רענון נתונים", systemImage: "arrow.clockwise").frame(maxWidth: .infinity, minHeight: 48) }
                            .buttonStyle(PressableStyle()).background(Color.wellnessCard, in: Capsule()).overlay(Capsule().strokeBorder(Color.wellnessHairline))
                            .disabled(store.loading)
                        Button(role: .destructive) { confirmLogout = true } label: { Label("יציאה מהחשבון", systemImage: "rectangle.portrait.and.arrow.right").frame(maxWidth: .infinity, minHeight: 48) }
                            .buttonStyle(PressableStyle()).foregroundStyle(Color.red).background(Color.red.opacity(0.10), in: Capsule())
                    }
                    Color.clear.frame(height: 24)
                }.padding(.horizontal, 16).padding(.top, 8)
            }.scrollDismissesKeyboard(.interactively).keyboardDoneButton().background(Color.wellnessCanvas.ignoresSafeArea()).scrollClipDisabled().navigationTitle("הגדרות").navigationBarTitleDisplayMode(isSheet ? .inline : .large)
                .toolbar { if isSheet { ToolbarItem(placement: .confirmationAction) { Button("סיום") { dismiss() } } } }
                .sheet(isPresented: $showGoals) { ProfileGoalsSheet().environmentObject(store) }
                .confirmationDialog("לצאת מהחשבון?", isPresented: $confirmLogout, titleVisibility: .visible) {
                    Button("יציאה", role: .destructive) { Task { await store.logout() } }
                }
        }
    }
    private var divider: some View { Divider().padding(.leading, 62) }
    private func chip(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon).font(.hb(.caption, .semibold)).foregroundStyle(Color.wellnessSecondary).lineLimit(1)
            .padding(.horizontal, 10).padding(.vertical, 5).background(Color.wellnessChip, in: Capsule())
    }
    private func sectionIcon(_ symbol: String, _ color: Color) -> some View {
        Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(color).frame(width: 34, height: 34)
            .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
    private func row(_ title: String, _ symbol: String, _ color: Color, detail: String? = nil, chevron: Bool = true) -> some View {
        HStack(spacing: 14) {
            sectionIcon(symbol, color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.hb(.body, .semibold)).foregroundStyle(Color.wellnessInk)
                if let detail { Text(detail).font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary) }
            }
            Spacer()
            Image(systemName: "chevron.left").font(.hb(.caption, .bold)).foregroundStyle(Color.wellnessSecondary)
        }.padding(.horizontal, 12).padding(.vertical, 10).contentShape(Rectangle())
    }
}
