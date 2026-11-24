import SwiftUI
import WellnessCore

/// AI trainer: create a program or improve a plan. Nothing is saved until the user approves the proposal.
struct TrainerSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var prefs = AppStore.TrainingPreferences()
    @State private var mode = "program"
    @State private var planId = ""
    @State private var question = ""
    @State private var busy = false
    @State private var error: String?
    @State private var proposal: JSONValue?
    @State private var requestID = ""
    private let dayNames = ["א׳", "ב׳", "ג׳", "ד׳", "ה׳", "ו׳", "ש׳"]
    private let muscles = ExerciseCatalog.muscleOrder
    private let equipment = ["bodyweight", "dumbbell", "barbell", "machine", "cable", "pullup"]
    var body: some View {
        NavigationStack {
            Group {
                if !store.aiEligible { ContentUnavailableView("המאמן זמין מגיל 18", systemImage: "person.crop.circle.badge.exclamationmark", description: Text("השלם תאריך לידה בפרופיל באפליקציה הרגילה כדי להפעיל את המאמן.")) }
                else if !store.aiConsented { AIConsentView() }
                else if let proposal { review(proposal) }
                else { form }
            }
            .wellnessScreen().navigationTitle("מאמן AI").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("סגור") { dismiss() } } }
        }
    }
    private var form: some View {
        List {
            Section { Picker("סוג בקשה", selection: $mode) { Text("תוכנית חדשה").tag("program"); Text("שיפור תוכנית").tag("adjust") }.pickerStyle(.segmented) }
            if mode == "adjust" {
                Section("איזו תוכנית לשפר?") {
                    Picker("תוכנית", selection: $planId) { Text("בחר").tag(""); ForEach(store.activePlans) { Text($0.data["name"].stringValue ?? "תוכנית").tag($0.id) } }
                    TextField("מה לשפר? (למשל: להוסיף יותר רגליים)", text: $question, axis: .vertical).lineLimit(1...4)
                }
            }
            Section("מטרה וניסיון") {
                Picker("מטרה", selection: $prefs.goal) { Text("כוח").tag("strength"); Text("בניית שריר").tag("muscle"); Text("כושר").tag("fitness") }
                Picker("ניסיון", selection: $prefs.experience) { Text("מתחיל").tag("beginner"); Text("בינוני").tag("intermediate"); Text("מתקדם").tag("advanced") }
                Stepper("משך אימון: \(prefs.minutes) דקות", value: $prefs.minutes, in: 20...120, step: 5)
            }
            Section("ימי אימון") {
                chips(0..<7, selected: { prefs.days.contains($0) }, label: { dayNames[$0] }) { day in if prefs.days.contains(day) { prefs.days.remove(day) } else if prefs.days.count < 6 { prefs.days.insert(day) } }
            }
            Section { Picker("חלוקה", selection: $prefs.split) { Text("אוטומטי").tag("auto"); Text("כל הגוף").tag("full_body"); Text("AB").tag("ab"); Text("ABC").tag("abc") } } header: { Text("מבנה") }
            Section { FlowChips(items: muscles, selected: { prefs.focus.contains($0) }, label: { ExerciseCatalog.muscleLabels[$0] ?? $0 }) { m in
                if let i = prefs.focus.firstIndex(of: m) { prefs.focus.remove(at: i) } else if prefs.focus.count < 2 { prefs.focus.append(m) } } } header: { Text("דגש (עד 2)") }
            Section { FlowChips(items: equipment, selected: { prefs.equipment.contains($0) }, label: { ExerciseCatalog.equipmentLabels[$0] ?? $0 }) { e in
                if prefs.equipment.contains(e) { prefs.equipment.remove(e) } else { prefs.equipment.insert(e) } } } header: { Text("ציוד זמין") }
            Section("הערות (לא חובה)") { TextField("פציעות, העדפות…", text: $prefs.notes, axis: .vertical).lineLimit(1...4) }
            if let error { Section { Text(error).foregroundStyle(Color.fatCoralText) } }
            Section {
                Button { Task { await generate() } } label: { if busy { HStack(spacing: 10) { ProgressView().tint(Color.wellnessOnPrimary); Text("מכין הצעה…") } } else { Label(mode == "program" ? "יצירת תוכנית" : "הצעת שיפור", systemImage: "sparkles") } }
                    .buttonStyle(PrimaryButton()).listRowBackground(Color.clear).listRowInsets(EdgeInsets()).disabled(!canSubmit).accessibilityIdentifier("trainer-generate")
            } footer: { Text("ההצעה מוצגת לבדיקה. שום דבר לא נשמר עד שתאשר.") }
        }.wellnessList()
    }
    private var canSubmit: Bool { !busy && !prefs.days.isEmpty && !prefs.equipment.isEmpty && (mode == "program" || !planId.isEmpty) }
    private func review(_ proposal: JSONValue) -> some View {
        List {
            Section { Text(proposal["message"].stringValue ?? "").font(.hb(.headline, .semibold)) }
            reasonsSection(proposal["reasons"].arrayValue.compactMap(\.stringValue))
            ForEach(Array(proposal["changes"].arrayValue.enumerated()), id: \.offset) { _, change in changeSection(change) }
            if let error { Section { Text(error).foregroundStyle(Color.fatCoralText) } }
            approvalSection
        }.wellnessList()
    }
    @ViewBuilder private func reasonsSection(_ reasons: [String]) -> some View {
        if !reasons.isEmpty { Section("למה כך?") { ForEach(reasons, id: \.self) { Label($0, systemImage: "checkmark.circle") } } }
    }
    private func changeSection(_ change: JSONValue) -> some View {
        Section(change["data"]["name"].stringValue ?? "תוכנית") {
            ForEach(Array(change["data"]["exercises"].arrayValue.enumerated()), id: \.offset) { _, e in exerciseRow(e) }
        }
    }
    private func exerciseRow(_ e: JSONValue) -> some View {
        let sets = Int(e["sets"].doubleValue ?? 0), reps = Int(e["reps"].doubleValue ?? 0), weight = e["weight"].doubleValue ?? 0
        let hold = Int(e["holdSeconds"].doubleValue ?? 0)
        let detail = "\(sets) סטים · " + (hold > 0 ? "\(hold) שניות החזקה" : "\(reps) חזרות") + (weight > 0 ? " · \(weight.formatted()) ק״ג" : "")
        return VStack(alignment: .leading, spacing: 3) {
            Text(e["name"].stringValue ?? "תרגיל").font(.hb(.headline, .semibold))
            Text(detail).font(.hb(.subheadline)).foregroundStyle(Color.wellnessSecondary)
        }.accessibilityElement(children: .combine)
    }
    private var approvalSection: some View {
        Section {
            Button { Task { await apply() } } label: { if busy { ProgressView().tint(Color.wellnessOnPrimary) } else { Text("אשר ושמור") } }
                .buttonStyle(PrimaryButton()).listRowBackground(Color.clear).listRowInsets(EdgeInsets()).disabled(busy).accessibilityIdentifier("trainer-apply")
            Button("חזרה לשינוי הבקשה") { proposal = nil }.frame(maxWidth: .infinity).disabled(busy).listRowBackground(Color.clear)
        } footer: { Text("הגרסה הקודמת של התוכנית נשמרת בהיסטוריה. זה מידע כללי ולא תחליף למאמן מוסמך.") }
    }
    @MainActor private func generate() async {
        busy = true; error = nil; defer { busy = false }
        guard await store.saveTrainingPreferences(prefs) else { return }
        requestID = UUID().uuidString.lowercased()
        var body: [String: JSONValue] = ["action": .string(mode), "requestId": .string(requestID), "preferences": prefs.json, "date": .string(store.dateKey),
            "description": .string(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "סקור/י את התוכנית לפי הביצועים והמשוב שלי." : question)]
        if mode == "adjust" { body["planId"] = .string(planId) }
        switch await store.call("wellness-ai", .object(body)) {
        case .success(let result): if result["changes"].arrayValue.isEmpty { error = "לא התקבלה הצעה. אפשר לנסות שוב." } else { proposal = result }
        case .failure(let e): error = e == .connection ? "אין חיבור לשרת." : "המאמן לא זמין כרגע. אפשר לנסות שוב מאוחר יותר."
        }
    }
    @MainActor private func apply() async {
        busy = true; error = nil; defer { busy = false }
        let id = proposal?["requestId"].stringValue ?? requestID
        switch await store.call("wellness-ai", .object(["action": .string("apply"), "requestId": .string(id)])) {
        case .success: await store.refresh(); dismiss()
        case .failure(let e): error = e == .conflict ? "התוכנית השתנתה במקום אחר. בקש הצעה חדשה." : "השמירה לא הושלמה. אפשר לנסות שוב."
        }
    }
    private func chips(_ range: Range<Int>, selected: @escaping (Int) -> Bool, label: @escaping (Int) -> String, toggle: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(range), id: \.self) { i in
                Button { toggle(i) } label: { Text(label(i)).font(.hb(.subheadline, .semibold)).frame(maxWidth: .infinity, minHeight: 44).foregroundStyle(selected(i) ? Color.wellnessOnPrimary : Color.wellnessInk).background(selected(i) ? Color.wellnessInk : Color.wellnessChip, in: Capsule()) }.buttonStyle(.plain).accessibilityAddTraits(selected(i) ? [.isSelected] : [])
            }
        }
    }
}

/// Wrapping toggle chips.
struct FlowChips: View {
    let items: [String]; let selected: (String) -> Bool; let label: (String) -> String; let toggle: (String) -> Void
    var body: some View {
        ViewThatFits(in: .horizontal) {
            row(items)
            VStack(alignment: .leading, spacing: 8) { row(Array(items.prefix(items.count / 2))); row(Array(items.dropFirst(items.count / 2))) }
        }
    }
    private func row(_ list: [String]) -> some View {
        HStack(spacing: 6) { ForEach(list, id: \.self) { item in
            Button { toggle(item) } label: { Text(label(item)).font(.hb(.footnote, .semibold)).padding(.horizontal, 10).frame(minHeight: 40).foregroundStyle(selected(item) ? Color.wellnessOnPrimary : Color.wellnessInk).background(selected(item) ? Color.wellnessInk : Color.wellnessChip, in: Capsule()) }.buttonStyle(.plain).accessibilityAddTraits(selected(item) ? [.isSelected] : [])
        } }
    }
}
