import SwiftUI
import WellnessCore

struct ActivityScreen: View {
    @EnvironmentObject private var store: AppStore
    @State private var privacy = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("הפעילות שלך").font(.largeTitle.bold())
                            Text("Apple Watch ו־iPhone").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "heart.fill").foregroundStyle(.pink).font(.title).padding(15).background(Color.pink.opacity(0.07), in: Circle())
                    }
                    if !store.health.available {
                        ContentUnavailableView("Apple Health לא זמין במכשיר הזה", systemImage: "heart.slash")
                    } else if !store.healthLoaded {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("האימונים שלך, במקום אחד").font(.title2.bold())
                            Text("חבר את בריאות, ואז בחר אילו אימונים לייבא לחשבון שלך.").foregroundStyle(.secondary)
                            Button { Task { await store.readHealth() } } label: {
                                if store.busy { ProgressView().tint(.white) } else { Label("חיבור ל־Apple Health", systemImage: "heart") }
                            }.buttonStyle(PrimaryButton()).disabled(store.busy)
                        }.wellnessCard()
                    } else {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                if let steps = store.steps { Text(steps, format: .number.precision(.fractionLength(0))).font(.largeTitle.bold().monospacedDigit()) }
                                else { Text("—").font(.largeTitle.bold()) }
                                Text("צעדים היום").foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "figure.walk").font(.largeTitle).foregroundStyle(.orange)
                        }.wellnessCard().accessibilityElement(children: .combine)
                        HStack {
                            Text("אימונים אחרונים").font(.title2.bold())
                            Spacer()
                            Button { Task { await store.readHealth() } } label: {
                                if store.busy { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                            }.disabled(store.busy).accessibilityLabel("רענון פעילות")
                        }
                        if store.candidates.isEmpty {
                            ContentUnavailableView("אין אימונים חדשים לייבוא", systemImage: "checkmark.circle", description: Text("ייתכן שכל האימונים כבר יובאו, שאין נתונים או שלא ניתנה הרשאת קריאה בבריאות."))
                        } else {
                            Text("בחר אימונים מה־30 ימים האחרונים").font(.subheadline).foregroundStyle(.secondary)
                            ForEach(store.candidates) { workout in
                                Button { if store.selection.contains(workout.id) { store.selection.remove(workout.id) } else { store.selection.insert(workout.id) } } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: store.selection.contains(workout.id) ? "checkmark.circle.fill" : "circle").font(.title2)
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(workout.name).font(.headline)
                                            Text(workout.start, format: .dateTime.day().month(.abbreviated).hour().minute()).font(.subheadline).foregroundStyle(.secondary)
                                            HStack(spacing: 10) {
                                                Text("\(Int((workout.duration / 60).rounded())) דק׳")
                                                if let energy = workout.energyKcal { Text("\(Int(energy.rounded())) קק״ל") }
                                                if let distance = workout.distanceMeters { Text("\(distance / 1000, specifier: "%.1f") ק״מ") }
                                            }.font(.caption).foregroundStyle(.secondary)
                                            Text(workout.sourceName).font(.caption2).foregroundStyle(.secondary)
                                        }.frame(maxWidth: .infinity, alignment: .leading)
                                    }.wellnessCard()
                                }.buttonStyle(.plain).disabled(store.busy)
                                    .accessibilityAddTraits(store.selection.contains(workout.id) ? [.isSelected] : [])
                            }
                            Button { Task { await store.importSelected() } } label: {
                                if store.busy { ProgressView().tint(.white) }
                                else { Text(store.selection.isEmpty ? "בחר אימונים לייבוא" : "ייבוא \(store.selection.count) אימונים") }
                            }.buttonStyle(PrimaryButton()).disabled(store.selection.isEmpty || store.busy)
                        }
                    }
                    if let message = store.importMessage { Label(message, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                    Button("מה נשמר בחשבון?") { privacy = true }.font(.footnote).foregroundStyle(.secondary)
                }.padding(22)
            }.background(Color.wellnessCanvas.opacity(0.35)).toolbar(.hidden, for: .navigationBar)
                .sheet(isPresented: $privacy) { HealthPrivacySheet() }
        }
    }
}

private struct HealthPrivacySheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("נשמר רק אחרי בחירה וייבוא") {
                    Text("סוג אימון, תאריך, משך, מקור הנתונים, מרחק וקלוריות כשיש נתונים. האימונים נשמרים בחשבון הקיים בשרת האפליקציה.")
                }
                Section("נשאר במכשיר") { Text("סיכום הצעדים היומי מוצג כאן ואינו מועלה לשרת.") }
                Section("בשליטתך") {
                    Text("אין כתיבה לבריאות או סנכרון ברקע. אפשר לשנות הרשאות ביישום בריאות. ביטול הרשאה אינו מוחק אימונים שכבר ייבאת; אפשר למחוק אותם מיומן האימונים כאן.")
                    Text("מוצגים עד 500 אימונים מ־30 הימים האחרונים. הרשאת קריאה שנדחתה עשויה להיראות כמו רשימה ריקה — כך Apple מגינה על הפרטיות.")
                }
            }.navigationTitle("הנתונים שלך").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("סגור") { dismiss() } } }
        }
    }
}
