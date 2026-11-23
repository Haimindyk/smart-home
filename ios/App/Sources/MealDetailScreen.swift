import SwiftUI
import WellnessCore

/// Meal details laid out like the web app: photo header with actions, big calories, macro bars,
/// ingredient rows, a "Done" button and a "fix with AI" entry for estimated meals.
struct MealDetailScreen: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let initial: HealthRow
    @State private var editingManually = false
    @State private var correcting = false
    @State private var addingIngredient = false
    @State private var quantityIndex: Int?
    @State private var removeIndex: Int?
    @State private var copying = false
    @State private var toast: String?
    @AppStorage("mealDetailHintHidden") private var hintHidden = false
    @ScaledMetric(relativeTo: .largeTitle) private var kcalSize: CGFloat = 64

    private var meal: HealthRow { store.meals.first { $0.id == initial.id } ?? initial }
    private var items: [JSONValue] { meal.data["items"].arrayValue }
    /// An estimated meal with a photo that was changed after the first save (a correction): offer to share it so the model can learn.
    private var canShareForTraining: Bool {
        store.trainingEnabled && mealPhotoPath(meal) != nil && hasEstimate && meal.version > 1 && !store.trainingShared.contains(meal.id)
    }
    private var trainingCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "wand.and.stars").foregroundStyle(Color.purple)
            Text("תיקנת את הזיהוי. לשתף את הדוגמה כדי לשפר את המודל?").font(.hb(.footnote)).frame(maxWidth: .infinity, alignment: .leading)
            Button { Task { if await store.shareTrainingExample(meal) { show("תודה! הדוגמה נשמרה לבדיקה") } } } label: {
                Text("שתף").font(.hb(.subheadline, .semibold)).padding(.horizontal, 14).frame(minHeight: 34).background(Color.wellnessChip, in: Capsule())
            }.accessibilityIdentifier("meal-share-training")
        }.padding(.horizontal, 14).padding(.vertical, 8).background(Color.purple.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    private var hasEstimate: Bool { items.contains { ["ai", "usda"].contains($0["food"]["source"].stringValue ?? "") } }

    private func total(_ key: String) -> Double? {
        let values = items.compactMap { item in item["food"]["per100"][key].doubleValue.map { $0 * (item["quantity"].doubleValue ?? 0) / 100 } }
        return values.isEmpty ? nil : values.reduce(0, +)
    }
    private func number(_ value: Double?, _ digits: Int = 0) -> String { (value ?? 0).formatted(.number.precision(.fractionLength(0...digits))) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                content.padding(.top, -30)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(Color.wellnessCanvas.ignoresSafeArea())
        .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .bottom) { if let toast { Text(toast).font(.hb(.subheadline, .semibold)).foregroundStyle(Color.wellnessOnPrimary).padding(.horizontal, 18).padding(.vertical, 12).background(Color.wellnessPrimary, in: Capsule()).padding(.bottom, 24).transition(.move(edge: .bottom).combined(with: .opacity)) } }
        .animation(.snappy, value: toast)
        .task { await store.loadTrainingStatus() }
        .sheet(isPresented: $editingManually) { EditMealSheet(meal: meal).environmentObject(store) }
        .sheet(isPresented: $correcting) { CorrectMealSheet(mealID: initial.id).environmentObject(store).presentationDetents([.medium, .large]).presentationDragIndicator(.visible) }
        .sheet(isPresented: $addingIngredient) { AddIngredientSheet(mealID: initial.id).environmentObject(store) }
        .sheet(isPresented: $copying) { CopyMealSheet(mealID: initial.id) { show("הארוחה הועתקה") }.environmentObject(store).presentationDetents([.medium]) }
        .sheet(isPresented: Binding(get: { quantityIndex != nil }, set: { if !$0 { quantityIndex = nil } })) {
            if let index = quantityIndex { QuantitySheet(mealID: initial.id, index: index).environmentObject(store).presentationDetents([.fraction(0.66)]).presentationDragIndicator(.visible) }
        }
        .confirmationDialog("להסיר את הרכיב?", isPresented: Binding(get: { removeIndex != nil }, set: { if !$0 { removeIndex = nil } }), titleVisibility: .visible) {
            Button("הסרה", role: .destructive) { if let index = removeIndex { removeItem(index) }; removeIndex = nil }
            Button("ביטול", role: .cancel) { removeIndex = nil }
        }
    }

    // MARK: Header

    private var header: some View {
        ZStack(alignment: .top) {
            Group {
                if mealPhotoPath(meal) != nil {
                    Color.clear.frame(height: 300).overlay(PrivateMealPhoto(meal: meal, thumbnail: true)).clipped()
                } else {
                    LinearGradient(colors: [Color.kcalAmber.opacity(0.35), Color.wellnessChip], startPoint: .topLeading, endPoint: .bottomTrailing).frame(height: 250)
                        .overlay(Image(systemName: "fork.knife").font(.system(size: 54)).foregroundStyle(Color.wellnessSecondary.opacity(0.45)))
                }
            }.frame(maxWidth: .infinity)
            LinearGradient(colors: [.black.opacity(0.5), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.5)).allowsHitTesting(false)
            topBar.padding(.horizontal, 14).padding(.top, 58)
            VStack { Spacer(); HStack { kindChip; Spacer() } }.padding(.horizontal, 16).padding(.bottom, 44)
        }.frame(height: mealPhotoPath(meal) != nil ? 300 : 250)
    }
    private var kindChip: some View {
        let kind = ["breakfast": "בוקר", "lunch": "צהריים", "dinner": "ערב", "snack": "נשנוש"][meal.data["kind"].stringValue ?? ""] ?? "ארוחה"
        return Label(kind, systemImage: "clock").font(.hb(.footnote, .semibold)).foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 7)
            .background(.black.opacity(0.45), in: Capsule())
    }
    private var topBar: some View {
        HStack(spacing: 8) {
            circle("chevron.right", "חזרה", id: "meal-back") { dismiss() }
            Text("תזונה").font(.hb(.headline, .bold)).foregroundStyle(.white).shadow(color: .black.opacity(0.4), radius: 4)
            Spacer(minLength: 4)
            circle("pencil", "עריכה", id: "edit-meal") { editingManually = true }
            circle("doc.on.doc", "העתקה ליום אחר", id: "meal-copy") { copying = true }
            circle("book", "שמירה כמתכון", id: "meal-recipe") { Task { if await store.saveRecipe(name: mealName(meal), servings: 1, items: items) { show("נשמר בספרייה") } } }
            ShareLink(item: shareText) { circleLabel("square.and.arrow.up") }.accessibilityLabel("שיתוף").accessibilityIdentifier("meal-share")
            circle("trash", "מחיקת הארוחה", id: "meal-delete") { Task { await store.removeMealWithUndo(meal) }; dismiss() }
        }
    }
    private func circle(_ symbol: String, _ label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { circleLabel(symbol) }.buttonStyle(PressableStyle()).accessibilityLabel(label).accessibilityIdentifier(id)
    }
    private func circleLabel(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white).frame(width: 38, height: 38).background(.black.opacity(0.4), in: Circle())
    }
    private var shareText: String {
        let lines = items.map { "• \($0["food"]["name"].stringValue ?? "רכיב") — \(number($0["quantity"].doubleValue)) \($0["food"]["basis"].stringValue == "ml" ? "מ״ל" : "גרם")" }
        return (["\(mealName(meal)): \(number(total("kcal"))) קק״ל · חלבון \(number(total("protein"))) ג׳ · פחמימות \(number(total("carbs"))) ג׳ · שומן \(number(total("fat"))) ג׳"] + lines).joined(separator: "\n")
    }

    // MARK: Content sheet

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(number(total("kcal"))).font(.hbFixed(kcalSize, .heavy)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                Text("קלוריות").font(.hb(.title3)).foregroundStyle(Color.wellnessSecondary)
            }.accessibilityElement(children: .combine)
            HStack(alignment: .top, spacing: 14) {
                macro("חלבון", total("protein"), target: store.goal["protein"].doubleValue ?? 100, color: .proteinBlue)
                macro("פחמימה", total("carbs"), target: store.goal["carbs"].doubleValue ?? 250, color: .carbsGold)
                macro("שומן", total("fat"), target: store.goal["fat"].doubleValue ?? 70, color: .fatCoral)
                macro("סיבים", total("fiber"), target: 30, color: .purple, digits: 1)
            }
            if total("sugar") != nil || total("sodium") != nil {
                Text(["סוכר מוסף \(number(total("sugar"), 1)) ג׳", "נתרן \(number(total("sodium"))) מ״ג"].joined(separator: " · ")).font(.hb(.footnote)).foregroundStyle(Color.wellnessSecondary)
            }
            HStack {
                Text("מוצרים").font(.hb(.headline, .bold))
                Spacer()
                Button { addingIngredient = true } label: { Label("הוסף", systemImage: "plus").font(.hb(.subheadline, .semibold)).foregroundStyle(Color.wellnessInk).frame(minHeight: 36) }
                    .buttonStyle(PressableStyle()).accessibilityIdentifier("meal-add-ingredient")
            }.padding(.top, 6)
            if !hintHidden { hint }
            if canShareForTraining { trainingCard }
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    row(index, item)
                    if index < items.count - 1 { Divider() }
                }
            }
            if hasEstimate { Text("הערכים משוערים. אפשר לערוך כל מוצר.").font(.hb(.footnote)).foregroundStyle(Color.wellnessSecondary) }
            Divider()
            Button { dismiss() } label: { Text("סיום") }.buttonStyle(PrimaryButton()).accessibilityIdentifier("meal-done")
            if hasEstimate {
                Button { correcting = true } label: {
                    Label("משהו לא מדויק? תקן עם AI", systemImage: "sparkles").font(.hb(.subheadline, .semibold)).foregroundStyle(Color.wellnessSecondary).frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(PressableStyle()).accessibilityIdentifier("meal-fix-ai")
            }
        }
        .padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 130)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.wellnessCard, in: UnevenRoundedRectangle(topLeadingRadius: 32, topTrailingRadius: 32, style: .continuous))
    }

    private func macro(_ title: String, _ value: Double?, target: Double, color: Color, digits: Int = 0) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.hb(.footnote)).foregroundStyle(Color.wellnessSecondary).lineLimit(1)
            Text("\(number(value, digits)) ג׳").font(.hb(.headline, .bold)).lineLimit(1).minimumScaleFactor(0.7)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(color).frame(width: max(value ?? 0 > 0 ? 4 : 0, geo.size.width * min(1, (value ?? 0) / max(1, target))))
                }
            }.frame(height: 5)
        }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
    }

    private var hint: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle").foregroundStyle(Color.wellnessSecondary)
            Text("הקש על פריט לעריכה · החלק למחיקה · לחיצה ארוכה לאפשרויות").font(.hb(.footnote)).foregroundStyle(Color.wellnessSecondary).frame(maxWidth: .infinity, alignment: .leading)
            Button { withAnimation(.snappy) { hintHidden = true } } label: { Image(systemName: "xmark").font(.footnote.weight(.semibold)).foregroundStyle(Color.wellnessSecondary).frame(width: 32, height: 32) }.accessibilityLabel("הסתר")
        }.padding(.horizontal, 14).padding(.vertical, 6).background(Color.wellnessChip, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func row(_ index: Int, _ item: JSONValue) -> some View {
        let per = item["food"]["per100"], quantity = item["quantity"].doubleValue ?? 0
        func part(_ key: String) -> Double? { per[key].doubleValue.map { $0 * quantity / 100 } }
        let unit = item["food"]["basis"].stringValue == "ml" ? "מ״ל" : "גרם"
        return Button { quantityIndex = index } label: {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item["food"]["name"].stringValue ?? "רכיב").font(.hb(.headline, .semibold)).foregroundStyle(Color.wellnessInk).multilineTextAlignment(.leading)
                    Text("\(number(quantity)) \(unit) • \(number(part("kcal"))) קל׳").font(.hb(.subheadline)).foregroundStyle(Color.wellnessSecondary)
                    Text("חלבון: \(number(part("protein"))) ג׳  |  פחמימות: \(number(part("carbs"))) ג׳  |  שומן: \(number(part("fat"))) ג׳").font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary).fixedSize(horizontal: false, vertical: true)
                    Text("סיבים \(number(part("fiber"), 1)) ג׳ · סוכר מוסף \(number(part("sugar"), 1)) ג׳ · נתרן \(number(part("sodium"))) מ״ג").font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary).fixedSize(horizontal: false, vertical: true)
                    if let note = item["assumption"].stringValue, !note.isEmpty {
                        Label(note, systemImage: "sparkles").font(.hb(.caption)).foregroundStyle(Color.amberInk).lineLimit(4).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2).accessibilityLabel("הערכה: \(note)")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.left").font(.hb(.caption, .bold)).foregroundStyle(Color.wellnessSecondary)
            }.padding(.vertical, 14).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeToConfirmDelete { if items.count > 1 { removeIndex = index } else { show("אי אפשר להסיר את הרכיב האחרון. אפשר למחוק את הארוחה.") } }
        .contextMenu {
            Button { quantityIndex = index } label: { Label("עריכת כמות", systemImage: "pencil") }
            if items.count > 1 { Button(role: .destructive) { removeIndex = index } label: { Label("הסרה", systemImage: "trash") } }
        }
        .accessibilityIdentifier("meal-item-\(index)")
    }

    private func removeItem(_ index: Int) {
        guard items.indices.contains(index), items.count > 1 else { return }
        var next = items; next.remove(at: index)
        Task { if await store.updateMeal(meal, name: meal.data["name"].stringValue ?? "", kind: meal.data["kind"].stringValue ?? "snack", items: next) { show("הרכיב הוסר") } }
    }
    private func show(_ message: String) {
        toast = message
        Task { try? await Task.sleep(for: .seconds(2.4)); if toast == message { toast = nil } }
    }
}

