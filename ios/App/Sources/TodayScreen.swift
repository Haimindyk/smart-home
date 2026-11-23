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
                    DayRail()
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
                            NavigationLink { MealDetailScreen(initial: meal) } label: { MealCard(meal: meal) }.buttonStyle(PressableStyle())
                                .swipeToConfirmDelete { mealToDelete = meal }
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
                Button("ביטול", role: .cancel) { mealToDelete = nil }
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
    @State private var centered: Date?
    private let cellWidth: CGFloat = 54
    private var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = store.timeZone; c.firstWeekday = 1; return c }
    /// A year back to a month ahead, oldest first (in Hebrew/RTL the oldest day sits on the right).
    private var days: [Date] {
        let today = calendar.startOfDay(for: Date())
        return (-365...30).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
    }
    var body: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 4) {
                    ForEach(days, id: \.self) { day in cell(day).id(day) }
                }.scrollTargetLayout()
            }
            .contentMargins(.horizontal, max(0, (geo.size.width - cellWidth) / 2), for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $centered, anchor: .center)
            .onAppear { centered = calendar.startOfDay(for: store.selectedDate) }
            .onChange(of: centered) { _, day in
                guard let day, !calendar.isDate(day, inSameDayAs: store.selectedDate) else { return }
                store.selectedDate = day
            }
            .onChange(of: store.selectedDate) { _, date in
                let day = calendar.startOfDay(for: date)
                if centered != day { withAnimation(.snappy) { centered = day } }
            }
        }
        .frame(height: 72)
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12), .init(color: .black, location: 0.88), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
        .accessibilityElement(children: .contain).accessibilityLabel("בחירת יום")
    }
    private func cell(_ day: Date) -> some View {
        let selected = calendar.isDate(day, inSameDayAs: store.selectedDate)
        let future = day > Date() && !calendar.isDateInToday(day)
        return Button { withAnimation(.snappy) { centered = day } } label: {
            VStack(spacing: 4) {
                Text(day, format: .dateTime.weekday(.narrow)).font(.hb(.caption)).foregroundStyle(future ? Color.primary.opacity(0.5) : Color.wellnessSecondary)
                Text(day, format: .dateTime.day()).font(.hb(.headline, .semibold)).monospacedDigit()
                    .foregroundStyle(future ? Color.primary.opacity(0.5) : Color.wellnessInk).lineLimit(1)
                Circle().fill(calendar.isDateInToday(day) ? Color.kcalAmber : .clear).frame(width: 4, height: 4)
            }.frame(width: cellWidth).padding(.vertical, 6)
                .background { if selected { RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.wellnessInk, lineWidth: 1.5) } }
        }.buttonStyle(.plain)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
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
    @ScaledMetric(relativeTo: .body) private var macroHeight: CGFloat = 144
    @ScaledMetric(relativeTo: .body) private var activityHeight: CGFloat = 332
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
                ActivityPage().padding(.top, 4).padding(.bottom, 16).tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never)).frame(height: page == 0 ? macroHeight : activityHeight)
            .animation(.snappy, value: page)
            .sensoryFeedback(.selection, trigger: page)
            HStack(spacing: 7) {
                ForEach(0..<2, id: \.self) { index in
                    Capsule().fill(index == page ? Color.wellnessInk : Color.primary.opacity(0.18))
                        .frame(width: index == page ? 22 : 7, height: 7)
                }
            }.animation(.snappy, value: page).environment(\.layoutDirection, .rightToLeft).accessibilityHidden(true)
        }
        .task { await store.loadTodayActivity() }
    }
}

/// Second carousel page: steps and burned calories side by side, with the water card underneath (as in the web app).
private struct ActivityPage: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatTile(title: "צעדים", value: store.steps.map { Int($0.rounded()) }, unit: "/ 10,000", ring: (store.steps ?? 0, 10_000, Color.wellnessInk, "figure.walk"))
                StatTile(title: "קלוריות שנשרפו", value: store.burnedKcal.map { Int($0.rounded()) }, unit: "קלוריות", ring: (store.burnedKcal ?? 0, nil, Color.kcalAmber, "flame.fill"))
            }
            WaterCard()
            LinkChips()
        }
    }
}

