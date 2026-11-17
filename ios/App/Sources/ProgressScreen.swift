import SwiftUI
import Charts
import WellnessCore

/// Weight trend and the last seven days of calories, mirroring the web app's progress tab.
struct ProgressScreen: View {
    @EnvironmentObject private var store: AppStore
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = store.timeZone; return c }
    private func parse(_ key: String?) -> Date? {
        guard let key else { return nil }
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = store.timeZone; f.dateFormat = "yyyy-MM-dd"
        return f.date(from: key)
    }
    private var weights: [(date: Date, kg: Double)] {
        store.weightLogs.compactMap { row in
            guard let date = parse(row.data["date"].stringValue), let kg = row.data["weight"].doubleValue else { return nil }
            return (date, kg)
        }.sorted { $0.date < $1.date }.suffix(60).map { $0 }
    }
    private var week: [(date: Date, kcal: Double)] {
        let end = calendar.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: end) else { return nil }
            let key = AppStore.dateKey(day, zone: store.timeZone)
            return (day, nutrientTotal(meals: store.meals.filter { $0.data["date"].stringValue == key }, nutrient: "kcal"))
        }
    }
    private var target: Double? { store.goal["kcal"].doubleValue }
    private var loggedDays: Int { week.filter { $0.kcal > 0 }.count }
    private var average: Double { let logged = week.filter { $0.kcal > 0 }; return logged.isEmpty ? 0 : logged.reduce(0) { $0 + $1.kcal } / Double(logged.count) }
    private var delta: Double? { guard let first = weights.first?.kg, let last = weights.last?.kg, weights.count > 1 else { return nil }; return last - first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("ההתקדמות שלך").font(.largeTitle.bold())
                    HStack(spacing: 12) {
                        stat("ממוצע יומי", average > 0 ? "\(Int(average.rounded()))" : "—", "קק״ל", .kcalAmberText)
                        stat("ימים עם תיעוד", "\(loggedDays)", "מתוך 7", .proteinBlueText)
                        stat("משקל", store.latestWeight.map { String(format: "%.1f", $0) } ?? "—", "ק״ג", .fatCoralText)
                    }
                    card("קלוריות ב־7 הימים האחרונים") {
                        Chart {
                            ForEach(week, id: \.date) { day in
                                BarMark(x: .value("יום", day.date, unit: .day), y: .value("קק״ל", day.kcal))
                                    .foregroundStyle(day.kcal > (target ?? .infinity) ? Color.fatCoral : Color.kcalAmber).cornerRadius(6)
                            }
                            if let target { RuleMark(y: .value("יעד", target)).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4])).foregroundStyle(Color.wellnessSecondary)
                                .annotation(position: .bottom, alignment: .leading) { Text("יעד \(Int(target))").font(.caption2).foregroundStyle(Color.wellnessSecondary) } }
                        }
                        .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
                        .frame(height: 180)
                    }
                    card("משקל") {
                        if weights.count < 2 {
                            ContentUnavailableView("עוד אין מספיק נתונים", systemImage: "scalemass", description: Text("הוסף שקילות בהגדרות כדי לראות מגמה."))
                                .frame(height: 180)
                        } else {
                            if let delta { Text(String(format: "%+.1f ק״ג מאז %@", delta, weights.first!.date.formatted(.dateTime.day().month(.abbreviated)))).font(.subheadline).foregroundStyle(Color.wellnessSecondary) }
                            let low = (weights.map(\.kg).min() ?? 0) - 1, high = (weights.map(\.kg).max() ?? 0) + 1
                            Chart(weights, id: \.date) { point in
                                AreaMark(x: .value("תאריך", point.date), yStart: .value("בסיס", low), yEnd: .value("ק״ג", point.kg)).foregroundStyle(LinearGradient(colors: [Color.fatCoral.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom)).interpolationMethod(.catmullRom)
                                LineMark(x: .value("תאריך", point.date), y: .value("ק״ג", point.kg)).foregroundStyle(Color.fatCoral).interpolationMethod(.catmullRom).lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                                PointMark(x: .value("תאריך", point.date), y: .value("ק״ג", point.kg)).foregroundStyle(Color.fatCoral)
                            }
                            .chartYScale(domain: low...high).frame(height: 180)
                        }
                    }
                }.padding(22)
            }.wellnessScreen().toolbar(.hidden, for: .navigationBar).refreshable { await store.refresh() }
        }
    }
    private func stat(_ title: String, _ value: String, _ unit: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.weight(.heavy).monospacedDigit()).foregroundStyle(color)
            Text(unit).font(.caption2).foregroundStyle(Color.wellnessSecondary)
            Text(title).font(.caption).foregroundStyle(Color.wellnessSecondary).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity).padding(.vertical, 14).padding(.horizontal, 4)
            .background(Color.wellnessCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.wellnessHairline))
            .accessibilityElement(children: .combine)
    }
    private func card<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).sectionTitle()
            content().environment(\.layoutDirection, .leftToRight)
        }.frame(maxWidth: .infinity, alignment: .leading).wellnessCard()
    }
}
