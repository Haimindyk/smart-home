import SwiftUI
import WellnessCore

struct TodayScreen: View {
    @EnvironmentObject private var store: AppStore
    @State private var showCalendar = false
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("היום שלך").font(.system(.largeTitle, design: .rounded).bold())
                        Button { showCalendar = true } label: {
                            HStack(spacing: 6) {
                                Text(store.selectedDate, format: .dateTime.month(.wide).year())
                                Image(systemName: "chevron.down").font(.caption)
                            }.foregroundStyle(.secondary)
                        }.frame(minHeight: 44).accessibilityLabel("בחירת תאריך").accessibilityIdentifier("date-picker")
                    }
                    DayRail()
                    CalorieCard()
                    HStack(spacing: 12) {
                        NutrientCard(title: "חלבון", nutrient: "protein", symbol: "fish.fill", color: .blue)
                        NutrientCard(title: "פחמימות", nutrient: "carbs", symbol: "carrot.fill", color: .orange)
                        NutrientCard(title: "שומן", nutrient: "fat", symbol: "drop.fill", color: .pink)
                    }
                    HStack {
                        Text("הארוחות שלך").sectionTitle()
                        Spacer()
                        if store.loading { ProgressView().accessibilityLabel("מעדכן ארוחות") }
                    }.padding(.top, 8)
                    if store.dayMeals.isEmpty {
                        ContentUnavailableView("עוד אין ארוחות ביום הזה", systemImage: "fork.knife", description: Text("הארוחות שלך מהחשבון יופיעו כאן."))
                    } else {
                        ForEach(store.dayMeals) { meal in
                            NavigationLink { MealDetail(meal: meal) } label: { MealCard(meal: meal) }.buttonStyle(PressableStyle()).accessibilityIdentifier("meal-\(meal.id)")
                        }
                    }
                }.padding(22)
            }
            .wellnessScreen()
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await store.refresh() }
            .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { drag in
                // Horizontal swipe turns the day (Hebrew/RTL: swipe left = next day).
                guard abs(drag.translation.width) > 70, abs(drag.translation.width) > abs(drag.translation.height) * 1.6 else { return }
                withAnimation(.snappy) { store.moveDay(drag.translation.width < 0 ? 1 : -1) }
            })
            .sensoryFeedback(.selection, trigger: store.selectedDate)
            .sheet(isPresented: $showCalendar) {
                NavigationStack {
                    DatePicker("תאריך", selection: $store.selectedDate, displayedComponents: .date)
                        .datePickerStyle(.graphical).padding()
                        .environment(\.timeZone, store.timeZone)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("סיום") { showCalendar = false } } }
                }.presentationDetents([.medium])
            }
        }.environment(\.timeZone, store.timeZone)
    }
}

private struct DayRail: View {
    @EnvironmentObject private var store: AppStore
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = store.timeZone; c.firstWeekday = 1; return c }
    private var days: [Date] {
        let start = calendar.startOfDay(for: store.selectedDate)
        let weekday = calendar.component(.weekday, from: start)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0 - weekday + 1, to: start) }
    }
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button { withAnimation(.snappy) { shift(-7) } } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }.accessibilityLabel("שבוע קודם")
                Spacer()
                if !calendar.isDateInToday(store.selectedDate) { Button("היום") { withAnimation(.snappy) { store.selectedDate = Date() } }.font(.caption.bold()).padding(.horizontal, 14).frame(minHeight: 44).background(.white, in: Capsule()).foregroundStyle(Color.wellnessInk) }
                Spacer()
                Button { withAnimation(.snappy) { shift(7) } } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }.accessibilityLabel("שבוע הבא")
            }.foregroundStyle(.secondary)
            HStack(spacing: 5) {
                ForEach(days, id: \.self) { day in
                    let selected = calendar.isDate(day, inSameDayAs: store.selectedDate)
                    Button { withAnimation(.snappy) { store.selectedDate = day } } label: {
                        VStack(spacing: 8) {
                            Text(day, format: .dateTime.weekday(.narrow)).font(.caption).foregroundStyle(selected ? Color.white.opacity(0.7) : .secondary)
                            Text(day, format: .dateTime.day()).font(.system(.title3, design: .rounded).bold().monospacedDigit())
                                .foregroundStyle(selected ? Color.white : Color.wellnessInk)
                            Circle().fill(calendar.isDateInToday(day) ? (selected ? Color.white : Color.orange) : .clear).frame(width: 4, height: 4)
                        }.frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(selected ? Color.wellnessInk : .clear, in: Capsule())
                    }.buttonStyle(.plain)
                    .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }
        }
    }
    private func shift(_ amount: Int) { if let date = calendar.date(byAdding: .day, value: amount, to: store.selectedDate) { store.selectedDate = date } }
}

private struct CalorieCard: View {
    @EnvironmentObject private var store: AppStore
    private var consumed: Double { nutrientTotal(meals: store.dayMeals, nutrient: "kcal") }
    private var target: Double? { store.goal["kcal"].doubleValue }
    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(consumed, format: .number.precision(.fractionLength(0)))
                    .font(.system(size: 52, weight: .bold, design: .rounded)).minimumScaleFactor(0.6)
                    .contentTransition(.numericText(value: consumed))
                    .animation(.snappy, value: consumed)
                Text("קלוריות נאכלו").foregroundStyle(.secondary)
                if let target {
                    let left = Int((target - consumed).rounded())
                    Text(left >= 0 ? "נשארו \(left) מתוך \(Int(target)) קק״ל" : "\(-left) מעל היעד של \(Int(target))")
                        .font(.caption.weight(.medium)).foregroundStyle(left >= 0 ? Color.secondary : Color.red)
                } else { Text("יעד יומי עדיין לא הוגדר").font(.caption).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            ProgressRing(value: consumed, target: target, color: .orange, symbol: "flame.fill", lineWidth: 10, gradient: .flame).frame(width: 104, height: 104)
        }.wellnessCard(padding: 24).accessibilityElement(children: .ignore)
            .accessibilityLabel("קלוריות נאכלו")
            .accessibilityValue("\(Int(consumed.rounded()))\(target.map { " מתוך \(Int($0))" } ?? "")")
            .accessibilityIdentifier("calories-card")
    }
}

