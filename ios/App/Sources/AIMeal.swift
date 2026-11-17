import SwiftUI
import PhotosUI
import WellnessCore

/// Photo -> AI estimate -> review quantities -> save. Gated exactly like the web app (adult + explicit consent).
struct AIMealSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let onSaved: () -> Void
    @State private var photo: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var note = ""
    @State private var analyzing = false
    @State private var analysis: AppStore.MealAnalysis?
    @State private var items: [JSONValue] = []
    @State private var kind = "snack"
    var body: some View {
        NavigationStack {
            Group {
                if !store.aiEligible { unavailable }
                else if !store.aiConsented { consent }
                else if let analysis { review(analysis) }
                else { capture }
            }
            .wellnessScreen().navigationTitle("ארוחה מתמונה").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("סגור") { dismiss() } } }
        }
    }
    private var unavailable: some View {
        ContentUnavailableView("ה־AI זמין מגיל 18", systemImage: "person.crop.circle.badge.exclamationmark",
            description: Text("השלם תאריך לידה בפרופיל באפליקציה הרגילה כדי להפעיל המלצות AI. אפשר להמשיך להוסיף ארוחות ידנית."))
    }
    private var consent: some View { AIConsentView() }
    private var capture: some View {
        VStack(spacing: 18) {
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image).resizable().scaledToFill().frame(height: 260).frame(maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous)).accessibilityLabel("תמונת הארוחה")
            } else {
                PhotosPicker(selection: $photo, matching: .images) {
                    VStack(spacing: 12) { Image(systemName: "camera.viewfinder").font(.system(size: 44)).foregroundStyle(Color.wellnessSecondary); Text("בחר תמונה של הארוחה").font(.hb(.headline, .semibold)); Text("אפשר לצלם בצילום מהיר ולבחור כאן, או לבחור מהגלריה.").font(.hb(.footnote)).foregroundStyle(Color.wellnessSecondary).multilineTextAlignment(.center) }
                        .frame(maxWidth: .infinity, minHeight: 220).padding().background(Color.wellnessCard, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.wellnessHairline, style: StrokeStyle(lineWidth: 1.5, dash: [6])))
                }.buttonStyle(PressableStyle())
            }
            TextField("הערה לשיפור הדיוק (לא חובה)", text: $note, axis: .vertical).lineLimit(1...3).padding(14)
                .background(Color.wellnessCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.wellnessHairline))
            Spacer()
            Button { Task { await analyze() } } label: {
                if analyzing { HStack(spacing: 10) { ProgressView().tint(Color.wellnessOnPrimary); Text("מנתח…") } } else { Label("נתח ארוחה", systemImage: "sparkles") }
            }.buttonStyle(PrimaryButton()).disabled(imageData == nil || analyzing)
        }.padding(20)
        .onChange(of: photo) { _, item in Task { await load(item) } }
    }
    private func review(_ analysis: AppStore.MealAnalysis) -> some View {
        List {
            if analysis.needsClarification, !analysis.question.isEmpty {
                Section { Label(analysis.question, systemImage: "questionmark.bubble") } footer: { Text("אפשר לתקן את הכמויות למטה לפני השמירה.") }
            }
            Section {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item["food"]["name"].stringValue ?? "רכיב").font(.hb(.headline, .semibold))
                            Text("\(Int((item["quantity"].doubleValue ?? 0).rounded())) \(item["food"]["basis"].stringValue == "ml" ? "מ״ל" : "גרם") · \(Int(kcal(item).rounded())) קק״ל").font(.hb(.subheadline)).foregroundStyle(Color.wellnessSecondary)
                            if let assumption = item["assumption"].stringValue, !assumption.isEmpty { Text(assumption).font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Stepper("", onIncrement: { change(index, 10) }, onDecrement: { change(index, -10) }).labelsHidden()
                    }.swipeActions { if items.count > 1 { Button(role: .destructive) { withAnimation { _ = items.remove(at: index) } } label: { Label("הסרה", systemImage: "trash") } } }
                }
            } header: { Text("הערכת AI — בדוק ותקן") } footer: { Text("זו הערכה בלבד. הערכים עשויים להיות לא מדויקים.") }
            Section("סוג ארוחה") {
                Picker("סוג", selection: $kind) { Text("בוקר").tag("breakfast"); Text("צהריים").tag("lunch"); Text("ערב").tag("dinner"); Text("נשנוש").tag("snack") }.pickerStyle(.segmented)
            }
            Section {
                Button { Task { if await store.saveAnalyzedMeal(analysis, items: items, kind: kind) { dismiss(); onSaved() } } } label: {
                    Text("הוסף לארוחה · \(Int(items.reduce(0) { $0 + kcal($1) }.rounded())) קק״ל").frame(maxWidth: .infinity)
                }.buttonStyle(PrimaryButton()).listRowBackground(Color.clear).listRowInsets(EdgeInsets()).disabled(store.busy || items.isEmpty)
            }
        }.wellnessList()
    }
    private func kcal(_ item: JSONValue) -> Double { (item["food"]["per100"]["kcal"].doubleValue ?? 0) * (item["quantity"].doubleValue ?? 0) / 100 }
    private func change(_ index: Int, _ delta: Double) {
        guard items.indices.contains(index), case .object(var fields) = items[index] else { return }
        fields["quantity"] = .number(min(10_000, max(1, (fields["quantity"]?.doubleValue ?? 0) + delta))); items[index] = .object(fields)
    }
    private func load(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        let scale = min(1, 1800 / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { ctx in UIColor.white.setFill(); ctx.fill(CGRect(origin: .zero, size: size)); image.draw(in: CGRect(origin: .zero, size: size)) }
        var quality = 0.86, jpeg = resized.jpegData(compressionQuality: quality)
        while let current = jpeg, current.count > 5_000_000, quality > 0.3 { quality -= 0.15; jpeg = resized.jpegData(compressionQuality: quality) }
        imageData = jpeg
        let hour = Calendar.current.component(.hour, from: Date()); kind = hour < 11 ? "breakfast" : hour < 16 ? "lunch" : hour < 21 ? "dinner" : "snack"
    }
    private func analyze() async {
        guard let imageData else { return }
        analyzing = true; defer { analyzing = false }
        if let result = await store.analyzeMeal(jpeg: imageData, description: note.trimmingCharacters(in: .whitespacesAndNewlines)) { items = result.items; analysis = result }
    }
}

/// Shared consent / eligibility gate (same wording and rules as the web app).
struct AIConsentView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "sparkles").font(.hb(.largeTitle)).foregroundStyle(.flame)
            Text("אישור שימוש ב־AI").font(.hb(.title2, .bold))
            Text("אישור שימוש ב־AI שולח את תוכן הבקשה הדרוש ל־Cloudflare. התוצאות דורשות בדיקה ואישור שלך.")
            Text("שם, PIN ופרופיל גוף מלא אינם נשלחים אוטומטית. אין שימוש בתוכן לאימון המודלים. אפשר לבטל בהגדרות.").foregroundStyle(Color.wellnessSecondary)
            Spacer()
            Button { Task { _ = await store.grantAIConsent() } } label: {
                if store.busy { ProgressView().tint(Color.wellnessOnPrimary) } else { Text("מאשר/ת שימוש ב־AI האישי") }
            }.buttonStyle(PrimaryButton()).disabled(store.busy)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
