import SwiftUI
import WellnessCore

struct ActivityScreen: View {
    @EnvironmentObject private var store: AppStore
    @State private var privacy = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("הפעילות שלך").font(.hb(.title, .bold))
                            Text("Apple Watch ו־iPhone").foregroundStyle(Color.wellnessSecondary)
                        }
                        Spacer()
                        Image(systemName: "heart.fill").foregroundStyle(.pink).font(.hb(.title)).padding(15).background(Color.pink.opacity(0.07), in: Circle())
                    }
                    if !store.health.available {
                        ContentUnavailableView("Apple Health לא זמין במכשיר הזה", systemImage: "heart.slash")
                    } else if !store.healthLoaded {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("האימונים שלך, במקום אחד").sectionTitle()
                            Text("חבר את בריאות, ואז בחר אילו אימונים לייבא לחשבון שלך.").foregroundStyle(Color.wellnessSecondary)
                            Button { Task { await store.readHealth() } } label: {
                                if store.busy { ProgressView().tint(Color.wellnessOnPrimary) } else { Label("חיבור ל־Apple Health", systemImage: "heart") }
                            }.buttonStyle(PrimaryButton()).disabled(store.busy)
                        }.wellnessCard()
                    } else {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                if let steps = store.steps { Text(steps, format: .number.precision(.fractionLength(0))).font(.hb(.largeTitle, .bold)).monospacedDigit() }
                                else { Text("—").font(.hb(.largeTitle, .bold)) }
                                Text("צעדים היום").foregroundStyle(Color.wellnessSecondary)
                            }
                            Spacer()
                            Image(systemName: "figure.walk").font(.hb(.largeTitle)).foregroundStyle(.orange)
                        }.wellnessCard().accessibilityElement(children: .combine)
                        HStack {
                            Text("אימונים אחרונים").sectionTitle()
                            Spacer()
                            Button { Task { await store.readHealth() } } label: {
                                if store.busy { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                            }.disabled(store.busy).accessibilityLabel("רענון פעילות")
                        }
                        if store.candidates.isEmpty {
                            ContentUnavailableView("אין אימונים חדשים לייבוא", systemImage: "checkmark.circle", description: Text("ייתכן שכל האימונים כבר יובאו, שאין נתונים או שלא ניתנה הרשאת קריאה בבריאות."))
                        } else {
                            Text("בחר אימונים מה־30 ימים האחרונים").font(.hb(.subheadline)).foregroundStyle(Color.wellnessSecondary)
                            ForEach(store.candidates) { workout in
                                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { if store.selection.contains(workout.id) { store.selection.remove(workout.id) } else { store.selection.insert(workout.id) } } } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: store.selection.contains(workout.id) ? "checkmark.circle.fill" : "circle").font(.hb(.title2)).foregroundStyle(store.selection.contains(workout.id) ? Color.wellnessInk : Color.wellnessSecondary).symbolEffect(.bounce, value: store.selection.contains(workout.id))
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(workout.name).font(.hb(.headline, .semibold))
                                            Text(workout.start, format: .dateTime.day().month(.abbreviated).hour().minute()).font(.hb(.subheadline)).foregroundStyle(Color.wellnessSecondary)
                                            HStack(spacing: 10) {
                                                Text("\(Int((workout.duration / 60).rounded())) דק׳")
                                                if let energy = workout.energyKcal { Text("\(Int(energy.rounded())) קק״ל") }
                                                if let distance = workout.distanceMeters { Text("\(distance / 1000, specifier: "%.1f") ק״מ") }
                                            }.font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary)
                                            Text(workout.sourceName).font(.hb(.caption2)).foregroundStyle(Color.wellnessSecondary)
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                    }.wellnessCard()
                                }.buttonStyle(PressableStyle()).disabled(store.busy)
                                    .sensoryFeedback(.selection, trigger: store.selection)
                                    .accessibilityAddTraits(store.selection.contains(workout.id) ? [.isSelected] : [])
                            }
                            Button { Task { await store.importSelected() } } label: {
                                if store.busy { ProgressView().tint(Color.wellnessOnPrimary) }
                                else { Text(store.selection.isEmpty ? "בחר אימונים לייבוא" : "ייבוא \(store.selection.count) אימונים") }
                            }.buttonStyle(PrimaryButton()).disabled(store.selection.isEmpty || store.busy)
                        }
                    }
                    if let message = store.importMessage { Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green).sensoryFeedback(.success, trigger: message) }
                    Button { privacy = true } label: { Text("מה נשמר בחשבון?").font(.hb(.footnote)).foregroundStyle(Color.wellnessSecondary).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle()) }
                }.padding(16)
            }.wellnessScreen().safeAreaInset(edge: .top, spacing: 0) { HealthTabBar() }.toolbar(.hidden, for: .navigationBar).refreshable { await store.readHealth() }
                .sheet(isPresented: $privacy) { HealthPrivacySheet() }
        }
    }
}

private struct HealthPrivacySheet: View {
    @Environment(\.dismiss) private var dismiss
    private func block(_ symbol: String, _ color: Color, _ title: String, _ paragraphs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(color).frame(width: 34, height: 34)
                    .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                Text(title).font(.hb(.headline, .semibold))
            }
            ForEach(paragraphs, id: \.self) { Text($0).font(.hb(.subheadline)).foregroundStyle(Color.wellnessSecondary).fixedSize(horizontal: false, vertical: true) }
        }.frame(maxWidth: .infinity, alignment: .leading).wellnessCard(padding: 16)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    block("icloud.and.arrow.up.fill", Color.proteinBlue, "נשמר רק אחרי בחירה וייבוא",
                          ["סוג אימון, תאריך, משך, מקור הנתונים, מרחק וקלוריות כשיש נתונים. האימונים נשמרים בחשבון הקיים בשרת האפליקציה."])
                    block("iphone", Color.carbsGold, "נשאר במכשיר", ["סיכום הצעדים היומי מוצג כאן ואינו מועלה לשרת."])
                    block("hand.raised.fill", Color.fatCoral, "בשליטתך",
                          ["אין כתיבה לבריאות או סנכרון ברקע. אפשר לשנות הרשאות ביישום בריאות. ביטול הרשאה אינו מוחק אימונים שכבר ייבאת; אפשר למחוק אותם מיומן האימונים כאן.",
                           "מוצגים עד 500 אימונים מ־30 הימים האחרונים. הרשאת קריאה שנדחתה עשויה להיראות כמו רשימה ריקה — כך Apple מגינה על הפרטיות."])
                    Color.clear.frame(height: 20)
                }.padding(.horizontal, 16).padding(.top, 8)
            }.background(Color.wellnessCanvas.ignoresSafeArea()).navigationTitle("הנתונים שלך").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("סגור") { dismiss() } } }
        }
    }
}
