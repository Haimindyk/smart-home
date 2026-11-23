import SwiftUI
import UIKit
import UserNotifications
import WellnessCore

/// Keeps one meal analysis alive and resumable.
///
/// The photo is uploaded once and the request carries a fixed id, so the server treats every repeat as the same job: it returns the
/// stored result, or says it is still busy and we wait. While the app is in the background iOS gives a short grace period (the
/// background task below); if that runs out the job is simply picked up again the next time the app becomes active.
@MainActor
final class MealAnalysisCenter: ObservableObject {
    static let shared = MealAnalysisCenter()
    enum Phase: Equatable { case analyzing, ready, failed(String) }
    private struct Pending: Codable { var id: String; var imagePath: String?; var note: String; var createdAt: Date; var entryDate: String? = nil; var entryTime: String? = nil }

    @Published private(set) var phase: Phase?
    @Published private(set) var preview: UIImage?
    @Published private(set) var analysis: AppStore.MealAnalysis?
    /// Set when the review sheet should be on screen.
    @Published var presenting = false
    /// The meal that was saved automatically from the finished analysis (nil when saving failed and the review is needed).
    @Published private(set) var savedMealID: String?
    /// Set when the saved meal should be opened for editing.
    @Published var presentingMealID: String?
    private var task: Task<Void, Never>?
    private var background: UIBackgroundTaskIdentifier = .invalid
    private let defaultsKey = "pendingMealAnalysis"
    private var imageURL: URL { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("pending-meal.jpg") }
    var isBusy: Bool { phase == .analyzing }

    /// Starts analyzing a photo (already resized/compressed JPEG).
    func start(jpeg: Data, note: String, store: AppStore) {
        guard !isBusy else { return }
        try? jpeg.write(to: imageURL, options: .atomic)
        preview = UIImage(data: jpeg); analysis = nil; presenting = false; savedMealID = nil
        let pending = Pending(id: UUID().uuidString.lowercased(), imagePath: nil, note: note, createdAt: Date(), entryDate: store.dateKey, entryTime: AppStore.timeKey(Date(), zone: store.timeZone))
        save(pending); run(pending, store: store)
    }
    /// Starts analyzing a spoken/typed description (no photo).
    func startText(description: String, store: AppStore) {
        guard !isBusy else { return }
        preview = nil; analysis = nil; presenting = false; savedMealID = nil
        try? FileManager.default.removeItem(at: imageURL)
        let pending = Pending(id: UUID().uuidString.lowercased(), imagePath: nil, note: description, createdAt: Date(), entryDate: store.dateKey, entryTime: AppStore.timeKey(Date(), zone: store.timeZone))
        save(pending); run(pending, store: store, textOnly: true)
    }
    /// Called when the app becomes active: an interrupted job is asked for again with the same id.
    func resumeIfNeeded(store: AppStore) {
        guard task == nil, !isBusy, phase != .ready, let pending = load() else { return }
        if store.isFixture { clear(); return }   // UI-test jobs never outlive the launch that made them
        if Date().timeIntervalSince(pending.createdAt) > 60 * 60 { clear(); return }
        if let data = try? Data(contentsOf: imageURL) { preview = UIImage(data: data) }
        run(pending, store: store, textOnly: pending.imagePath == nil && preview == nil)
    }
    /// Shows the outcome: the saved meal for editing, or the review when saving did not work.
    func openResult() {
        if let id = savedMealID { presentingMealID = id; clear() } else { presenting = true }
    }
    func clear() {
        task?.cancel(); task = nil
        phase = nil; analysis = nil; preview = nil; presenting = false; savedMealID = nil
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        try? FileManager.default.removeItem(at: imageURL)
    }
    /// Forgets the finished job but keeps nothing on disk (after the meal was saved).
    func finish() { clear() }

