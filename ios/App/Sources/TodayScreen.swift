import SwiftUI
import WellnessCore

struct TodayScreen: View {
    @EnvironmentObject private var store: AppStore
    @State private var showCalendar = false
    @State private var mealToDelete: HealthRow?
    @State private var showSettings = false
    @State private var showCoach = false
    @State private var addingMeal = false
    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("היום שלך").font(.hb(.title, .bold))
                        HStack(spacing: 10) {
                            Button { showCalendar = true } label: {
                                HStack(spacing: 6) {
                                    Text(store.selectedDate, format: .dateTime.month(.wide).year())
                                    Image(systemName: "chevron.down").font(.hb(.caption))
                                }.foregroundStyle(Color.wellnessSecondary)
                            }.frame(minHeight: 36).accessibilityLabel("בחירת תאריך").accessibilityIdentifier("date-picker")
                            if !Calendar.current.isDateInToday(store.selectedDate) {
                                Button("היום") { withAnimation(.snappy) { store.selectedDate = Date() } }.font(.hb(.caption, .bold)).padding(.horizontal, 12).frame(minHeight: 32).background(Color.wellnessCard, in: Capsule()).overlay(Capsule().strokeBorder(Color.wellnessHairline)).foregroundStyle(Color.wellnessInk).accessibilityIdentifier("today-button")
                            }
                        }
                    }
                        Spacer()
                        Button { showCoach = true } label: {
                            Image(systemName: "sparkles").font(.hb(.headline)).foregroundStyle(.flame).frame(width: 44, height: 44)
                                .background(Color.wellnessCard, in: Circle()).overlay(Circle().strokeBorder(Color.wellnessHairline))
                        }.buttonStyle(PressableStyle()).accessibilityLabel("המאמן שלי").accessibilityIdentifier("coach-button")
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape.fill").font(.hb(.headline)).foregroundStyle(Color.wellnessInk).frame(width: 44, height: 44)
                                .background(Color.wellnessCard, in: Circle()).overlay(Circle().strokeBorder(Color.wellnessHairline))
                        }.buttonStyle(PressableStyle()).accessibilityLabel("הגדרות").accessibilityIdentifier("settings-button")
                    }
                    DayRail().daySwipe(store)
                    CalorieCard().daySwipe(store)
                    SummaryCarousel()
                    HStack {
                        Text("הארוחות שלך").sectionTitle()
                        Spacer()
                        if store.loading { ProgressView().accessibilityLabel("מעדכן ארוחות") }
                    }.padding(.top, 8)
                    if store.dayMeals.isEmpty {
                        ContentUnavailableView {
                            Label("עוד אין ארוחות ביום הזה", systemImage: "fork.knife")
                        } description: {
                            Text("הוסף ארוחה כדי לעקוב אחרי הקלוריות והמאקרו.")
                        } actions: {
                            Button { addingMeal = true } label: { Label("הוסף ארוחה", systemImage: "plus") }.buttonStyle(.borderedProminent).tint(Color.wellnessPrimary).accessibilityIdentifier("empty-add-meal")
                        }
                    } else {
                        ForEach(store.dayMeals) { meal in
                            NavigationLink { MealDetail(initial: meal) } label: { MealCard(meal: meal) }.buttonStyle(PressableStyle())
                                .contextMenu { Button(role: .destructive) { mealToDelete = meal } label: { Label("מחיקת הארוחה", systemImage: "trash") } }.accessibilityIdentifier("meal-\(meal.id)")
                        }
                    }
                }.padding(16).shimmer(store.loading && store.meals.isEmpty && store.goals.isEmpty)
            }
            .wellnessScreen()
            .safeAreaInset(edge: .top, spacing: 0) { HealthTabBar() }
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await store.refresh() }
            .sensoryFeedback(.selection, trigger: store.selectedDate)
            .confirmationDialog("למחוק את הארוחה?", isPresented: Binding(get: { mealToDelete != nil }, set: { if !$0 { mealToDelete = nil } }), titleVisibility: .visible) {
                Button("מחיקה", role: .destructive) { if let meal = mealToDelete { Task { _ = await store.deleteMeal(meal) } }; mealToDelete = nil }
            }
            .sheet(isPresented: $addingMeal) { AddMealSheet().environmentObject(store).presentationDragIndicator(.visible) }
            .sheet(isPresented: $showCoach) { CoachChatView().environmentObject(store) }
            .sheet(isPresented: $showSettings) { SettingsScreen(isSheet: true).environmentObject(store) }
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
        HStack(spacing: 0) {
            Button { withAnimation(.snappy) { shift(-7) } } label: { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).frame(width: 28, height: 56) }.accessibilityLabel("שבוע קודם")
            ViewThatFits(in: .horizontal) {
                dayCells(scrolling: false)
                ScrollView(.horizontal, showsIndicators: false) { dayCells(scrolling: true) }
            }
            Button { withAnimation(.snappy) { shift(7) } } label: { Image(systemName: "chevron.left").font(.footnote.weight(.semibold)).frame(width: 28, height: 56) }.accessibilityLabel("שבוע הבא")
        }.foregroundStyle(Color.wellnessSecondary)
    }
    @ViewBuilder private func dayCells(scrolling: Bool) -> some View {
        HStack(spacing: 5) {
                ForEach(days, id: \.self) { day in
                    let selected = calendar.isDate(day, inSameDayAs: store.selectedDate)
                    let future = day > Date() && !calendar.isDateInToday(day)
                    Button { withAnimation(.snappy) { store.selectedDate = day } } label: {
                        VStack(spacing: 4) {
                            Text(day, format: .dateTime.weekday(.narrow)).font(.hb(.caption)).foregroundStyle(future ? Color.primary.opacity(0.5) : Color.wellnessSecondary)
                            Text(day, format: .dateTime.day()).font(.hb(.headline, .semibold)).monospacedDigit()
                                .foregroundStyle(future ? Color.primary.opacity(0.5) : Color.wellnessInk).lineLimit(1)
                            Circle().fill(calendar.isDateInToday(day) ? Color.kcalAmber : .clear).frame(width: 4, height: 4)
                        }.frame(maxWidth: scrolling ? nil : .infinity).frame(minWidth: scrolling ? 56 : 0).padding(.vertical, 6)
                            .background { if selected { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.wellnessInk, lineWidth: 1.5) } }
                    }.buttonStyle(.plain)
                    .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .accessibilityAddTraits(selected ? [.isSelected] : [])
                }
            }

    }

    private func shift(_ amount: Int) { if let date = calendar.date(byAdding: .day, value: amount, to: store.selectedDate) { store.selectedDate = date } }
}

