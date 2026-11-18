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
    var body: some View {
        NavigationStack {
            List {
                Section("שם הארוחה") { TextField("שם", text: $name) }
                Section("סוג ארוחה") {
                    Picker("סוג", selection: $kind) {
                        Text("בוקר").tag("breakfast"); Text("צהריים").tag("lunch"); Text("ערב").tag("dinner"); Text("נשנוש").tag("snack")
                    }.pickerStyle(.segmented)
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
            .wellnessList().navigationTitle("עריכת ארוחה").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ביטול") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("שמירה") { Task { if await store.updateMeal(meal, name: name, kind: kind, items: items) { dismiss() } } }.disabled(store.busy || items.isEmpty)
                }
            }
            .onAppear {
                guard !loaded else { return }; loaded = true
                name = meal.data["name"].stringValue ?? ""; kind = meal.data["kind"].stringValue ?? "snack"; items = meal.data["items"].arrayValue
            }
            .sensoryFeedback(.selection, trigger: items)
        }
    }
    private func change(_ index: Int, _ delta: Double) {
        guard items.indices.contains(index), case .object(var fields) = items[index] else { return }
        let value = min(10_000, max(1, (fields["quantity"]?.doubleValue ?? 0) + delta))
        fields["quantity"] = .number(value); items[index] = .object(fields)
    }
}
