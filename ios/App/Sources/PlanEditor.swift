import SwiftUI
import WellnessCore

/// Manual workout plan creation (same `workout_plans` shape as the web app).
struct PlanEditorSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var days: Set<Int> = []
    @State private var exercises: [AppStore.PlanExercise] = [.init()]
    @State private var picking = false
    private let dayNames = ["א׳", "ב׳", "ג׳", "ד׳", "ה׳", "ו׳", "ש׳"]
    private var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && exercises.contains { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } && !store.busy }
    var body: some View {
        NavigationStack {
            List {
                Section("שם התוכנית") { TextField("למשל: פלג גוף עליון", text: $name).accessibilityIdentifier("plan-name") }
                Section("ימי אימון") {
                    HStack(spacing: 6) {
                        ForEach(0..<7, id: \.self) { day in
                            Button { if days.contains(day) { days.remove(day) } else { days.insert(day) } } label: {
                                Text(dayNames[day]).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                                    .foregroundStyle(days.contains(day) ? Color.wellnessOnInk : Color.wellnessInk)
                                    .background(days.contains(day) ? Color.wellnessInk : Color.wellnessChip, in: Capsule())
                            }.buttonStyle(.plain).accessibilityAddTraits(days.contains(day) ? [.isSelected] : [])
                        }
                    }.sensoryFeedback(.selection, trigger: days)
                }
                Section {
                    ForEach($exercises) { $exercise in
                        VStack(alignment: .leading, spacing: 16) {
                            TextField("שם התרגיל", text: $exercise.name).font(.headline)
                            Stepper("סטים: \(exercise.sets)", value: $exercise.sets, in: 1...30)
                            Stepper("חזרות: \(exercise.reps)", value: $exercise.reps, in: 1...500)
                            Stepper("משקל: \(exercise.weight, specifier: "%g") ק״ג", value: $exercise.weight, in: 0...1000, step: 2.5)
                            Stepper("מנוחה: \(exercise.rest) שנ׳", value: $exercise.rest, in: 0...1800, step: 15)
                        }.padding(.vertical, 10)
                        .swipeActions { if exercises.count > 1 { Button(role: .destructive) { exercises.removeAll { $0.id == exercise.id } } label: { Label("הסרה", systemImage: "trash") } } }
                    }
                    Button { picking = true } label: { Label("בחר תרגיל מהקטלוג", systemImage: "list.bullet.rectangle.fill") }.disabled(exercises.count >= 100).accessibilityIdentifier("pick-exercise")
                    Button { withAnimation { exercises.append(.init()) } } label: { Label("הוסף תרגיל חופשי", systemImage: "plus.circle.fill") }.disabled(exercises.count >= 100)
                } header: { Text("תרגילים") } footer: { Text("החלק תרגיל הצידה כדי להסיר אותו.") }
            }
            .sheet(isPresented: $picking) { CatalogPicker { picked in withAnimation { if exercises.count == 1, exercises[0].name.isEmpty { exercises = [] }; exercises.append(.init(name: picked.he, catalogId: picked.id, muscle: picked.muscleHe, equipment: picked.equipmentHe)) } } }
            .wellnessList().navigationTitle("תוכנית חדשה").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ביטול") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("שמירה") { Task { if await store.savePlan(name: name, days: days, exercises: exercises) { dismiss() } } }.disabled(!canSave).accessibilityIdentifier("save-plan") }
            }
        }
    }
}

/// Searchable list of the curated exercise catalog shared with the web app.
struct CatalogPicker: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (CatalogExercise) -> Void
    @State private var query = ""
    private var filtered: [CatalogExercise] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return ExerciseCatalog.all.filter { q.isEmpty || $0.he.contains(q) || $0.en.lowercased().contains(q) || $0.muscleHe.contains(q) }
    }
    var body: some View {
        NavigationStack {
            List {
                ForEach(ExerciseCatalog.muscleOrder, id: \.self) { muscle in
                    let items = filtered.filter { $0.muscle == muscle }
                    if !items.isEmpty {
                        Section(ExerciseCatalog.muscleLabels[muscle] ?? muscle) {
                            ForEach(items) { item in
                                Button { onPick(item); dismiss() } label: {
                                    HStack { VStack(alignment: .leading, spacing: 3) { Text(item.he).font(.headline).foregroundStyle(Color.wellnessInk); Text(item.equipmentHe).font(.caption).foregroundStyle(Color.wellnessSecondary) }; Spacer(); Image(systemName: "plus.circle").foregroundStyle(Color.wellnessSecondary) }
                                }.accessibilityElement(children: .combine).accessibilityIdentifier("catalog-\(item.id)")
                            }
                        }
                    }
                }
            }
            .wellnessList().searchable(text: $query, prompt: "חיפוש תרגיל או שריר")
            .navigationTitle("קטלוג תרגילים").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("סגור") { dismiss() } } }
            .overlay { if filtered.isEmpty { ContentUnavailableView.search(text: query) } }
        }
    }
}