private struct CalorieCard: View {
    @EnvironmentObject private var store: AppStore
    @ScaledMetric(relativeTo: .largeTitle) private var bigNumber: CGFloat = 40
    private var consumed: Double { nutrientTotal(meals: store.dayMeals, nutrient: "kcal") }
    private var target: Double? { store.goal["kcal"].doubleValue }
    var body: some View {
        let remaining = target.map { $0 - consumed }
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(remaining.map { max(0, $0) } ?? consumed, format: .number.precision(.fractionLength(0)))
                    .font(.hbFixed(bigNumber, .heavy)).minimumScaleFactor(0.6)
                    .contentTransition(.numericText(value: remaining ?? consumed))
                    .animation(.snappy, value: consumed)
                Text(remaining == nil ? "קלוריות נאכלו" : "קלוריות נותרו").font(.hb(.subheadline)).foregroundStyle(Color.wellnessSecondary).lineLimit(2).minimumScaleFactor(0.7)
                if let target {
                    if let remaining, remaining < 0 {
                        Text("חרגת ב־\(Int((-remaining).rounded())) קק״ל").font(.hb(.caption, .semibold)).foregroundStyle(Color.kcalAmberText)
                    } else {
                        Text("נאכלו \(Int(consumed.rounded())) מתוך \(Int(target))").font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary)
                    }
                } else { Text("יעד יומי עדיין לא הוגדר").font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            ProgressRing(value: consumed, target: target, color: .kcalAmber, symbol: "flame.fill", lineWidth: 8).frame(width: 72, height: 72)
        }.wellnessCard(padding: 16).accessibilityElement(children: .ignore)
            .accessibilityLabel("קלוריות נאכלו")
            .accessibilityValue("\(Int(consumed.rounded()))\(target.map { " מתוך \(Int($0))" } ?? "")")
            .accessibilityIdentifier("calories-card")
    }
}