// MARK: - Fix with AI

private struct CorrectMealSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let mealID: String
    @State private var text = ""
    @FocusState private var focused: Bool
    private var meal: HealthRow? { store.meals.first { $0.id == mealID } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("שפר זיהוי").font(.hb(.title3, .bold)).padding(.top, 22)
            if !store.aiEligible {
                Text("ה־AI זמין מגיל 18. השלם תאריך לידה בפרופיל כדי להפעיל.").font(.hb(.subheadline)).foregroundStyle(Color.wellnessSecondary)
                Spacer()
            } else if !store.aiConsented {
                AIConsentView()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        let items = meal?.data["items"].arrayValue ?? []
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            let per = item["food"]["per100"], q = item["quantity"].doubleValue ?? 0
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item["food"]["name"].stringValue ?? "רכיב").font(.hb(.headline, .semibold))
                                Text("\((q).formatted(.number.precision(.fractionLength(0...1)))) \(item["food"]["basis"].stringValue == "ml" ? "מ״ל" : "גרם") · \(Int(((per["kcal"].doubleValue ?? 0) * q / 100).rounded())) קל׳").font(.hb(.subheadline)).foregroundStyle(Color.wellnessSecondary)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
                            if index < items.count - 1 { Divider() }
                        }
                    }
                }
                if store.busy { HStack(spacing: 10) { ProgressView(); Text("מעדכן את הארוחה… זה יכול לקחת עד דקה").font(.hb(.footnote)).foregroundStyle(Color.wellnessSecondary) } }
                HStack(spacing: 10) {
                    TextField("מה לתקן? (למשל: ׳זה אורז ולא פסטה׳)", text: $text, axis: .vertical).lineLimit(1...4).focused($focused).submitLabel(.send)
                        .font(.hb(.subheadline)).padding(.horizontal, 16).padding(.vertical, 14).accessibilityIdentifier("correction-text")
                    Button { send() } label: {
                        Image(systemName: "arrow.up").font(.system(size: 16, weight: .bold)).foregroundStyle(.white).frame(width: 42, height: 42)
                            .background(canSend ? Color.wellnessPrimary : Color.primary.opacity(0.3), in: Circle())
                    }.disabled(!canSend).accessibilityLabel("שליחת התיקון").accessibilityIdentifier("correction-send")
                }.background(Color.wellnessChip, in: RoundedRectangle(cornerRadius: 24, style: .continuous)).padding(.bottom, 10)
            }
        }.padding(.horizontal, 20).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).background(Color.wellnessCard)
    }
    private var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.busy }
    private func send() {
        guard canSend, let meal else { return }
        Task { if await store.correctMeal(meal, text: text) { text = ""; dismiss() } }
    }
}

