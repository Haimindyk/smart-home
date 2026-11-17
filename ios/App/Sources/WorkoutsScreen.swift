import SwiftUI
import WellnessCore

struct WorkoutsScreen: View {
    @EnvironmentObject private var store: AppStore
    @State private var creating = false
    @State private var planToArchive: HealthRow?
    private var history: [HealthRow] { store.workouts.sorted { ($0.data["startedAt"].stringValue ?? "") > ($1.data["startedAt"].stringValue ?? "") } }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("האימונים שלך").font(.system(.largeTitle, design: .rounded).bold())
                    HStack {
                        Text("התוכניות שלי").sectionTitle()
                        Spacer()
                        Button { creating = true } label: { Label("תוכנית חדשה", systemImage: "plus").font(.subheadline.weight(.semibold)).padding(.horizontal, 14).frame(height: 40).background(Color.wellnessInk, in: Capsule()).foregroundStyle(Color.wellnessOnInk) }
                            .buttonStyle(PressableStyle()).accessibilityIdentifier("new-plan")
                    }
                    if store.activePlans.isEmpty {
                        ContentUnavailableView("עוד אין תוכנית", systemImage: "dumbbell", description: Text("תוכניות שתיצור בחשבון יופיעו כאן."))
                    }
                    ForEach(store.activePlans) { plan in
                        NavigationLink { PlanDetail(plan: plan) } label: {
                            HStack(spacing: 16) {
                                Image(systemName: "dumbbell.fill").font(.title2).padding(14).background(Color.wellnessChip, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(plan.data["name"].stringValue ?? "תוכנית אימון").font(.headline)
                                    Text("\(plan.data["exercises"].arrayValue.count) תרגילים").font(.subheadline).foregroundStyle(Color.wellnessSecondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "chevron.left").foregroundStyle(Color.wellnessSecondary).font(.caption)
                            }.wellnessCard()
                        }.buttonStyle(PressableStyle()).accessibilityIdentifier("plan-\(plan.id)")
                        .contextMenu { Button(role: .destructive) { planToArchive = plan } label: { Label("העבר לארכיון", systemImage: "archivebox") } }
                    }
                    Text("יומן האימונים").sectionTitle()
                    if history.isEmpty { ContentUnavailableView("עוד אין אימונים ביומן", systemImage: "calendar") }
                    ForEach(history) { workout in
                        NavigationLink { WorkoutDetail(workout: workout) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(workout.data["name"].stringValue ?? "אימון").font(.headline)
                                    Text(workout.data["date"].stringValue ?? "").font(.subheadline).foregroundStyle(Color.wellnessSecondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                if workout.data["appleHealth"] != .null { Image(systemName: "heart.fill").foregroundStyle(.pink).accessibilityLabel("Apple Health") }
                                Text(statusName(workout.data["status"].stringValue)).font(.caption).foregroundStyle(Color.wellnessSecondary)
                            }.wellnessCard()
                        }.buttonStyle(PressableStyle()).accessibilityIdentifier("workout-\(workout.id)")
                    }
                }.padding(22)
            }.wellnessScreen().toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $creating) { PlanEditorSheet().environmentObject(store) }
            .confirmationDialog("להעביר את התוכנית לארכיון?", isPresented: Binding(get: { planToArchive != nil }, set: { if !$0 { planToArchive = nil } }), titleVisibility: .visible) {
                Button("העבר לארכיון", role: .destructive) { if let plan = planToArchive { Task { _ = await store.archivePlan(plan) } }; planToArchive = nil }
            } message: { Text("האימונים שכבר נרשמו נשארים ביומן.") }
            .refreshable { await store.refresh() }
        }
    }
}