/// Two swipeable pages (macros, activity) with page dots, like the web app's summary cards.
private struct SummaryCarousel: View {
    @EnvironmentObject private var store: AppStore
    @State private var page = 0
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 128
    private var hasActivity: Bool { store.steps != nil }
    @ViewBuilder private var macroCards: some View {
        NutrientCard(title: "חלבון", nutrient: "protein", symbol: "fish.fill", color: .proteinBlue)
        NutrientCard(title: "פחמימות", nutrient: "carbs", symbol: "carrot.fill", color: .carbsGold)
        NutrientCard(title: "שומן", nutrient: "fat", symbol: "drop.fill", color: .fatCoral)
    }
    var body: some View {
        VStack(spacing: 14) {
            TabView(selection: $page) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { macroCards }
                    ScrollView { VStack(spacing: 10) { macroCards } }
                }.padding(.top, 4).padding(.bottom, 16).tag(0)
                WaterCard().padding(.top, 4).padding(.bottom, 16).tag(1)
                if hasActivity { StepsCard().padding(.top, 4).padding(.bottom, 16).tag(2) }
            }
            .tabViewStyle(.page(indexDisplayMode: .never)).frame(height: height + 16)
            .sensoryFeedback(.selection, trigger: page)
            HStack(spacing: 7) {
                    ForEach(0..<(hasActivity ? 3 : 2), id: \.self) { index in
                        Capsule().fill(index == page ? Color.wellnessInk : Color.primary.opacity(0.18))
                            .frame(width: index == page ? 22 : 7, height: 7)
                    }
                }.animation(.snappy, value: page).environment(\.layoutDirection, .rightToLeft).accessibilityHidden(true)
        }
    }
}

private struct WaterCard: View {
    @EnvironmentObject private var store: AppStore
    @ScaledMetric(relativeTo: .title) private var waterNumber: CGFloat = 38
    var body: some View {
        let total = store.dayWater, target = store.waterTarget
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("מים").font(.hb(.subheadline)).foregroundStyle(Color.wellnessSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Int(total), format: .number).font(.hbFixed(waterNumber, .heavy)).monospacedDigit().contentTransition(.numericText(value: total))
                    Text("/ \(Int(target)) מ״ל").font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary)
                }.animation(.snappy, value: total)
                HStack(spacing: 10) {
                    Button { Task { await store.addWater(250) } } label: { Label("250", systemImage: "plus").font(.hb(.subheadline, .semibold)).padding(.horizontal, 14).frame(height: 40).background(Color.proteinBlue.opacity(0.14), in: Capsule()).foregroundStyle(Color.proteinBlueText) }
                        .buttonStyle(PressableStyle()).accessibilityLabel("הוסף 250 מיליליטר מים")
                    Button { Task { await store.undoWater() } } label: { Image(systemName: "arrow.uturn.backward").frame(width: 40, height: 40).background(Color.wellnessChip, in: Circle()).foregroundStyle(Color.wellnessInk) }
                        .buttonStyle(PressableStyle()).disabled(store.dayWaterLogs.isEmpty).accessibilityLabel("ביטול הכוס האחרונה")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            ProgressRing(value: total, target: target, color: .proteinBlue, symbol: "drop.fill", lineWidth: 8).frame(width: 84, height: 84)
        }.wellnessCard().sensoryFeedback(.impact(weight: .medium), trigger: store.dayWaterLogs.count)
            .accessibilityElement(children: .contain)
    }
}

private struct StepsCard: View {
    @EnvironmentObject private var store: AppStore
    @ScaledMetric(relativeTo: .title) private var stepsNumber: CGFloat = 40
    var body: some View {
        let steps = store.steps ?? 0
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("צעדים").font(.hb(.subheadline)).foregroundStyle(Color.wellnessSecondary)
                Text(steps, format: .number.precision(.fractionLength(0))).font(.hbFixed(stepsNumber, .heavy)).monospacedDigit()
                Text("היום · Apple Health").font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            ProgressRing(value: steps, target: 10_000, color: .wellnessInk, symbol: "figure.walk", lineWidth: 8).frame(width: 84, height: 84)
        }.wellnessCard().accessibilityElement(children: .combine)
    }
}

