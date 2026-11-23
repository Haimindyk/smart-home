import SwiftUI
import AVFoundation
import WellnessCore

private struct FoodChoice: Identifiable { let id = UUID(); let food: JSONValue }

/// Search (name or barcode) -> pick a product -> choose a portion -> saved as a meal.
struct AddMealSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [FoodChoice] = []
    @State private var searching = false
    @State private var searched = false
    @State private var scanning = false
    @State private var picked: FoodChoice?
    @State private var manualEntry = false
    @State private var aiMeal = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    Button { aiMeal = true } label: { Image(systemName: "sparkles").font(.hb(.title2)).foregroundStyle(Color.wellnessOnPrimary).frame(width: 52, height: 52).background(Color.wellnessPrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous)) }
                        .buttonStyle(PressableStyle()).accessibilityLabel("ארוחה מתמונה עם AI").accessibilityIdentifier("ai-meal")
                    Button { scanning = true } label: { Image(systemName: "barcode.viewfinder").font(.hb(.title2)).foregroundStyle(Color.wellnessOnPrimary).frame(width: 52, height: 52).background(Color.wellnessPrimary, in: RoundedRectangle(cornerRadius: 16, style: .continuous)) }
                        .buttonStyle(PressableStyle()).accessibilityLabel("סריקת ברקוד")
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(Color.wellnessSecondary)
                        TextField("חיפוש מוצר לפי שם…", text: $query).submitLabel(.search)
                        if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.wellnessSecondary) } }
                    }.padding(.horizontal, 14).frame(height: 52)
                        .background(Color.wellnessCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.wellnessHairline))
                }
                Button { manualEntry = true } label: { Label("הוספה ידנית", systemImage: "square.and.pencil").font(.hb(.subheadline, .semibold)).foregroundStyle(Color.wellnessInk).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain).accessibilityIdentifier("manual-food")
                if searching { ProgressView().padding(.top, 30) }
                else if results.isEmpty && !searched && query.isEmpty && (!store.recentMeals.isEmpty || !store.recipes.isEmpty || !store.personalFoods.isEmpty) {
                    ScrollView { LazyVStack(alignment: .leading, spacing: 10) {
                        if !store.recipes.isEmpty {
                            Text("המתכונים שלי").sectionTitle()
                            ForEach(store.recipes) { recipe in
                                Button { Task { if await store.logRecipe(recipe, kind: currentKind()) { dismiss() } } } label: {
                                    HStack { Image(systemName: "book.closed").foregroundStyle(Color.wellnessSecondary); Text(recipe.data["name"].stringValue ?? "מתכון").font(.hb(.headline, .semibold)).foregroundStyle(Color.wellnessInk); Spacer(); Text("מנה אחת").font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary) }
                                        .padding(14).background(Color.wellnessCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.wellnessHairline))
                                }.buttonStyle(PressableStyle())
                            }
                        }
                        if !store.favoriteMeals.isEmpty {
                            Text("ארוחות מועדפות").sectionTitle()
                            ForEach(store.favoriteMeals.prefix(8)) { meal in Button { Task { if await store.relogMeal(meal, kind: currentKind()) { dismiss() } } } label: { RecentRow(meal: meal) }.buttonStyle(PressableStyle()) }
                        }
                        if !store.personalFoods.isEmpty {
                            Text("המועדפים שלי").sectionTitle()
                            ForEach(store.personalFoods.prefix(12)) { row in Button { picked = FoodChoice(food: row.data) } label: { FoodRow(food: row.data) }.buttonStyle(PressableStyle()) }
                        }
                        if !store.recentMeals.isEmpty { Text("אחרונים").sectionTitle() }
                        ForEach(store.recentMeals) { meal in
                            Button { Task { if await store.relogMeal(meal, kind: currentKind()) { dismiss() } } } label: { RecentRow(meal: meal) }.buttonStyle(PressableStyle())
                        }
                    } }.scrollClipDisabled().sensoryFeedback(.success, trigger: store.meals.count)
                }
                else if results.isEmpty {
                    ContentUnavailableView(searched ? "לא נמצאו מוצרים" : "מה אכלת?", systemImage: searched ? "questionmark.circle" : "fork.knife",
                        description: Text(searched ? "נסה שם אחר או סרוק ברקוד." : "חפש מוצר או סרוק ברקוד כדי להוסיף ארוחה."))
                } else {
                    ScrollView { LazyVStack(spacing: 10) {
                        ForEach(results) { choice in
                            Button { picked = choice } label: { FoodRow(food: choice.food) }.buttonStyle(PressableStyle())
                        }
                    } }.scrollClipDisabled()
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20).padding(.top, 8).wellnessScreen()
            .navigationTitle("הוספת ארוחה").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("סגור") { dismiss() } } }
            .task(id: query) {
                let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
                guard text.count >= 2 else { results = []; searched = false; return }
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                await run(text, barcode: nil)
            }
            .sheet(isPresented: $aiMeal) { AIMealSheet { dismiss() }.environmentObject(store) }
            .sheet(isPresented: $manualEntry) { ManualFoodSheet { food in Task { try? await Task.sleep(for: .milliseconds(450)); picked = FoodChoice(food: food) } } }
            .sheet(item: $picked) { choice in PortionSheet(food: choice.food) { dismiss() }.presentationDetents([.large]) }
            .fullScreenCover(isPresented: $scanning) {
                ZStack(alignment: .topLeading) {
                    BarcodeScanner { code in scanning = false; Task { await run(code, barcode: code) } }.ignoresSafeArea()
                    Button { scanning = false } label: { Image(systemName: "xmark").font(.hb(.headline, .semibold)).padding(14).background(.ultraThinMaterial, in: Circle()) }.padding(20).accessibilityLabel("סגור")
                    VStack { Spacer(); Text("כוון את הברקוד למרכז המסגרת").font(.hb(.headline, .semibold)).padding(14).background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 60) }.frame(maxWidth: .infinity)
                }
            }
        }
    }
    private func currentKind() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour < 11 ? "breakfast" : hour < 16 ? "lunch" : hour < 21 ? "dinner" : "snack"
    }
    private func run(_ text: String, barcode: String?) async {
        searching = true; defer { searching = false }
        let foods = await store.searchFoods(query: text, barcode: barcode)
        results = (foods ?? []).map { FoodChoice(food: $0) }; searched = true
        if barcode != nil, results.count == 1 { picked = results.first }
    }
}