private struct PlanDetail: View {
    @EnvironmentObject private var store: AppStore
    let plan: HealthRow
    @State private var started: HealthRow?
    var body: some View {
        List {
            Section { Button { Task { started = await store.startWorkout(from: plan) } } label: { Label("התחל אימון", systemImage: "play.fill").frame(maxWidth: .infinity) }.buttonStyle(PrimaryButton()).listRowBackground(Color.clear).listRowInsets(EdgeInsets()).disabled(store.busy).accessibilityIdentifier("start-workout") }
            ForEach(Array(plan.data["exercises"].arrayValue.enumerated()), id: \.offset) { _, exercise in
                VStack(alignment: .leading, spacing: 8) {
                    Text(exercise["name"].stringValue ?? "תרגיל").font(.headline)
                    Text("\(Int(exercise["sets"].doubleValue ?? 0)) סטים · \(Int(exercise["reps"].doubleValue ?? 0)) חזרות").font(.subheadline).foregroundStyle(Color.wellnessSecondary)
                    if exercise["loadUnknown"].boolValue != true, let weight = exercise["weight"].doubleValue, weight > 0 {
                        Text("\(weight, specifier: "%g") ק״ג").font(.subheadline).foregroundStyle(Color.wellnessSecondary)
                    }
                    if let notes = exercise["notes"].stringValue, !notes.isEmpty { Text(notes).font(.footnote).foregroundStyle(Color.wellnessSecondary) }
                }.padding(.vertical, 8)
            }
        }.listStyle(.insetGrouped).wellnessList().navigationTitle(plan.data["name"].stringValue ?? "תוכנית").navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(item: $started) { ActiveWorkoutView(row: $0).environmentObject(store) }
    }
}

private struct WorkoutDetail: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    let workout: HealthRow
    var body: some View {
        List {
            Section {
                LabeledContent("תאריך", value: workout.data["date"].stringValue ?? "")
                LabeledContent("מצב", value: statusName(workout.data["status"].stringValue))
            }
            if workout.data["appleHealth"] != .null {
                Section("Apple Health") {
                    LabeledContent("מקור", value: workout.data["appleHealth"]["sourceName"].stringValue ?? "")
                    if let duration = workout.data["appleHealth"]["durationSeconds"].doubleValue { LabeledContent("משך", value: "\(Int((duration / 60).rounded())) דקות") }
                    if let energy = workout.data["appleHealth"]["energyKcal"].doubleValue { LabeledContent("קלוריות פעילות", value: "\(Int(energy.rounded())) קק״ל") }
                    if let distance = workout.data["appleHealth"]["distanceMeters"].doubleValue { LabeledContent("מרחק", value: String(format: "%.2f ק״מ", distance / 1000)) }
                }
            }
            ForEach(Array(workout.data["exercises"].arrayValue.enumerated()), id: \.offset) { _, exercise in
                Section(exercise["name"].stringValue ?? "תרגיל") {
                    ForEach(Array(exercise["performed"].arrayValue.enumerated()), id: \.offset) { index, set in
                        HStack {
                            Text("סט \(index + 1)")
                            Spacer()
                            Text("\(Int(set["reps"].doubleValue ?? 0)) חזרות · \(set["weight"].doubleValue ?? 0, specifier: "%g") ק״ג").foregroundStyle(Color.wellnessSecondary)
                            Image(systemName: set["done"].boolValue == true ? "checkmark.circle.fill" : "circle").foregroundStyle(Color.wellnessSecondary)
                        }
                    }
                }
            }
            if workout.data["appleHealth"] != .null {
                Section {
                    Button("מחיקת האימון מהחשבון", role: .destructive) { confirmDelete = true }.disabled(store.busy)
                } footer: { Text("האימון המקורי ב־Apple Health יישאר במכשיר.") }
            }
        }.wellnessList().navigationTitle(workout.data["name"].stringValue ?? "אימון").navigationBarTitleDisplayMode(.inline)
            .confirmationDialog("למחוק את האימון המיובא?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("מחיקה", role: .destructive) { Task { if await store.removeImportedWorkout(workout) { dismiss() } } }
            }
    }
}

private func statusName(_ status: String?) -> String {
    switch status { case "completed": "הושלם"; case "partial": "חלקי"; case "active": "פעיל"; case "cancelled": "בוטל"; default: "" }
}
