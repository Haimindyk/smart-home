import SwiftUI
import WellnessCore

/// Live workout: tick sets, adjust reps/weight, rest timer, autosave to the same `workout_sessions` row the web app uses.
struct ActiveWorkoutView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var row: HealthRow
    @State private var rest: Int?
    @State private var restEnd: Date?
    @State private var saving = false
    @State private var dirty = false
    @State private var confirmFinish = false
    @State private var demoItem: DemoRef?
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private var exercises: [JSONValue] { row.data["exercises"].arrayValue }
    private var doneSets: Int { exercises.flatMap { $0["performed"].arrayValue }.filter { $0["done"].boolValue == true }.count }
    private var totalSets: Int { exercises.reduce(0) { $0 + $1["performed"].arrayValue.count } }
    private var isActive: Bool { row.data["status"].stringValue == "active" }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text("\(doneSets) מתוך \(totalSets) סטים").font(.hb(.headline, .semibold)); Spacer(); if let rest { Label("\(rest) ש׳", systemImage: "timer").font(.hb(.headline, .semibold)).monospacedDigit().foregroundStyle(Color.kcalAmber).contentTransition(.numericText(value: Double(rest))) } }
                        ProgressView(value: Double(doneSets), total: Double(max(1, totalSets))).tint(Color.wellnessPrimary)
                    }.accessibilityElement(children: .combine)
                }
                ForEach(Array(exercises.enumerated()), id: \.offset) { exIndex, exercise in
                    Section {
                        ForEach(Array(exercise["performed"].arrayValue.enumerated()), id: \.offset) { setIndex, set in
                            SetRow(index: setIndex, set: set, enabled: isActive) { reps, weight, done in
                                update(exIndex, setIndex, reps: reps, weight: weight, done: done, rest: Int(exercise["rest"].doubleValue ?? 90))
                            }
                        }
                        if let notes = exercise["notes"].stringValue, !notes.isEmpty { Text(notes).font(.hb(.footnote)).foregroundStyle(Color.wellnessSecondary) }
                    } header: {
                        HStack {
                            Text(exercise["name"].stringValue ?? "תרגיל")
                            Spacer()
                            if let found = ExerciseDemos.resolve(name: exercise["name"].stringValue ?? "", catalogId: exercise["catalogId"].stringValue) {
                                Button { demoItem = DemoRef(name: exercise["name"].stringValue ?? "תרגיל", demo: found) } label: { Label("הדגמה", systemImage: "play.rectangle").font(.hb(.footnote, .semibold)).frame(minHeight: 44) }.accessibilityIdentifier("workout-demo-\(found.id)")
                            }
                        }
                    }
                }
                if isActive {
                    Section { Button { confirmFinish = true } label: { Text("סיום אימון").frame(maxWidth: .infinity) }.buttonStyle(PrimaryButton()).listRowBackground(Color.clear).listRowInsets(EdgeInsets()).disabled(saving) }
                }
            }
            .wellnessList().navigationTitle(row.data["name"].stringValue ?? "אימון").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(isActive ? "המשך אחר כך" : "סגור") { dismiss() } } }
            .confirmationDialog("לסיים את האימון?", isPresented: $confirmFinish, titleVisibility: .visible) {
                Button("סיום ושמירה") { Task { await finish() } }
            } message: { Text("\(doneSets) מתוך \(totalSets) סטים הושלמו.") }
            .onReceive(tick) { _ in
                guard let restEnd else { return }
                let left = Int(restEnd.timeIntervalSinceNow.rounded(.up))
                if left <= 0 { self.restEnd = nil; rest = nil; UINotificationFeedbackGenerator().notificationOccurred(.success) } else { rest = left }
            }
            .sensoryFeedback(.success, trigger: doneSets) { old, new in new > old }
            .sheet(item: $demoItem) { ExerciseDemoSheet(name: $0.name, demo: $0.demo) }
        }
        .interactiveDismissDisabled(saving)
    }
    private func update(_ exIndex: Int, _ setIndex: Int, reps: Double, weight: Double, done: Bool, rest seconds: Int) {
        guard case .object(var payload) = row.data, var list = payload["exercises"]?.arrayValue, list.indices.contains(exIndex),
              case .object(var exercise) = list[exIndex], var sets = exercise["performed"]?.arrayValue, sets.indices.contains(setIndex),
              case .object(var set) = sets[setIndex] else { return }
        let wasDone = set["done"]?.boolValue == true
        set["reps"] = .number(reps); set["weight"] = .number(weight); set["done"] = .bool(done)
        sets[setIndex] = .object(set); exercise["performed"] = .array(sets); list[exIndex] = .object(exercise); payload["exercises"] = .array(list)
        row = HealthRow(id: row.id, owner_user_id: row.owner_user_id, data: .object(payload), version: row.version, deleted_at: row.deleted_at)
        if done && !wasDone, seconds > 0 { restEnd = Date().addingTimeInterval(Double(seconds)); rest = seconds }
        Task { await persist() }
    }
    /// Saves are serialized: a tap while a save is in flight only marks the row dirty, and the loop saves the
    /// latest row with the freshly returned version. Parallel saves with one stale version would conflict and drop edits.
    @MainActor private func persist() async {
        if saving { dirty = true; return }
        saving = true; defer { saving = false }
        repeat {
            dirty = false
            let current = row
            guard let saved = await store.saveWorkout(current, payload: current.data) else { return }
            row = HealthRow(id: saved.id, owner_user_id: saved.owner_user_id, data: row.data, version: saved.version, deleted_at: saved.deleted_at)
        } while dirty
    }
    @MainActor private func finish() async {
        while saving { try? await Task.sleep(for: .milliseconds(50)) }
        guard case .object(var payload) = row.data else { return }
        payload["status"] = .string(doneSets == totalSets ? "completed" : "partial"); payload["endedAt"] = .string(store.finishedTimestamp())
        saving = true; defer { saving = false }
        if await store.saveWorkout(row, payload: .object(payload)) != nil { dismiss() }
    }
}

