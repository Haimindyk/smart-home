import SwiftUI
import WellnessCore

/// Edit a logged meal: name, meal type, per-item quantities, remove items.
struct EditMealSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let meal: HealthRow
    @State private var name = ""
    @State private var kind = "snack"
    @State private var items: [JSONValue] = []
    @State private var loaded = false
    @State private var copyDate = Date()
    @State private var copying = false
    @State private var favorite = false
    var body: some View {
        NavigationStack {
            List {
                Section("שם הארוחה") { TextField("שם", text: $name) }
                Section("סוג ארוחה") {
                    Picker("סוג", selection: $kind) {
                        Text("בוקר").tag("breakfast"); Text("צהריים").tag("lunch"); Text("ערב").tag("dinner"); Text("נשנוש").tag("snack")
                    }.pickerStyle(.segmented)
                }
                if !extras.isEmpty {
                    Section("ערכים נוספים") {
                        ForEach(extras, id: \.0) { label, value, unit in HStack { Text(label); Spacer(); Text("\(value.formatted(.number.precision(.fractionLength(0...1)))) \(unit)").foregroundStyle(Color.wellnessSecondary).monospacedDigit() } }
                    }
                }
                Section {
                    Toggle(isOn: $favorite) { Label("ארוחה מועדפת", systemImage: "star") }.tint(Color.wellnessPrimary).accessibilityIdentifier("meal-favorite")
                    DatePicker("העתקה לתאריך", selection: $copyDate, displayedComponents: .date).environment(\.locale, Locale(identifier: "he_IL"))
                    Button { Task { copying = true; _ = await store.copyMeal(meal, to: copyDate); copying = false } } label: { Label("העתקה לתאריך שנבחר", systemImage: "doc.on.doc") }.disabled(copying).accessibilityIdentifier("meal-copy")
                }
                Section {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item["food"]["name"].stringValue ?? "רכיב").font(.hb(.headline, .semibold))
                                Text("\(Int((item["quantity"].doubleValue ?? 0).rounded())) \(item["food"]["basis"].stringValue == "ml" ? "מ״ל" : "גרם")").font(.hb(.subheadline)).foregroundStyle(Color.wellnessSecondary)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Stepper("", onIncrement: { change(index, 10) }, onDecrement: { change(index, -10) }).labelsHidden()
                        }
                        .swipeActions(edge: .trailing) {
                            if items.count > 1 { Button(role: .destructive) { withAnimation { _ = items.remove(at: index) } } label: { Label("הסרה", systemImage: "trash") } }
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: { Text("פריטים") } footer: { Text(items.count > 1 ? "החלק פריט הצידה כדי להסיר אותו." : "אי אפשר להסיר את הפריט האחרון. אפשר למחוק את הארוחה כולה מהמסך הראשי.") }
            }
            .wellnessList().navigationTitle("עריכת ארוחה")
            .safeAreaInset(edge: .bottom) { Button { Task { _ = await store.saveRecipe(name: name.isEmpty ? (items.first?["food"]["name"].stringValue ?? "מתכון") : name, servings: 1, items: items) } } label: { Label("שמירה כמתכון", systemImage: "book.closed").font(.hb(.subheadline, .semibold)).padding(.horizontal, 18).frame(minHeight: 44).background(.regularMaterial, in: Capsule()) }.padding(.bottom, 6).accessibilityIdentifier("save-recipe") }.navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ביטול") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("שמירה") { Task { if await store.updateMeal(meal, name: name, kind: kind, items: items) { if favorite != (meal.data["favorite"].boolValue == true), let updated = store.meals.first(where: { $0.id == meal.id }) { _ = await store.setFavorite(updated, favorite) }; dismiss() } } }.disabled(store.busy || items.isEmpty)
                }
            }
            .onAppear {
                guard !loaded else { return }; loaded = true
                name = meal.data["name"].stringValue ?? ""; kind = meal.data["kind"].stringValue ?? "snack"; items = meal.data["items"].arrayValue; favorite = meal.data["favorite"].boolValue == true
            }
            .sensoryFeedback(.selection, trigger: items)
        }
    }
    /// Optional nutrients (fiber, sugar, saturated fat, sodium) summed over the items that report them.
    private var extras: [(String, Double, String)] {
        [("סיבים", "fiber", "גרם", 1.0), ("סוכר", "sugar", "גרם", 1.0), ("שומן רווי", "saturatedFat", "גרם", 1.0), ("נתרן", "sodium", "מ״ג", 1.0)].compactMap { label, key, unit, _ in
            let values = items.compactMap { item -> Double? in item["food"]["per100"][key].doubleValue.map { $0 * (item["quantity"].doubleValue ?? 0) / 100 } }
            return values.isEmpty ? nil : (label, values.reduce(0, +), unit)
        }
    }
    private func change(_ index: Int, _ delta: Double) {
        guard items.indices.contains(index), case .object(var fields) = items[index] else { return }
        let value = min(10_000, max(1, (fields["quantity"]?.doubleValue ?? 0) + delta))
        fields["quantity"] = .number(value); items[index] = .object(fields)
    }
}