private struct RecentRow: View {
    let meal: HealthRow
    var body: some View {
        let name = meal.data["name"].stringValue.flatMap { $0.isEmpty ? nil : $0 } ?? (meal.data["items"].arrayValue.first?["food"]["name"].stringValue ?? "ארוחה")
        HStack(spacing: 14) {
            Image(systemName: "arrow.counterclockwise").font(.hb(.headline, .semibold)).foregroundStyle(Color.wellnessOnPrimary).frame(width: 40, height: 40).background(Color.wellnessPrimary, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.hb(.headline, .semibold)).foregroundStyle(Color.wellnessInk).lineLimit(2).multilineTextAlignment(.leading)
                Text(meal.data["items"].arrayValue.compactMap { $0["food"]["name"].stringValue }.joined(separator: " · ")).font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 1) { Text("\(Int(nutrientTotal(meals: [meal], nutrient: "kcal").rounded()))").font(.hb(.headline, .semibold)).foregroundStyle(Color.wellnessInk); Text("קק״ל").font(.hb(.caption2)).foregroundStyle(Color.wellnessSecondary) }
        }.wellnessCard(padding: 14).accessibilityElement(children: .combine).accessibilityHint("מוסיף את הארוחה שוב להיום")
    }
}

private struct FoodRow: View {
    let food: JSONValue
    var body: some View {
        let per = food["per100"]
        HStack(spacing: 14) {
            Image(systemName: "plus").font(.hb(.headline, .semibold)).foregroundStyle(Color.wellnessOnPrimary).frame(width: 40, height: 40).background(Color.wellnessPrimary, in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(food["name"].stringValue ?? "מוצר").font(.hb(.headline, .semibold)).foregroundStyle(Color.wellnessInk).lineLimit(2).multilineTextAlignment(.leading)
                Text("חלבון \(fmt(per["protein"])) ג׳ · פחמימות \(fmt(per["carbs"])) ג׳ · שומן \(fmt(per["fat"])) ג׳").font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 1) { Text(fmt(per["kcal"])).font(.hb(.headline, .semibold)).foregroundStyle(Color.wellnessInk); Text("קק״ל ל־100").font(.hb(.caption2)).foregroundStyle(Color.wellnessSecondary) }
        }.wellnessCard(padding: 14)
    }
    private func fmt(_ v: JSONValue) -> String { String(Int((v.doubleValue ?? 0).rounded())) }
}