// MARK: - Quantity, add ingredient, copy

/// Edit one ingredient's amount: quick portions (½, 1, 1½, 2), a big stepper, and a switch between units (pieces) and grams.
private struct QuantitySheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let mealID: String
    let index: Int
    @State private var quantity: Double = 100          // always in the food's basis (g or ml)
    @State private var reference: Double = 100         // what "1" means in the quick portions
    @State private var unitGrams: Double?              // weight of one piece, when the food has one
    @State private var useUnits = false
    @State private var loaded = false
    @ScaledMetric(relativeTo: .largeTitle) private var bigNumber: CGFloat = 52
    private var meal: HealthRow? { store.meals.first { $0.id == mealID } }
    private var item: JSONValue? { meal?.data["items"].arrayValue[safe: index] }
    private var basisUnit: String { item?["food"]["basis"].stringValue == "ml" ? "מ״ל" : "גרם" }
    private var unitName: String {
        let name = item?["food"]["name"].stringValue ?? ""
        if name.contains("ביצ") { return "ביצים" }
        if name.contains("עוף") || name.contains("בשר") || name.contains("דג") || name.contains("סלמון") || name.contains("סטייק") || name.contains("חזה") { return "נתחים" }
        if name.contains("לחם") || name.contains("פיתה") { return "פרוסות" }
        return "יחידות"
    }
    private func part(_ key: String) -> Double { (item?["food"]["per100"][key].doubleValue ?? 0) * quantity / 100 }
    private func has(_ key: String) -> Bool { item?["food"]["per100"][key].doubleValue != nil }
    private var shownNumber: Double { useUnits ? quantity / max(unitGrams ?? 1, 1) : quantity }
    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text(item?["food"]["name"].stringValue ?? "רכיב").font(.hb(.title3, .bold)).multilineTextAlignment(.leading)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.wellnessSecondary).frame(width: 40, height: 40) }.accessibilityLabel("סגירה")
            }.padding(.top, 14)
            HStack(spacing: 10) {
                ForEach([0.5, 1, 1.5, 2], id: \.self) { multiple in
                    let selected = abs(quantity - multiple * reference) < 0.5
                    Button { withAnimation(.snappy) { quantity = max(1, multiple * reference) } } label: {
                        Text(label(multiple)).font(.hb(.headline, .semibold)).foregroundStyle(selected ? Color.wellnessOnPrimary : Color.wellnessInk)
                            .frame(maxWidth: .infinity, minHeight: 50).background(selected ? Color.wellnessPrimary : Color.wellnessChip, in: Capsule())
                    }.buttonStyle(PressableStyle())
                }
            }
            HStack {
                roundButton("minus", -1)
                VStack(spacing: 2) {
                    Text(shownNumber, format: .number.precision(.fractionLength(0...(useUnits ? 2 : 0)))).font(.hbFixed(bigNumber, .heavy)).monospacedDigit().contentTransition(.numericText(value: shownNumber))
                    Text(useUnits ? unitName : basisUnit).font(.hb(.subheadline)).foregroundStyle(Color.wellnessSecondary)
                }.frame(maxWidth: .infinity)
                roundButton("plus", 1)
            }
            if unitGrams != nil {
                HStack(spacing: 0) {
                    segment(unitName, on: useUnits) { withAnimation(.snappy) { useUnits = true } }
                    segment(basisUnit == "מ״ל" ? "מ״ל" : "ג׳", on: !useUnits) { withAnimation(.snappy) { useUnits = false } }
                }.padding(4).background(Color.wellnessChip, in: Capsule())
            }
            VStack(spacing: 4) {
                Text("\(Int(part("kcal").rounded())) קל׳ · \(Int(part("protein").rounded()))ח׳ · \(Int(part("carbs").rounded()))פ׳ · \(Int(part("fat").rounded()))ש׳ ≈").font(.hb(.subheadline, .semibold)).foregroundStyle(Color.wellnessSecondary)
                Text("סיבים \(fmt(part("fiber"))) ג׳ · סוכר מוסף \(fmt(part("sugar"))) ג׳ · נתרן \(Int(part("sodium").rounded())) מ״ג").font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary)
            }.multilineTextAlignment(.center).accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Button("שמור") { save() }.buttonStyle(PrimaryButton()).accessibilityIdentifier("quantity-save").padding(.bottom, 6)
        }
        .padding(.horizontal, 20)
        .sensoryFeedback(.selection, trigger: quantity)
        .onAppear { load() }
    }
    private func fmt(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) }
    private func label(_ multiple: Double) -> String { multiple == 0.5 ? "½" : multiple == 1.5 ? "1½" : String(Int(multiple)) }
    private func roundButton(_ symbol: String, _ direction: Double) -> some View {
        Button {
            withAnimation(.snappy) {
                let step = useUnits ? 0.5 * (unitGrams ?? 100) : (quantity < 50 ? 5 : 10)
                quantity = min(10_000, max(1, quantity + direction * step))
            }
        } label: { Image(systemName: symbol).font(.title3.weight(.semibold)).foregroundStyle(Color.wellnessInk).frame(width: 56, height: 56).background(Color.wellnessCard, in: Circle()).overlay(Circle().strokeBorder(Color.wellnessHairline)) }
            .buttonStyle(PressableStyle()).accessibilityLabel(direction > 0 ? "הוסף כמות" : "הפחת כמות")
    }
    private func segment(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.hb(.subheadline, .semibold)).foregroundStyle(on ? Color.wellnessInk : Color.wellnessSecondary).frame(maxWidth: .infinity, minHeight: 40)
                .background(on ? Color.wellnessCard : .clear, in: Capsule())
        }.buttonStyle(.plain)
    }
    private func load() {
        guard !loaded, let item else { return }
        loaded = true
        quantity = item["quantity"].doubleValue ?? 100
        let low = item["food"]["unitWeight"]["low"].doubleValue, high = item["food"]["unitWeight"]["high"].doubleValue
        if let low, low > 0 { unitGrams = (low + (high ?? low)) / 2; useUnits = true; reference = unitGrams ?? quantity }
        else if let serving = item["food"]["servingSize"].doubleValue, serving > 0 { reference = serving }
        else { reference = quantity }
    }
    private func save() {
        guard let meal, var items = Optional(meal.data["items"].arrayValue), items.indices.contains(index), case .object(var fields) = items[index] else { return }
        fields["quantity"] = .number((quantity * 10).rounded() / 10); items[index] = .object(fields)
        Task { if await store.updateMeal(meal, name: meal.data["name"].stringValue ?? "", kind: meal.data["kind"].stringValue ?? "snack", items: items) { dismiss() } }
    }
}