private struct SetRow: View {
    let index: Int
    let set: JSONValue
    let enabled: Bool
    let onChange: (Double, Double, Bool) -> Void
    var body: some View {
        let reps = set["reps"].doubleValue ?? 0, weight = set["weight"].doubleValue ?? 0, done = set["done"].boolValue == true
        HStack(spacing: 8) {
            Text("\(index + 1)").font(.hb(.headline, .semibold)).monospacedDigit().foregroundStyle(Color.wellnessSecondary).frame(width: 22)
            control(value: weight, unit: "ק״ג", label: "משקל", step: 2.5) { onChange(reps, max(0, $0), done) }
            control(value: reps, unit: "חזרות", label: "חזרות", step: 1) { onChange(max(0, $0), weight, done) }
            Button { onChange(reps, weight, !done) } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.hb(.title)).foregroundStyle(done ? Color.wellnessInk : Color.wellnessSecondary)
                    .symbolEffect(.bounce, value: done).frame(width: 44, height: 44)
            }.buttonStyle(.plain).disabled(!enabled).accessibilityLabel(done ? "סט \(index + 1) הושלם" : "סמן סט \(index + 1) כהושלם")
        }.padding(.vertical, 4)
    }
    /// Value on top, large minus/plus below: stays readable at any Dynamic Type size.
    private func control(value: Double, unit: String, label: String, step: Double, set: @escaping (Double) -> Void) -> some View {
        VStack(spacing: 6) {
            VStack(spacing: 0) {
                Text(value, format: .number.precision(.fractionLength(0...1))).font(.hb(.title3, .bold)).monospacedDigit().contentTransition(.numericText(value: value))
                Text(unit).font(.hb(.caption2)).foregroundStyle(Color.wellnessSecondary)
            }.accessibilityElement(children: .combine)
            HStack(spacing: 8) {
                stepButton("minus") { set(value - step) }.accessibilityLabel("הפחת \(label)")
                stepButton("plus") { set(value + step) }.accessibilityLabel("הוסף \(label)")
            }
        }.frame(maxWidth: .infinity).animation(.snappy, value: value)
    }
    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.hb(.footnote, .bold)).foregroundStyle(Color.wellnessInk).frame(width: 40, height: 36).background(Color.wellnessChip, in: Capsule())
        }.buttonStyle(.plain).disabled(!enabled)
    }
}

private struct DemoRef: Identifiable { let name: String; let demo: ExerciseDemo; var id: String { demo.id } }