private struct PortionSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let food: JSONValue
    let onSaved: () -> Void
    @State private var quantity: Double = 100
    @ScaledMetric(relativeTo: .largeTitle) private var bigNumber: CGFloat = 44
    @State private var kind = "snack"
    private var unit: String { food["basis"].stringValue == "ml" ? "מ״ל" : "גרם" }
    private func total(_ key: String) -> Double { (food["per100"][key].doubleValue ?? 0) * quantity / 100 }
    var body: some View {
        NavigationStack {
            ScrollView { VStack(spacing: 20) {
                Text(food["name"].stringValue ?? "מוצר").font(.hb(.title2, .bold)).multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    macro("קק״ל", total("kcal"), Color.wellnessInk); macro("חלבון", total("protein"), .proteinBlue)
                    macro("פחמימות", total("carbs"), .carbsGold); macro("שומן", total("fat"), .fatCoral)
                }
                VStack(spacing: 14) {
                    Text("כמות").font(.hb(.subheadline)).foregroundStyle(Color.wellnessSecondary)
                    HStack(spacing: 22) {
                        stepper("plus", 10); VStack { Text(quantity, format: .number.precision(.fractionLength(0))).font(.hbFixed(bigNumber, .heavy)).monospacedDigit().contentTransition(.numericText(value: quantity)); Text(unit).foregroundStyle(Color.wellnessSecondary) }.frame(minWidth: 96)
                        stepper("minus", -10)
                    }
                    if let serving = food["servingSize"].doubleValue, serving > 0 {
                        Button("מנה (\(Int(serving)) \(unit))") { withAnimation(.snappy) { quantity = serving } }.buttonStyle(.bordered).tint(Color.wellnessPrimary)
                    }
                }.frame(maxWidth: .infinity).wellnessCard()
                Picker("ארוחה", selection: $kind) {
                    Text("בוקר").tag("breakfast"); Text("צהריים").tag("lunch"); Text("ערב").tag("dinner"); Text("נשנוש").tag("snack")
                }.pickerStyle(.segmented)
                Button { Task { if await store.saveMeal(kind: kind, name: food["name"].stringValue ?? "", food: food, quantity: quantity) { dismiss(); onSaved() } } } label: {
                    if store.busy { ProgressView().tint(Color.wellnessOnPrimary) } else { Label("הוסף לארוחה", systemImage: "plus.circle") }
                }.buttonStyle(PrimaryButton())
            }.padding(20) }
            .wellnessScreen().navigationTitle("פרטי מוצר").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("חזרה") { dismiss() } } }
            .onAppear {
                quantity = food["servingSize"].doubleValue.flatMap { $0 > 0 ? $0 : nil } ?? 100
                let hour = Calendar.current.component(.hour, from: Date())
                kind = hour < 11 ? "breakfast" : hour < 16 ? "lunch" : hour < 21 ? "dinner" : "snack"
            }
            .sensoryFeedback(.selection, trigger: quantity)
        }
    }
    private func macro(_ title: String, _ value: Double, _ color: Color) -> some View {
        VStack(spacing: 4) { Text(Int(value.rounded()), format: .number).font(.hb(.title3, .bold)).foregroundStyle(color).contentTransition(.numericText(value: value)); Text(title).font(.hb(.caption2)).foregroundStyle(Color.wellnessSecondary) }
            .frame(maxWidth: .infinity).padding(.vertical, 12).background(Color.wellnessChip, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
    private func stepper(_ icon: String, _ delta: Double) -> some View {
        Button { withAnimation(.snappy) { quantity = min(10_000, max(1, quantity + delta)) } } label: {
            Image(systemName: icon).font(.hb(.title3, .bold)).frame(width: 54, height: 54).background(Color.wellnessChip, in: Circle()).foregroundStyle(Color.wellnessInk)
        }.buttonStyle(PressableStyle()).accessibilityLabel(delta > 0 ? "הוסף כמות" : "הפחת כמות")
    }
}

/// Camera barcode reader with a visible scan frame and a sweeping line, so it is obvious the scanner is live.
struct BarcodeScanner: View {
    let onCode: (String) -> Void
    @State private var sweep = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let frame = CGSize(width: 280, height: 170)
    var body: some View {
        ZStack {
            BarcodeCamera(onCode: onCode)
            Color.black.opacity(0.45).reverseMask { RoundedRectangle(cornerRadius: 22, style: .continuous).frame(width: frame.width, height: frame.height) }.allowsHitTesting(false)
            RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white, lineWidth: 3).frame(width: frame.width, height: frame.height).allowsHitTesting(false)
            Rectangle().fill(LinearGradient(colors: [.clear, .red.opacity(0.9), .clear], startPoint: .leading, endPoint: .trailing))
                .frame(width: frame.width - 28, height: 3).shadow(color: .red.opacity(0.8), radius: 6)
                .offset(y: sweep ? frame.height / 2 - 16 : -(frame.height / 2 - 16)).allowsHitTesting(false)
            VStack {
                Spacer()
                Label("מחפש ברקוד…", systemImage: "barcode.viewfinder").font(.hb(.headline, .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 12).background(.black.opacity(0.55), in: Capsule()).padding(.bottom, 60)
            }.allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain).accessibilityLabel("סורק ברקוד פעיל")
        .onAppear { if !reduceMotion { withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { sweep = true } } }
    }
}
private extension View {
    func reverseMask<M: View>(@ViewBuilder _ mask: () -> M) -> some View {
        self.mask { Rectangle().overlay { mask().blendMode(.destinationOut) }.compositingGroup() }
    }
}

/// Camera barcode reader (EAN/UPC/Code128). Reports the first valid code once.
struct BarcodeCamera: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    func makeUIViewController(context: Context) -> ScannerController { let c = ScannerController(); c.onCode = onCode; return c }
    func updateUIViewController(_ controller: ScannerController, context: Context) {}
    final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onCode: ((String) -> Void)?
        private let session = AVCaptureSession()
        private var done = false
        override func viewDidLoad() {
            super.viewDidLoad(); view.backgroundColor = .black
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async { if granted { self?.configure() } }
            }
        }
        private func configure() {
            guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output); output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.ean13, .ean8, .upce, .code128].filter { output.availableMetadataObjectTypes.contains($0) }
            let layer = AVCaptureVideoPreviewLayer(session: session); layer.videoGravity = .resizeAspectFill; layer.frame = view.bounds
            view.layer.insertSublayer(layer, at: 0)
            DispatchQueue.global(qos: .userInitiated).async { [session] in session.startRunning() }
        }
        override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); view.layer.sublayers?.first?.frame = view.bounds }
        override func viewWillDisappear(_ animated: Bool) { super.viewWillDisappear(animated); session.stopRunning() }
        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !done, let code = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue, (8...14).contains(code.count), code.allSatisfy(\.isNumber) else { return }
            done = true; UINotificationFeedbackGenerator().notificationOccurred(.success); onCode?(code)
        }
    }
}


