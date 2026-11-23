import SwiftUI
import WellnessCore

/// "Improve the model": the user opts in once, then chooses which corrected meals (photo + items) to share as training examples.
struct TrainingDataScreen: View {
    @EnvironmentObject private var store: AppStore
    @State private var confirmRevoke = false
    @State private var confirmShare: HealthRow?
    private var shareable: [HealthRow] {
        store.meals.filter { $0.data["imagePath"].stringValue != nil }.sorted { ($0.data["date"].stringValue ?? "") > ($1.data["date"].stringValue ?? "") }
    }
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "wand.and.stars").font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.purple).frame(width: 44, height: 44)
                            .background(Color.purple.opacity(0.15), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        Text("עזור לשפר את הזיהוי").font(.hb(.title3, .bold))
                    }
                    Text("כשתיקנת ארוחה שהמודל פספס (למשל עוף במקום הודו), אפשר לשתף אותה כדוגמה כדי שהמודל ילמד ממנה.").font(.hb(.subheadline)).foregroundStyle(Color.wellnessSecondary)
                    bullet("hand.tap.fill", "אתה בוחר כל דוגמה בנפרד. הסכמה לבדה לא שולחת כלום.")
                    bullet("photo", "נשמרים רק התמונה והרכיבים שתיקנת, בלי שם, קוד או פרופיל.")
                    bullet("arrow.uturn.backward", "אפשר לבטל בכל רגע, והדוגמאות שנשמרו נמחקות.")
                    bullet("person.fill.checkmark", "זמין למי שמעל גיל 18 (נדרש תאריך לידה בפרופיל).")
                }.frame(maxWidth: .infinity, alignment: .leading).wellnessCard(padding: 18)

                if store.trainingEnabled {
                    HStack {
                        Label("דוגמאות ששיתפת: \(store.trainingCount)", systemImage: "checkmark.seal.fill").font(.hb(.subheadline, .semibold)).foregroundStyle(Color.proteinBlue).accessibilityIdentifier("training-count")
                        Spacer()
                    }.padding(.horizontal, 4)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ארוחות עם תמונה").sectionTitle().padding(.bottom, 4)
                        if shareable.isEmpty {
                            Text("עוד אין ארוחות עם תמונה. ארוחה שתנתח מתמונה ותתקן תופיע כאן.").font(.hb(.subheadline)).foregroundStyle(Color.wellnessSecondary).padding(.vertical, 10)
                        }
                        ForEach(shareable) { meal in
                            row(meal)
                            if meal.id != shareable.last?.id { Divider() }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).wellnessCard(padding: 16)
                }

                Button {
                    if store.trainingEnabled { confirmRevoke = true } else { Task { _ = await store.setTrainingConsent(true) } }
                } label: {
                    Text(store.trainingEnabled ? "ביטול הסכמה ומחיקת הדוגמאות" : "אני מאשר/ת להשתתף").frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(PressableStyle()).foregroundStyle(store.trainingEnabled ? Color.red : Color.wellnessOnPrimary)
                .background(store.trainingEnabled ? Color.red.opacity(0.1) : Color.wellnessPrimary, in: Capsule())
                .accessibilityIdentifier("training-consent")
                Color.clear.frame(height: 24)
            }.padding(.horizontal, 16).padding(.top, 8)
        }
        .background(Color.wellnessCanvas.ignoresSafeArea()).navigationTitle("שיפור המודל").navigationBarTitleDisplayMode(.inline)
        .task { await store.loadTrainingStatus() }
        .confirmationDialog("לבטל את ההסכמה?", isPresented: $confirmRevoke, titleVisibility: .visible) {
            Button("ביטול הסכמה ומחיקת הדוגמאות", role: .destructive) { Task { _ = await store.setTrainingConsent(false) } }
            Button("חזרה", role: .cancel) {}
        } message: { Text("כל הדוגמאות ששיתפת יימחקו.") }
        .confirmationDialog("לשתף את הארוחה כדוגמה?", isPresented: Binding(get: { confirmShare != nil }, set: { if !$0 { confirmShare = nil } }), titleVisibility: .visible) {
            Button("שתף") { if let meal = confirmShare { Task { _ = await store.shareTrainingExample(meal) } }; confirmShare = nil }
            Button("ביטול", role: .cancel) { confirmShare = nil }
        } message: { Text("התמונה והרכיבים כפי שתיקנת יישמרו לבדיקה כדי לשפר את המודל. עיינת בהם ואתה מאשר.") }
    }
    private func bullet(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.wellnessSecondary).frame(width: 22)
            Text(text).font(.hb(.footnote)).foregroundStyle(Color.wellnessSecondary).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func row(_ meal: HealthRow) -> some View {
        let shared = store.trainingShared.contains(meal.id)
        return HStack(spacing: 12) {
            PrivateMealPhoto(meal: meal, thumbnail: true).frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(mealName(meal)).font(.hb(.subheadline, .semibold)).lineLimit(1)
                Text(meal.data["date"].stringValue ?? "").font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if shared {
                Label("שותף", systemImage: "checkmark").font(.hb(.caption, .semibold)).foregroundStyle(Color.proteinBlue)
            } else {
                Button { confirmShare = meal } label: { Text("שתף").font(.hb(.subheadline, .semibold)).padding(.horizontal, 16).frame(minHeight: 36).background(Color.wellnessChip, in: Capsule()) }
                    .buttonStyle(PressableStyle()).accessibilityIdentifier("training-share-\(meal.id)")
            }
        }.padding(.vertical, 8)
    }
}
