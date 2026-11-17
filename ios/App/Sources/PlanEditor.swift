import SwiftUI
import WellnessCore

/// Manual workout plan creation (same `workout_plans` shape as the web app).
struct PlanEditorSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var days: Set<Int> = []
    @State private var exercises: [AppStore.PlanExercise] = [.init()]
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
                    Button { withAnimation { exercises.append(.init()) } } label: { Label("הוסף תרגיל", systemImage: "plus.circle.fill") }.disabled(exercises.count >= 100)
                } header: { Text("תרגילים") } footer: { Text("החלק תרגיל הצידה כדי להסיר אותו.") }
            }
            .wellnessList().navigationTitle("תוכנית חדשה").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ביטול") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("שמירה") { Task { if await store.savePlan(name: name, days: days, exercises: exercises) { dismiss() } } }.disabled(!canSave).accessibilityIdentifier("save-plan") }
            }
        }
    }
}