/// Enter a food by hand: name and nutrition per 100 g (or 100 ml), then choose the portion.
struct ManualFoodSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onDone: (JSONValue) -> Void
    @State private var name = ""
    @State private var basis = "g"
    @State private var kcal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    private func n(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".")).flatMap { $0 >= 0 ? $0 : nil } }
    private var valid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && (n(kcal) ?? -1) >= 0 && (n(kcal) ?? 0) <= 2000 && n(protein) != nil && n(carbs) != nil && n(fat) != nil }
    var body: some View {
        NavigationStack {
            List {
                Section("שם המזון") { TextField("למשל: לחם מקמח מלא", text: $name).accessibilityIdentifier("manual-name") }
                Section("ערכים תזונתיים") {
                    Picker("ל־100", selection: $basis) { Text("גרם").tag("g"); Text("מ״ל").tag("ml") }.pickerStyle(.segmented)
                    row("קלוריות ל־100", $kcal); row("חלבון (גרם)", $protein); row("פחמימות (גרם)", $carbs); row("שומן (גרם)", $fat)
                }
            }
            .wellnessList().navigationTitle("הוספה ידנית").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ביטול") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("המשך") { finish() }.disabled(!valid).accessibilityIdentifier("manual-continue") }
            }
        }
    }
    private func row(_ title: String, _ binding: Binding<String>) -> some View { HStack { Text(title); Spacer(); TextField("0", text: binding).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90) } }
    private func finish() {
        let food: JSONValue = .object(["id": .string(UUID().uuidString.lowercased()), "name": .string(String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))), "basis": .string(basis), "source": .string("manual"),
                                        "per100": .object(["kcal": .number(n(kcal) ?? 0), "protein": .number(n(protein) ?? 0), "carbs": .number(n(carbs) ?? 0), "fat": .number(n(fat) ?? 0)])])
        dismiss(); onDone(food)
    }
}