private struct NutrientCard: View {
    @EnvironmentObject private var store: AppStore
    let title: String; let nutrient: String; let symbol: String; let color: Color
    var body: some View {
        let value = nutrientTotal(meals: store.dayMeals, nutrient: nutrient)
        let target = store.goal[nutrient].doubleValue
        VStack(spacing: 12) {
            ProgressRing(value: value, target: target, color: color, symbol: symbol).frame(width: 42, height: 42)
            VStack(spacing: 3) {
                Text("\(Int(value.rounded())) ג׳").font(.system(.headline, design: .rounded)).minimumScaleFactor(0.7).contentTransition(.numericText(value: value)).animation(.snappy, value: value)
                Text(title).font(.caption).foregroundStyle(.secondary)
                if let target { Text("מתוך \(Int(target)) ג׳").font(.caption2).foregroundStyle(.secondary) }
            }
        }.frame(maxWidth: .infinity).padding(.vertical, 18).padding(.horizontal, 5)
            .background(.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous)).shadow(color: .black.opacity(0.045), radius: 14, y: 5)
            .accessibilityElement(children: .combine)
    }
}

private struct MealCard: View {
    let meal: HealthRow
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                PrivateMealPhoto(meal: meal, thumbnail: true).frame(width: 60, height: 64).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(mealName(meal)).font(.headline).lineLimit(2)
                    Text(meal.data["items"].arrayValue.compactMap { $0["food"]["name"].stringValue }.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 2)
                Text("\(Int(nutrientTotal(meals: [meal], nutrient: "kcal").rounded()))").font(.title3.bold())
                Text("קק״ל").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                ForEach([("חלבון", "protein"), ("פחמימות", "carbs"), ("שומן", "fat")], id: \.0) { item in
                    Text("\(item.0) \(Int(nutrientTotal(meals: [meal], nutrient: item.1).rounded())) ג׳")
                        .font(.caption2.weight(.medium)).frame(maxWidth: .infinity).padding(.vertical, 7).background(Color.wellnessChip, in: Capsule())
                }
            }
        }.wellnessCard().accessibilityElement(children: .combine)
    }
}

private struct MealDetail: View {
    let meal: HealthRow
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if mealPhotoPath(meal) != nil { PrivateMealPhoto(meal: meal, thumbnail: false).clipShape(RoundedRectangle(cornerRadius: 24)) }
                Text("\(Int(nutrientTotal(meals: [meal], nutrient: "kcal").rounded())) קק״ל").font(.largeTitle.bold())
                VStack(spacing: 0) {
                    ForEach(Array(meal.data["items"].arrayValue.enumerated()), id: \.offset) { _, item in
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item["food"]["name"].stringValue ?? "רכיב").font(.headline)
                                Text("\(Int((item["quantity"].doubleValue ?? 0).rounded())) \(item["food"]["basis"].stringValue == "ml" ? "מ״ל" : "גרם")").foregroundStyle(.secondary)
                            }
                            Spacer()
                            if item["food"]["source"].stringValue == "ai" { Text("הערכה").font(.caption).foregroundStyle(.secondary) }
                        }.padding(.vertical, 16)
                        Divider()
                    }
                }.wellnessCard()
            }.padding(22)
        }.wellnessScreen().navigationTitle(mealName(meal)).navigationBarTitleDisplayMode(.inline)
    }
}

private func mealName(_ meal: HealthRow) -> String {
    let name = meal.data["name"].stringValue ?? ""
    return name.isEmpty ? meal.data["items"].arrayValue.compactMap { $0["food"]["name"].stringValue }.prefix(2).joined(separator: " ו") : name
}

private func mealPhotoPath(_ meal: HealthRow) -> String? {
    meal.data["imagePath"].stringValue ?? meal.data["items"].arrayValue.compactMap { $0["food"]["imagePath"].stringValue }.first
}
private struct PrivateMealPhoto: View {
    @EnvironmentObject private var store: AppStore
    @State private var image: UIImage?
    let meal: HealthRow
    let thumbnail: Bool
    var body: some View {
        Group {
            if let image {
                if thumbnail { Image(uiImage: image).resizable().scaledToFill() }
                else { Image(uiImage: image).resizable().scaledToFit() }
            } else {
                Color.wellnessChip.overlay(Image(systemName: "fork.knife").foregroundStyle(.secondary)).frame(minHeight: thumbnail ? 64 : 160)
            }
        }
        .accessibilityLabel("תמונת הארוחה")
        .task(id: "\(store.session?.owner ?? "")/\(mealPhotoPath(meal) ?? "")") {
            image = nil
            if let path = mealPhotoPath(meal), let data = await store.imageData(path), !Task.isCancelled { image = UIImage(data: data) }
        }
    }
}

extension AppStore {
    /// Moves the selected day by whole days in the store's time zone.
    func moveDay(_ amount: Int) {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        if let date = calendar.date(byAdding: .day, value: amount, to: selectedDate) { selectedDate = date }
    }
}