    private func run(_ initial: Pending, store: AppStore, textOnly: Bool = false) {
        phase = .analyzing
        beginBackground()
        task = Task { [weak self] in
            guard let self else { return }
            defer { Task { @MainActor in self.endBackground(); self.task = nil } }
            var pending = initial
            if !textOnly, pending.imagePath == nil {
                if store.isFixture { pending.imagePath = "fixture/\(pending.id).jpg"; self.save(pending) }
                else {
                    guard let data = try? Data(contentsOf: self.imageURL), let owner = store.session?.owner, let backend = store.backend else { self.finishWith(.failed("לא הצלחנו לקרוא את התמונה. נסה לצלם שוב.")); return }
                    do { pending.imagePath = try await backend.uploadImage(data, owner: owner); self.save(pending) }
                    catch { self.finishWith(.failed("העלאת התמונה נכשלה. בדוק חיבור ונסה שוב.")); return }
                }
            }
            let outcome = await store.runMealAnalysis(imagePath: textOnly ? nil : pending.imagePath, requestID: pending.id, description: pending.note)
            guard !Task.isCancelled else { return }
            if case .ready(let result) = outcome {
                // Save right away at the time the meal was entered; the time and details can be edited afterwards.
                let time = pending.entryTime ?? AppStore.timeKey(pending.createdAt, zone: store.timeZone)
                let row = await store.saveAnalyzedMealRow(result, items: result.items, kind: AppStore.mealKind(forTime: time), date: pending.entryDate, time: time)
                self.savedMealID = row?.id
                // Saved: forget the pending job now, or relaunching the app before the banner is opened would analyse and save the same meal again.
                if row != nil { UserDefaults.standard.removeObject(forKey: self.defaultsKey) }
            }
            self.finishWith(outcome)
        }
    }
    private func finishWith(_ outcome: AppStore.AnalysisOutcome) {
        switch outcome {
        case .ready(let result):
            analysis = result; phase = .ready
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            notifyIfInBackground()
        case .failed(let message):
            if message.isEmpty { return }   // cancelled or the account changed
            phase = .failed(message)
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }
    }

    // MARK: Persistence and background time

    private func save(_ pending: Pending) { if let data = try? JSONEncoder().encode(pending) { UserDefaults.standard.set(data, forKey: defaultsKey) } }
    private func load() -> Pending? { UserDefaults.standard.data(forKey: defaultsKey).flatMap { try? JSONDecoder().decode(Pending.self, from: $0) } }
    private func beginBackground() {
        guard background == .invalid else { return }
        background = UIApplication.shared.beginBackgroundTask(withName: "meal-analysis") { [weak self] in
            // Out of time: stop waiting here, the job continues on the server and is asked for again when the app returns.
            Task { @MainActor in self?.task?.cancel(); self?.task = nil; self?.endBackground() }
        }
    }
    private func endBackground() {
        guard background != .invalid else { return }
        UIApplication.shared.endBackgroundTask(background); background = .invalid
    }
    private func notifyIfInBackground() {
        guard UIApplication.shared.applicationState != .active else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = "הארוחה נשמרה ביומן"; content.body = "הניתוח הושלם והארוחה נוספה. אפשר לבדוק ולערוך את הפרטים והשעה."; content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "meal-analysis-ready", content: content, trigger: nil))
        }
    }
}

// MARK: - Review

