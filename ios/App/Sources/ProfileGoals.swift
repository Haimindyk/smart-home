import SwiftUI
import WellnessCore

/// Profile and daily targets in three steps (the web app's profile journey): goal, personal details, activity and targets.
struct ProfileGoalsSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var objective = "maintain"
    @State private var birth = Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    @State private var hasBirth = false
    @State private var height = ""
    @State private var weight = ""
    @State private var physiology: String?
    @State private var activity = "light"
    @State private var manual = false
    @State private var custom = (kcal: "2000", protein: "100", carbs: "250", fat: "65")
    @State private var effective = Date()
    @State private var message: String?
    @State private var saving = false
    private var zone: TimeZone { store.timeZone }
    private func day(_ d: Date) -> String { AppStore.dateKey(d, zone: zone) }
    private func number(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".")) }
    private var profile: GoalCalculator.Profile { .init(birthDate: hasBirth ? day(birth) : nil, height: number(height), weight: number(weight), physiology: physiology, activity: activity, objective: objective) }
    private var suggested: GoalCalculator.Goal? { try? GoalCalculator.calculate(profile, on: day(effective)) }
    private var titles: [String] { ["מה המטרה שלך?", "נכיר אותך קצת", "התכנית שמתאימה לך"] }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 6) { ForEach(0..<3, id: \.self) { Capsule().fill($0 <= step ? Color.wellnessPrimary : Color.wellnessChip).frame(height: 5) } }.accessibilityLabel("שלב \(step + 1) מתוך 3")
                    Text(titles[step]).font(.hb(.largeTitle, .bold))
                    if let message { Text(message).font(.hb(.subheadline, .semibold)).foregroundStyle(Color.fatCoralText) }
                    switch step { case 0: goalStep; case 1: detailsStep; default: targetsStep }
                    Toggle("אני רוצה לבחור יעדים בעצמי", isOn: $manual.animation()).tint(Color.wellnessPrimary).padding(16).background(Color.wellnessCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.wellnessHairline))
                        .onChange(of: manual) { _, on in if on, let g = suggested { custom = ("\(g.kcal)", "\(g.protein)", "\(g.carbs)", "\(g.fat)") } }
                    HStack(spacing: 12) {
                        if step > 0 { Button("חזרה") { message = nil; withAnimation { step -= 1 } }.buttonStyle(.bordered).tint(Color.wellnessInk).controlSize(.large) }
                        Button { Task { await advance() } } label: { Text(saving ? "שומר…" : step < 2 ? "ממשיכים" : "שמירת הפרופיל והיעדים") }.buttonStyle(PrimaryButton()).disabled(saving).accessibilityIdentifier("profile-goals-next")
                    }
                    Text("החישוב למבוגרים לפי Mifflin–St Jeor הוא נקודת התחלה שאפשר לשנות, לא הנחיה רפואית. אימונים אינם מוסיפים קלוריות ליעד.").font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary)
                    history
                }.padding(20)
            }
            .wellnessScreen().navigationTitle("הפרופיל והיעדים שלי").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("סגור") { dismiss() } } }
            .onAppear(perform: load)
        }
    }
    private func choice(_ key: String, _ title: String, subtitle: String? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) { Text(title).font(.hb(.headline, .semibold)); if let subtitle { Text(subtitle).font(.hb(.footnote)).foregroundStyle(Color.wellnessSecondary) } }.frame(maxWidth: .infinity, alignment: .leading)
                if selected { Image(systemName: "checkmark.circle.fill") }
            }.foregroundStyle(Color.wellnessInk).padding(16).frame(minHeight: 56)
                .background(selected ? Color.wellnessChip : Color.wellnessCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(selected ? Color.wellnessInk : Color.wellnessHairline, lineWidth: selected ? 2 : 1))
        }.buttonStyle(PressableStyle()).accessibilityAddTraits(selected ? [.isSelected] : []).accessibilityIdentifier("choice-\(key)")
    }
    private var goalStep: some View {
        VStack(spacing: 10) {
            choice("lose", "ירידה מתונה במשקל", subtitle: "צעדים קטנים, הרגלים שנשארים", selected: objective == "lose") { objective = "lose" }
            choice("maintain", "לשמור ולהרגיש טוב", subtitle: "איזון שמתאים לחיים שלך", selected: objective == "maintain") { objective = "maintain" }
            choice("gain", "להתחזק ולבנות", subtitle: "לתמוך באימונים ובהתקדמות", selected: objective == "gain") { objective = "gain" }
        }
    }
    private var detailsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle("הוספת תאריך לידה", isOn: $hasBirth).tint(Color.wellnessPrimary)
            if hasBirth {
                DatePicker("תאריך לידה", selection: $birth, in: ...Date(), displayedComponents: .date).environment(\.locale, Locale(identifier: "he_IL"))
                if let age = try? GoalCalculator.calendarAge(birthDate: day(birth), on: day(Date())) { Text("הגיל שלך היום: \(age)").font(.hb(.subheadline)).foregroundStyle(Color.wellnessSecondary) }
            }
            HStack(spacing: 12) {
                TextField("גובה בס״מ", text: $height).keyboardType(.decimalPad).padding(14).background(Color.wellnessCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.wellnessHairline)).accessibilityIdentifier("profile-height")
                TextField("משקל בק״ג", text: $weight).keyboardType(.decimalPad).padding(14).background(Color.wellnessCard, in: RoundedRectangle(cornerRadius: 14, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.wellnessHairline)).accessibilityIdentifier("profile-weight")
            }
            Text("נתון פיזיולוגי לחישוב").font(.hb(.subheadline, .semibold))
            HStack(spacing: 12) {
                choice("male", "זכר", selected: physiology == "male") { physiology = "male" }
                choice("female", "נקבה", selected: physiology == "female") { physiology = "female" }
            }
            Text("ללא פרופיל מלא או מתחת לגיל 18 אפשר לבחור יעדים ידניים.").font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary)
        }
    }
    private var targetsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("כמה תנועה יש ביום שלך?").font(.hb(.subheadline, .semibold))
            VStack(spacing: 8) {
                choice("sedentary", "בעיקר בישיבה", selected: activity == "sedentary") { activity = "sedentary" }
                choice("light", "קצת תנועה", selected: activity == "light") { activity = "light" }
                choice("moderate", "בתנועה קבועה", selected: activity == "moderate") { activity = "moderate" }
                choice("high", "יום פעיל מאוד", selected: activity == "high") { activity = "high" }
            }
            if manual {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    field("קלוריות", $custom.kcal); field("חלבון בגרם", $custom.protein); field("פחמימות בגרם", $custom.carbs); field("שומן בגרם", $custom.fat)
                }
            } else if let g = suggested {
                VStack(alignment: .leading, spacing: 8) {
                    Text("היעד היומי שלך").font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary)
                    Text("\(g.kcal.formatted()) קק״ל").font(.hb(.largeTitle, .heavy)).accessibilityIdentifier("suggested-kcal")
                    HStack { macro("חלבון", g.protein); macro("פחמימות", g.carbs); macro("שומן", g.fat) }
                }.frame(maxWidth: .infinity, alignment: .leading).wellnessCard()
            } else { Text("השלמת הפרופיל תפתח חישוב אוטומטי. אפשר גם לבחור יעדים ידניים.").font(.hb(.subheadline)).padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Color.wellnessChip, in: RoundedRectangle(cornerRadius: 18, style: .continuous)) }
            DatePicker("היעד בתוקף מתאריך", selection: $effective, displayedComponents: .date).environment(\.locale, Locale(identifier: "he_IL"))
        }
    }
    private func macro(_ title: String, _ value: Int) -> some View { VStack { Text("\(value) ג׳").font(.hb(.headline, .bold)); Text(title).font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary) }.frame(maxWidth: .infinity) }
    private func field(_ title: String, _ binding: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) { Text(title).font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary); TextField("0", text: binding).keyboardType(.numberPad).padding(12).background(Color.wellnessCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.wellnessHairline)) }
    }
    @ViewBuilder private var history: some View {
        if !store.goalHistory.isEmpty {
            DisclosureGroup("היסטוריית יעדים (\(store.goalHistory.count))") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(store.goalHistory) { g in Text("\(g.data["date"].stringValue ?? "") · \(Int(g.data["kcal"].doubleValue ?? 0)) קק״ל · ח \(Int(g.data["protein"].doubleValue ?? 0)) / פ \(Int(g.data["carbs"].doubleValue ?? 0)) / ש \(Int(g.data["fat"].doubleValue ?? 0))").font(.hb(.footnote)).foregroundStyle(Color.wellnessSecondary) }
                }.padding(.top, 6)
            }.font(.hb(.subheadline, .semibold)).tint(Color.wellnessInk)
        }
    }
    private func load() {
        let p = store.profile
        objective = p["objective"].stringValue ?? "maintain"; activity = p["activity"].stringValue ?? "light"; physiology = p["physiology"].stringValue
        if let h = p["height"].doubleValue { height = h.formatted() }; if let w = p["weight"].doubleValue { weight = w.formatted() }
        if let b = p["birthDate"].stringValue, let d = DateParsing.day(b, zone: zone) { birth = d; hasBirth = true }
        if let g = store.goalHistory.first, g.data["method"].stringValue == "manual" { manual = true; custom = ("\(Int(g.data["kcal"].doubleValue ?? 2000))", "\(Int(g.data["protein"].doubleValue ?? 100))", "\(Int(g.data["carbs"].doubleValue ?? 250))", "\(Int(g.data["fat"].doubleValue ?? 65))") }
    }
    private func advance() async {
        message = nil
        if step == 1, !manual, suggested == nil { message = "צריך תאריך לידה (18 ומעלה), גובה, משקל ונתון פיזיולוגי, או לבחור יעדים ידניים."; return }
        if step < 2 { withAnimation { step += 1 }; return }
        let goal: (date: String, kcal: Int, protein: Int, carbs: Int, fat: Int, method: String)
        if manual { goal = (day(effective), Int(number(custom.kcal) ?? 0), Int(number(custom.protein) ?? 0), Int(number(custom.carbs) ?? 0), Int(number(custom.fat) ?? 0), "manual") }
        else if let g = suggested { goal = (g.date, g.kcal, g.protein, g.carbs, g.fat, "calculated") }
        else { message = "השלמת הפרופיל תפתח חישוב אוטומטי. אפשר גם לבחור יעדים ידניים."; return }
        saving = true; defer { saving = false }
        if await store.saveProfileAndGoal(birthDate: hasBirth ? day(birth) : nil, height: number(height), weight: number(weight), physiology: physiology, activity: activity, objective: objective, goal: goal) { dismiss() }
        else { message = store.error ?? "לא הצלחנו לשמור." }
    }
}