private struct AddIngredientSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let mealID: String
    @State private var query = ""
    @State private var results: [JSONValue] = []
    @State private var searching = false
    @State private var picked: JSONValue?
    @State private var quantity: Double = 100
    private var meal: HealthRow? { store.meals.first { $0.id == mealID } }
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if let food = picked {
                    Text(food["name"].stringValue ?? "מוצר").font(.hb(.title3, .bold)).padding(.top, 8)
                    HStack(spacing: 20) {
                        step("minus", -10); Text(quantity, format: .number.precision(.fractionLength(0))).font(.hbFixed(44, .heavy)).monospacedDigit().frame(minWidth: 100); step("plus", 10)
                    }
                    Text("\(Int(((food["per100"]["kcal"].doubleValue ?? 0) * quantity / 100).rounded())) קל׳").font(.hb(.subheadline)).foregroundStyle(Color.wellnessSecondary)
                    Button("הוסף לארוחה") { add(food) }.buttonStyle(PrimaryButton()).accessibilityIdentifier("ingredient-add")
                    Button("חזרה לחיפוש") { picked = nil }.font(.hb(.subheadline)).foregroundStyle(Color.wellnessSecondary)
                    Spacer()
                } else {
                    TextField("חיפוש מוצר לפי שם…", text: $query).submitLabel(.search).padding(14).background(Color.wellnessChip, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .onSubmit { Task { searching = true; results = await store.searchFoods(query: query, barcode: nil) ?? []; searching = false } }
                        .accessibilityIdentifier("ingredient-search")
                    if searching { ProgressView().padding(.top, 20) }
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.offset) { _, food in
                                Button { picked = food; quantity = food["servingSize"].doubleValue.flatMap { $0 > 0 ? $0 : nil } ?? 100 } label: {
                                    HStack {
                                        Text(food["name"].stringValue ?? "מוצר").font(.hb(.headline, .semibold)).foregroundStyle(Color.wellnessInk).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                                        Text("\(Int((food["per100"]["kcal"].doubleValue ?? 0).rounded())) קל׳ ל־100").font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary)
                                    }.padding(.vertical, 12).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                Divider()
                            }
                        }
                    }
                }
            }.padding(.horizontal, 20).wellnessScreen().navigationTitle("הוספת מוצר").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("ביטול") { dismiss() } } }
        }
    }
    private func step(_ symbol: String, _ delta: Double) -> some View {
        Button { withAnimation(.snappy) { quantity = min(10_000, max(1, quantity + delta)) } } label: {
            Image(systemName: symbol).font(.title3.weight(.bold)).frame(width: 54, height: 54).background(Color.wellnessChip, in: Circle()).foregroundStyle(Color.wellnessInk)
        }.buttonStyle(PressableStyle())
    }
    private func add(_ food: JSONValue) {
        guard let meal, meal.data["items"].arrayValue.count < 100 else { return }
        let item: JSONValue = .object(["id": .string(UUID().uuidString.lowercased()), "food": food, "quantity": .number(quantity)])
        Task { if await store.updateMeal(meal, name: meal.data["name"].stringValue ?? "", kind: meal.data["kind"].stringValue ?? "snack", items: meal.data["items"].arrayValue + [item]) { dismiss() } }
    }
}

private struct CopyMealSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let mealID: String
    let done: () -> Void
    @State private var date = Date()
    var body: some View {
        VStack(spacing: 16) {
            Text("העתקה ליום אחר").font(.hb(.title3, .bold)).padding(.top, 24)
            DatePicker("תאריך", selection: $date, displayedComponents: .date).datePickerStyle(.graphical).environment(\.locale, Locale(identifier: "he_IL")).environment(\.timeZone, store.timeZone)
            Button("העתק") { Task { if let meal = store.meals.first(where: { $0.id == mealID }), await store.copyMeal(meal, to: date) { done(); dismiss() } } }.buttonStyle(PrimaryButton())
        }.padding(.horizontal, 20)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