/// The step after analysis: check quantities, pick the meal type, save.
struct MealReviewView: View {
    @EnvironmentObject private var store: AppStore
    let analysis: AppStore.MealAnalysis
    let onSaved: () -> Void
    @State private var items: [JSONValue] = []
    @State private var kind = "snack"
    @State private var loaded = false
    var body: some View {
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
                            if let assumption = item["assumption"].stringValue, !assumption.isEmpty { Text(assumption).font(.hb(.caption)).foregroundStyle(Color.amberInk) }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Stepper("", onIncrement: { change(index, 10) }, onDecrement: { change(index, -10) }).labelsHidden()
                    }.swipeActions { if items.count > 1 { Button(role: .destructive) { withAnimation { _ = items.remove(at: index) } } label: { Label("הסרה", systemImage: "trash") } } }
                }
            } header: { Text("הערכת AI — בדוק ותקן") } footer: { Text("זו הערכה בלבד. הערכים עשויים להיות לא מדויקים.") }
            Section("סוג ארוחה") {
                Picker("סוג", selection: $kind) { Text("בוקר").tag("breakfast"); Text("צהריים").tag("lunch"); Text("ערב").tag("dinner"); Text("נשנוש").tag("snack") }.pickerStyle(.segmented)
            }
            Section {
                Button { Task { if await store.saveAnalyzedMeal(analysis, items: items, kind: kind) { onSaved() } } } label: {
                    Text("הוסף לארוחה · \(Int(items.reduce(0) { $0 + kcal($1) }.rounded())) קק״ל").frame(maxWidth: .infinity)
                }.buttonStyle(PrimaryButton()).listRowBackground(Color.clear).listRowInsets(EdgeInsets()).disabled(store.busy || items.isEmpty).accessibilityIdentifier("review-save")
            }
        }.wellnessList()
        .onAppear {
            guard !loaded else { return }; loaded = true
            items = analysis.items
            let hour = Calendar.current.component(.hour, from: Date()); kind = hour < 11 ? "breakfast" : hour < 16 ? "lunch" : hour < 21 ? "dinner" : "snack"
        }
    }
    private func kcal(_ item: JSONValue) -> Double { (item["food"]["per100"]["kcal"].doubleValue ?? 0) * (item["quantity"].doubleValue ?? 0) / 100 }
    private func change(_ index: Int, _ delta: Double) {
        guard items.indices.contains(index), case .object(var fields) = items[index] else { return }
        fields["quantity"] = .number(min(10_000, max(1, (fields["quantity"]?.doubleValue ?? 0) + delta))); items[index] = .object(fields)
    }
}

/// Review presented from the root once an analysis finished.
struct MealReviewSheet: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject var center: MealAnalysisCenter
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Group {
                if let analysis = center.analysis {
                    VStack(spacing: 0) {
                        if let preview = center.preview {
                            Image(uiImage: preview).resizable().scaledToFill().frame(height: 170).frame(maxWidth: .infinity).clipped()
                                .accessibilityLabel("תמונת הארוחה")
                        }
                        MealReviewView(analysis: analysis) { center.finish(); dismiss() }
                    }
                } else { ProgressView() }
            }
            .wellnessScreen().navigationTitle("ארוחה מתמונה").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("סגור") { dismiss() } } }
        }.interactiveDismissDisabled(false)
    }
}

// MARK: - Banner while a job is pending

/// Small card over the tab bar: analysing, ready to review, or failed.
struct MealAnalysisBanner: View {
    @ObservedObject var center: MealAnalysisCenter
    var body: some View {
        if let phase = center.phase {
            HStack(spacing: 12) {
                ZStack {
                    if let preview = center.preview { Image(uiImage: preview).resizable().scaledToFill() } else { Color.wellnessChip }
                }.frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    switch phase {
                    case .analyzing: Text("מנתח את הארוחה…").font(.hb(.subheadline, .semibold)); Text("אפשר להמשיך להשתמש באפליקציה").font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary)
                    case .ready: Text(center.savedMealID != nil ? "הארוחה נשמרה ביומן" : "הניתוח מוכן").font(.hb(.subheadline, .semibold)); Text(center.savedMealID != nil ? "אפשר לערוך את הפרטים והשעה" : "בדוק ושמור את הארוחה").font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary)
                    case .failed(let message): Text("הניתוח נכשל").font(.hb(.subheadline, .semibold)); Text(message).font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary).lineLimit(2)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                switch phase {
                case .analyzing: ProgressView()
                case .ready: Button(center.savedMealID != nil ? "עריכה" : "בדיקה") { center.openResult() }.font(.hb(.subheadline, .bold)).padding(.horizontal, 16).frame(minHeight: 38).background(Color.wellnessPrimary, in: Capsule()).foregroundStyle(Color.wellnessOnPrimary).accessibilityIdentifier("analysis-review")
                case .failed: Button { center.clear() } label: { Image(systemName: "xmark").font(.footnote.weight(.bold)).frame(width: 34, height: 34).background(Color.wellnessChip, in: Circle()) }.accessibilityLabel("סגירה")
                }
            }
            .padding(12).background(Color.wellnessCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.wellnessHairline))
            .shadow(color: .black.opacity(0.12), radius: 14, y: 5)
            .padding(.horizontal, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