private struct NutrientCard: View {
    @EnvironmentObject private var store: AppStore
    let title: String; let nutrient: String; let symbol: String; let color: Color
    var body: some View {
        let value = nutrientTotal(meals: store.dayMeals, nutrient: nutrient)
        let target = store.goal[nutrient].doubleValue
        let left = target.map { $0 - value }
        VStack(spacing: 6) {
            ProgressRing(value: value, target: target, color: color, symbol: symbol, lineWidth: 4).frame(width: 36, height: 36)
            VStack(spacing: 3) {
                Text("\(Int(value.rounded())) ג׳").font(.hb(.headline, .bold))
                    .contentTransition(.numericText(value: value)).animation(.snappy, value: value)
                Text(title).font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary)
                if let left {
                    Text(left >= 0 ? "נותרו \(Int(left.rounded())) ג׳" : "חרגת ב־\(Int((-left).rounded())) ג׳")
                        .font(.hb(.caption2, .medium)).foregroundStyle(left >= 0 ? Color.wellnessSecondary : Color.kcalAmberText)
                }
            }
        }.frame(maxWidth: .infinity).padding(.vertical, 12).padding(.horizontal, 5)
            .background(Color.wellnessCard, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.wellnessHairline))
            .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
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
                    Text(mealName(meal)).font(.hb(.headline, .semibold)).lineLimit(2)
                    Text(meal.data["items"].arrayValue.compactMap { $0["food"]["name"].stringValue }.joined(separator: " · ")).font(.hb(.subheadline)).foregroundStyle(Color.wellnessSecondary).lineLimit(2)
                }
                Spacer(minLength: 2)
                Text("\(Int(nutrientTotal(meals: [meal], nutrient: "kcal").rounded()))").font(.hb(.title3, .bold))
                Text("קק״ל").font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary)
            }
            HStack {
                ForEach([("חלבון", "protein", "fish.fill", Color.proteinBlue), ("פחמימות", "carbs", "carrot.fill", Color.carbsGold), ("שומן", "fat", "drop.fill", Color.fatCoral)], id: \.0) { item in
                    HStack(spacing: 5) {
                        Text("\(Int(nutrientTotal(meals: [meal], nutrient: item.1).rounded())) ג׳")
                        Image(systemName: item.2).foregroundStyle(item.3)
                    }.font(.hb(.caption, .medium)).frame(maxWidth: .infinity).padding(.vertical, 8).background(Color.wellnessChip, in: Capsule())
                        .accessibilityLabel("\(item.0) \(Int(nutrientTotal(meals: [meal], nutrient: item.1).rounded())) גרם")
                }
            }
        }.wellnessCard().accessibilityElement(children: .combine)
    }
}

private struct MealDetail: View {
    @EnvironmentObject private var store: AppStore
    let initial: HealthRow
    @State private var editing = false
    private var meal: HealthRow { store.meals.first { $0.id == initial.id } ?? initial }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if mealPhotoPath(meal) != nil { PrivateMealPhoto(meal: meal, thumbnail: false).clipShape(RoundedRectangle(cornerRadius: 24)) }
                Text("\(Int(nutrientTotal(meals: [meal], nutrient: "kcal").rounded())) קק״ל").font(.hb(.largeTitle, .bold))
                VStack(spacing: 0) {
                    let items = meal.data["items"].arrayValue
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item["food"]["name"].stringValue ?? "רכיב").font(.hb(.headline, .semibold))
                                Text("\(Int((item["quantity"].doubleValue ?? 0).rounded())) \(item["food"]["basis"].stringValue == "ml" ? "מ״ל" : "גרם")").foregroundStyle(Color.wellnessSecondary)
                            }
                            Spacer()
                            if item["food"]["source"].stringValue == "ai" { Text("הערכה").font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary).padding(.trailing, 8) }
                            let kcal = (item["food"]["per100"]["kcal"].doubleValue ?? 0) * (item["quantity"].doubleValue ?? 0) / 100
                            if kcal > 0 { Text("\(Int(kcal.rounded())) קק״ל").font(.hb(.subheadline, .semibold)).foregroundStyle(Color.kcalAmberText) }
                        }.padding(.vertical, 16)
                        if index < items.count - 1 { Divider() }
                    }
                }.wellnessCard()
            }.padding(16)
        }.wellnessScreen().navigationTitle(mealName(meal)).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("עריכה") { editing = true }.accessibilityIdentifier("edit-meal") } }
            .sheet(isPresented: $editing) { EditMealSheet(meal: meal).environmentObject(store) }
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
                Color.wellnessChip.overlay(Image(systemName: "fork.knife").foregroundStyle(Color.wellnessSecondary)).frame(minHeight: thumbnail ? 64 : 160)
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