/// Where the numbers come from: Apple Health (steps, active calories) and the paired Apple Watch.
private struct LinkChips: View {
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var watch = PhoneConnectivity.shared
    @Environment(\.openURL) private var openURL
    private var healthConnected: Bool { store.steps != nil || store.burnedKcal != nil }
    var body: some View {
        HStack(spacing: 10) {
            if healthConnected {
                chip("heart.fill", "Apple Health", "מחובר", on: true, color: .fatCoral)
            } else {
                Button {
                    Task { await store.loadTodayActivity() }
                    if let url = URL(string: "x-apple-health://") { openURL(url) }
                } label: { chip("heart.fill", "Apple Health", "חיבור", on: false, color: .fatCoral) }
                    .buttonStyle(PressableStyle()).accessibilityIdentifier("connect-health").accessibilityHint("פותח את אפליקציית הבריאות כדי לאשר גישה")
            }
            switch watch.link {
            case .installed: chip("applewatch", "Apple Watch", "מחובר", on: true, color: .proteinBlue)
            case .paired: chip("applewatch", "Apple Watch", "האפליקציה לא מותקנת בשעון", on: false, color: .proteinBlue)
            case .none, .unsupported: chip("applewatch", "Apple Watch", "לא מזווג", on: false, color: .proteinBlue)
            }
        }.frame(maxWidth: .infinity)
    }
    private func chip(_ symbol: String, _ name: String, _ status: String, on: Bool, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(on ? color : Color.wellnessSecondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(name).font(.hb(.caption, .semibold)).foregroundStyle(Color.wellnessInk)
                Text(status).font(.hb(.caption2)).foregroundStyle(on ? Color.proteinBlue : Color.wellnessSecondary).lineLimit(1).minimumScaleFactor(0.8)
            }
            Circle().fill(on ? Color.green : Color.primary.opacity(0.25)).frame(width: 7, height: 7)
        }
        .padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.wellnessCard, in: Capsule()).overlay(Capsule().strokeBorder(Color.wellnessHairline))
        .accessibilityElement(children: .combine)
    }
}

private struct StatTile: View {
    let title: String
    let value: Int?
    let unit: String
    let ring: (value: Double, target: Double?, color: Color, symbol: String)
    @ScaledMetric(relativeTo: .title) private var number: CGFloat = 30
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.hb(.subheadline)).foregroundStyle(Color.wellnessSecondary).lineLimit(1).minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value.map { $0.formatted() } ?? "—").font(.hbFixed(number, .heavy)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                Text(unit).font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            HStack { Spacer(); ProgressRing(value: ring.value, target: ring.target, color: ring.color, symbol: ring.symbol, lineWidth: 4).frame(width: 44, height: 44) }
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading).wellnessCard(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

private struct WaterCard: View {
    @EnvironmentObject private var store: AppStore
    @ScaledMetric(relativeTo: .title) private var waterNumber: CGFloat = 32
    var body: some View {
        let total = store.dayWater, target = store.waterTarget
        HStack(spacing: 14) {
            ProgressRing(value: total, target: target, color: .proteinBlue, symbol: "drop.fill", lineWidth: 7).frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text("מים").font(.hb(.subheadline)).foregroundStyle(Color.wellnessSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(Int(total), format: .number).font(.hbFixed(waterNumber, .heavy)).monospacedDigit().contentTransition(.numericText(value: total))
                    Text("/ \(Int(target)) מ״ל").font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary).lineLimit(1).minimumScaleFactor(0.8)
                }.animation(.snappy, value: total)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button { Task { await store.undoWater() } } label: { Image(systemName: "minus").font(.system(size: 16, weight: .semibold)).frame(width: 44, height: 44).background(Color.wellnessChip, in: Circle()).overlay(Circle().strokeBorder(Color.wellnessHairline)).foregroundStyle(Color.wellnessInk) }
                .buttonStyle(PressableStyle()).disabled(store.dayWaterLogs.isEmpty).accessibilityLabel("ביטול הכוס האחרונה")
            Button { Task { await store.addWater(250) } } label: { Image(systemName: "plus").font(.system(size: 16, weight: .semibold)).frame(width: 44, height: 44).background(Color.proteinBlue.opacity(0.14), in: Circle()).overlay(Circle().strokeBorder(Color.proteinBlue.opacity(0.5))).foregroundStyle(Color.proteinBlue) }
                .buttonStyle(PressableStyle()).accessibilityLabel("הוסף 250 מיליליטר מים")
        }.wellnessCard(padding: 14).sensoryFeedback(.impact(weight: .medium), trigger: store.dayWaterLogs.count)
            .accessibilityElement(children: .contain)
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

func mealName(_ meal: HealthRow) -> String {
    let name = meal.data["name"].stringValue ?? ""
    return name.isEmpty ? meal.data["items"].arrayValue.compactMap { $0["food"]["name"].stringValue }.prefix(2).joined(separator: " ו") : name
}

func mealPhotoPath(_ meal: HealthRow) -> String? {
    meal.data["imagePath"].stringValue ?? meal.data["items"].arrayValue.compactMap { $0["food"]["imagePath"].stringValue }.first
}
struct PrivateMealPhoto: View {
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
