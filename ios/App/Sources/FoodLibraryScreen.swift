import SwiftUI
import WellnessCore

/// "My library": products remembered from scans and saved recipes (the web app's food library).
struct FoodLibraryScreen: View {
    @EnvironmentObject private var store: AppStore
    @State private var editing: HealthRow?
    @State private var confirm: (title: String, action: () -> Void)?
    var body: some View {
        List {
            Section("מזונות אישיים ומועדפים") {
                if store.personalFoods.isEmpty { Text("מוצרים שתסרוק ותוסיף יישמרו כאן.").font(.hb(.subheadline)).foregroundStyle(Color.wellnessSecondary) }
                ForEach(store.personalFoods) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.data["name"].stringValue ?? "מוצר").font(.hb(.headline, .semibold))
                        if let kcal = row.data["per100"]["kcal"].doubleValue { Text("\(Int(kcal.rounded())) קק״ל ל־100 \(row.data["basis"].stringValue == "ml" ? "מ״ל" : "גרם")").font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary) }
                    }.frame(minHeight: 48, alignment: .leading)
                    .swipeActions { Button(role: .destructive) { confirm = ("להסיר מהספרייה?", { Task { _ = await store.removePersonalFood(row) } }) } label: { Label("הסרה", systemImage: "trash") } }
                }
            }
            Section("המתכונים שלי") {
                if store.recipes.isEmpty { Text("אפשר לשמור ארוחה כמתכון מתוך עריכת הארוחה.").font(.hb(.subheadline)).foregroundStyle(Color.wellnessSecondary) }
                ForEach(store.recipes) { row in
                    Button { editing = row } label: {
                        HStack {
                            Text(row.data["name"].stringValue ?? "מתכון").font(.hb(.headline, .semibold)).foregroundStyle(Color.wellnessInk)
                            Spacer()
                            Text("\((row.data["servings"].doubleValue ?? 1).formatted()) מנות").font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary)
                        }.frame(minHeight: 48)
                    }.accessibilityIdentifier("recipe-\(row.id)")
                    .swipeActions { Button(role: .destructive) { confirm = ("למחוק את המתכון?", { Task { _ = await store.removeRecipe(row) } }) } label: { Label("מחיקה", systemImage: "trash") } }
                }
            }
        }
        .wellnessList().navigationTitle("הספרייה שלי").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { RecipeEditorSheet(row: $0).environmentObject(store) }
        .confirmationDialog(confirm?.title ?? "", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), titleVisibility: .visible) {
            Button("מחיקה", role: .destructive) { confirm?.action(); confirm = nil }
        } message: { Text("ארוחות שכבר נרשמו לא ישתנו.") }
    }
}

struct RecipeEditorSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let row: HealthRow
    @State private var name = ""
    @State private var servings = "1"
    @State private var grams: [String: String] = [:]
    var body: some View {
        NavigationStack {
            List {
                Section("שם המתכון") { TextField("שם", text: $name).accessibilityIdentifier("recipe-name") }
                Section("מספר מנות") { TextField("1", text: $servings).keyboardType(.decimalPad) }
                Section("מרכיבים (גרם)") {
                    ForEach(Array(row.data["items"].arrayValue.enumerated()), id: \.offset) { _, item in
                        let id = item["id"].stringValue ?? ""
                        HStack { Text(item["food"]["name"].stringValue ?? "מרכיב"); Spacer(); TextField("0", text: Binding(get: { grams[id] ?? "" }, set: { grams[id] = $0 })).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90) }
                    }
                }
            }
            .wellnessList().navigationTitle("עריכת מתכון").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ביטול") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("שמירה") { Task { if await save() { dismiss() } } }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty).accessibilityIdentifier("recipe-save") }
            }
            .onAppear {
                name = row.data["name"].stringValue ?? ""; servings = (row.data["servings"].doubleValue ?? 1).formatted()
                for item in row.data["items"].arrayValue { if let id = item["id"].stringValue { grams[id] = (item["quantity"].doubleValue ?? 0).formatted() } }
            }
        }
    }
    private func number(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".")) }
    private func save() async -> Bool {
        guard let n = number(servings), n > 0 else { return false }
        var parsed: [String: Double] = [:]
        for (id, text) in grams { guard let g = number(text), g > 0 else { return false }; parsed[id] = g }
        return await store.updateRecipe(row, name: name, servings: n, grams: parsed)
    }
}
