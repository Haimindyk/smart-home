import SwiftUI
import WellnessCore

/// "My library": products remembered from scans and saved recipes (the web app's food library).
struct FoodLibraryScreen: View {
    @EnvironmentObject private var store: AppStore
    @State private var editing: HealthRow?
    @State private var confirm: (title: String, action: () -> Void)?
    private func tile(_ symbol: String, _ color: Color) -> some View {
        Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(color).frame(width: 40, height: 40)
            .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
    private func empty(_ symbol: String, _ text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 28)).foregroundStyle(Color.wellnessSecondary.opacity(0.7))
            Text(text).font(.hb(.subheadline)).foregroundStyle(Color.wellnessSecondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 18).cardRow()
    }
    var body: some View {
        List {
            Section {
                if store.personalFoods.isEmpty { empty("barcode.viewfinder", "מוצרים שתסרוק ותוסיף יישמרו כאן.") }
                ForEach(store.personalFoods) { row in
                    HStack(spacing: 14) {
                        tile("fork.knife", Color.carbsGold)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.data["name"].stringValue ?? "מוצר").font(.hb(.headline, .semibold))
                            if let kcal = row.data["per100"]["kcal"].doubleValue { Text("\(Int(kcal.rounded())) קק״ל ל־100 \(row.data["basis"].stringValue == "ml" ? "מ״ל" : "גרם")").font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(minHeight: 52).cardRow()
                    .swipeActions { Button(role: .destructive) { confirm = ("להסיר מהספרייה?", { Task { _ = await store.removePersonalFood(row) } }) } label: { Label("הסרה", systemImage: "trash") } }
                }
            } header: { Text("מזונות אישיים ומועדפים").sectionTitle().textCase(nil) }
            Section {
                if store.recipes.isEmpty { empty("book.closed", "אפשר לשמור ארוחה כמתכון מתוך עריכת הארוחה.") }
                ForEach(store.recipes) { row in
                    Button { editing = row } label: {
                        HStack(spacing: 14) {
                            tile("book.closed.fill", Color.proteinBlue)
                            Text(row.data["name"].stringValue ?? "מתכון").font(.hb(.headline, .semibold)).foregroundStyle(Color.wellnessInk).frame(maxWidth: .infinity, alignment: .leading)
                            Text("\((row.data["servings"].doubleValue ?? 1).formatted()) מנות").font(.hb(.caption, .semibold)).foregroundStyle(Color.wellnessSecondary)
                                .padding(.horizontal, 10).padding(.vertical, 5).background(Color.wellnessChip, in: Capsule())
                            Image(systemName: "chevron.left").font(.hb(.caption, .bold)).foregroundStyle(Color.wellnessSecondary)
                        }.frame(minHeight: 52).cardVisual()
                    }.buttonStyle(.plain).listRowChrome().accessibilityIdentifier("recipe-\(row.id)")
                    .swipeActions { Button(role: .destructive) { confirm = ("למחוק את המתכון?", { Task { _ = await store.removeRecipe(row) } }) } label: { Label("מחיקה", systemImage: "trash") } }
                }
            } header: { Text("המתכונים שלי").sectionTitle().textCase(nil) }
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

private extension View {
    /// A list row drawn as a rounded card, with no separators, to match the rest of the app.
    func cardRow() -> some View { cardVisual().listRowChrome() }
    func cardVisual() -> some View {
        self.padding(.horizontal, 14)
            .background(Color.wellnessCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.wellnessHairline))
    }
    func listRowChrome() -> some View {
        listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
    }
}
