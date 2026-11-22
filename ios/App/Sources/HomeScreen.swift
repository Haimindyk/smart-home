import SwiftUI
import WellnessCore

struct MemberAvatar: View {
    let member: HMember?
    var size: CGFloat = 36
    var body: some View {
        let tint = Color(hex: member?.color ?? "#888888")
        ZStack {
            Text(member?.emoji ?? String(member?.name.prefix(1) ?? "?")).font(.system(size: size * 0.5))
            if let url = member?.photoURL {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase { image.resizable().scaledToFill() } else { Color.clear }
                }
            }
        }
        .frame(width: size, height: size).background(tint.opacity(0.22), in: Circle()).clipShape(Circle())
        .overlay(Circle().strokeBorder(tint.opacity(0.5), lineWidth: 1.5))
        .accessibilityLabel(member?.name ?? "")
    }
}

/// Avatar button that opens a dropdown list of household members (photo + name) to choose who is responsible.
struct AssigneeButton: View {
    @EnvironmentObject private var home: HomeStore
    let currentID: String?
    var size: CGFloat = 36
    /// Everyone responsible (tasks can have several); the first one is the "current" pick in the dropdown.
    var ids: [String] = []
    /// Tinted capsule with the person's photo and name (the web app's assignee badge) instead of a bare avatar.
    var badge = false
    let onPick: (String?) -> Void
    @State private var open = false
    private var people: [HMember] { (ids.isEmpty ? [currentID].compactMap { $0 } : ids).compactMap { home.member($0) } }
    var body: some View {
        Button { open = true } label: {
            Group {
                if badge, people.count == 1, let m = people.first {
                    HStack(spacing: 6) {
                        MemberAvatar(member: m, size: 24)
                        Text(m.name).font(.hb(.caption, .semibold)).foregroundStyle(Color.wellnessInk).lineLimit(1)
                    }.padding(.leading, 3).padding(.trailing, 10).frame(height: 30)
                        .background(Color(hex: m.color).opacity(0.16), in: Capsule())
                } else if badge, people.count > 1 {
                    HStack(spacing: -8) {
                        ForEach(people.prefix(3)) { m in MemberAvatar(member: m, size: 26).overlay(Circle().strokeBorder(Color.wellnessCard, lineWidth: 2)) }
                        if people.count > 3 { Text("+\(people.count - 3)").font(.hb(.caption2, .bold)).frame(width: 26, height: 26).background(Color.wellnessChip, in: Circle()).overlay(Circle().strokeBorder(Color.wellnessCard, lineWidth: 2)) }
                    }
                } else if let m = home.member(currentID) { MemberAvatar(member: m, size: size) }
                else { Image(systemName: "person.badge.plus").font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(Color.wellnessSecondary).frame(width: size, height: size).background(Color.wellnessChip, in: Circle()).overlay(Circle().strokeBorder(Color.wellnessHairline, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))) }
            }.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle()).accessibilityLabel(people.isEmpty ? "הגדרת אחראי" : "אחראי: " + people.map(\.name).joined(separator: ", ") + ". לחיצה לשינוי")
        .popover(isPresented: $open) {
            VStack(spacing: 0) {
                ForEach(home.members) { m in row(m.id, name: m.name, member: m) }
                Divider()
                row(nil, name: "ללא אחראי", member: nil)
            }.padding(.vertical, 6).frame(minWidth: 240).presentationCompactAdaptation(.popover)
        }
    }
    private func row(_ id: String?, name: String, member: HMember?) -> some View {
        Button { open = false; onPick(id) } label: {
            HStack(spacing: 12) {
                if let member { MemberAvatar(member: member, size: 34) } else { Image(systemName: "person.slash").frame(width: 34, height: 34).foregroundStyle(Color.wellnessSecondary) }
                Text(name).font(.hb(.body)).foregroundStyle(Color.wellnessInk)
                Spacer(minLength: 16)
                if id == currentID { Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(Color.wellnessInk) }
            }.padding(.horizontal, 16).frame(minHeight: 48).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("assignee-option-\(id ?? "none")")
    }
}
extension Color {
    init(hex: String) {
        var h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")); if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        var v: UInt64 = 0; Scanner(string: h).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
    }
}

enum HomeSheet: Identifiable {
    case search, newSection, editSection(HSection), history, members
    var id: String { switch self { case .search: "search"; case .newSection: "new"; case .editSection(let s): "edit-\(s.id)"; case .history: "history"; case .members: "members" } }
}

private struct PanelOffsetKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) { value.merge(nextValue()) { $1 } }
}

extension HSection {
    var kindColor: Color { switch kind { case "shopping": .kindShopping; case "chores": .kindChores; case "info": .kindInfo; default: .kindTasks } }
    var kindIcon: String { switch kind { case "shopping": "cart.fill"; case "chores": "arrow.triangle.2.circlepath"; case "info": "note.text"; default: "checklist" } }
}

/// The household dashboard: one scrolling page of section panels (like the web app), with a glass header and a pill of section tabs.
struct HomeScreen: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var home: HomeStore
    @State private var showSettings = false
    @State private var showAssistant = false
    @State private var showProfile = false
    @State private var broadcasting = false
    @State private var broadcastText = ""
    @State private var sheet: HomeSheet?
    @State private var jumping = false
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour < 5 ? "לילה טוב" : hour < 12 ? "בוקר טוב" : hour < 18 ? "צהריים טובים" : hour < 22 ? "ערב טוב" : "לילה טוב"
    }
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 16) {
                        hero
                        wellnessCard
                        AssistantCards()
                        if home.sections.isEmpty && !home.loading { ContentUnavailableView { Label("אין עדיין מדורים", systemImage: "square.grid.2x2") } description: { Text("מדורים מארגנים את הבית: קניות, משימות, תחזוקה ועוד.") } actions: { Button { sheet = .newSection } label: { Label("מדור חדש", systemImage: "plus") }.buttonStyle(.borderedProminent).tint(Color.wellnessPrimary) } }
                        ForEach(home.sections) { SectionPanel(section: $0).id($0.id) }
                        Color.clear.frame(height: 110)
                    }.padding(.horizontal, 16).padding(.top, 6).shimmer(home.loading && home.sections.isEmpty)
                }
                .scrollDismissesKeyboard(.interactively)
                .coordinateSpace(name: "home-scroll")
                .onPreferenceChange(PanelOffsetKey.self) { offsets in
                    guard !jumping, let best = offsets.filter({ $0.value <= 160 }).max(by: { $0.value < $1.value }) ?? offsets.min(by: { $0.value < $1.value }) else { return }
                    if home.selectedSectionID != best.key { home.selectedSectionID = best.key }
                }
                .safeAreaInset(edge: .top, spacing: 0) { chrome(proxy) }
                .refreshable { await home.refresh() }
            }
            .wellnessScreen().toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) { SettingsScreen(isSheet: true).environmentObject(store) }
            .alert("הודעה לכל הבית", isPresented: $broadcasting) {
                TextField("מה לכתוב?", text: $broadcastText)
                Button("שליחה") { let text = broadcastText; broadcastText = ""; Task { _ = await home.sendBroadcast(text) } }
                Button("ביטול", role: .cancel) { broadcastText = "" }
            } message: { Text("ההודעה תופיע בהיסטוריה ותישלח כהתראה לבני הבית.") }
            .sheet(isPresented: $showProfile) { ProfileEditorSheet().environmentObject(home) }
            .sheet(isPresented: $showAssistant) { AssistantSheet().environmentObject(store).environmentObject(home) }
            .sheet(item: $sheet) { which in
                switch which {
                case .search: SearchSheet().environmentObject(home)
                case .newSection: SectionEditorSheet(section: nil).environmentObject(home)
                case .editSection(let section): SectionEditorSheet(section: section).environmentObject(home)
                case .history: HistorySheet().environmentObject(home)
                case .members: MembersSheet().environmentObject(home)
                }
            }
            .errorBanner($home.error)
        }
    }

    // MARK: Wellness entry (the web app's personal space card)
    private var wellnessCard: some View {
        Button { home.openHealthRequested = true } label: {
            HStack(spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    Circle().fill(Color.wellnessPrimary.opacity(0.12)).overlay(Circle().strokeBorder(Color.wellnessPrimary.opacity(0.3))).frame(width: 44, height: 44)
                        .overlay(Image(systemName: "leaf").font(.headline).foregroundStyle(Color.wellnessPrimary))
                    Image(systemName: "dumbbell.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(Color.wellnessOnPrimary).frame(width: 20, height: 20).background(Color.wellnessPrimary, in: Circle()).offset(x: 3, y: 3)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("KH WELLNESS").font(.hb(.caption2, .semibold)).tracking(2).foregroundStyle(Color.amberInk)
                    Text("זמן לעצמך").font(.hb(.headline, .bold)).foregroundStyle(Color.wellnessInk)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.backward").font(.footnote.weight(.bold)).foregroundStyle(Color.wellnessSecondary)
            }.wellnessCard(padding: 12)
        }.buttonStyle(PressableStyle()).accessibilityIdentifier("wellness-entry").accessibilityElement(children: .combine).accessibilityHint("פותח את המרחב האישי")
    }

    // MARK: Hero
    private var hero: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("הבית").font(.hb(.caption2, .semibold)).tracking(2.2).foregroundStyle(Color.wellnessPrimary)
                (Text("\(greeting)").foregroundStyle(Color.wellnessInk) + Text(home.me.map { ", " + $0.name } ?? "").foregroundStyle(Color.amberInk))
                    .font(.hb(.title2, .bold)).tracking(-0.4).lineLimit(1).minimumScaleFactor(0.8)
                Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide)).font(.hb(.footnote)).foregroundStyle(Color.wellnessSecondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button { sheet = .newSection } label: {
                Label("קטגוריה", systemImage: "plus").font(.hb(.subheadline, .semibold)).padding(.horizontal, 14).frame(minHeight: 40)
                    .foregroundStyle(Color.wellnessOnPrimary).background(Color.wellnessPrimary, in: Capsule())
            }.buttonStyle(PressableStyle()).accessibilityLabel("קטגוריה חדשה").accessibilityIdentifier("hero-new-section")
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.wellnessCard)
                .overlay(RadialGradient(colors: [Color.wellnessPrimary.opacity(0.09), .clear], center: UnitPoint(x: 1, y: -0.1), startRadius: 0, endRadius: 260).clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous)))
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.wellnessHairline))
                .shadow(color: .black.opacity(0.05), radius: 1, y: 1).shadow(color: .black.opacity(0.08), radius: 10, y: 5)
        }
    }

    // MARK: Sticky chrome (header + section pill)
    private func chrome(_ proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 4) {
                Image(systemName: "house.fill").font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.amberInk).frame(width: 36, height: 36)
                    .background(Color.amberTint, in: RoundedRectangle(cornerRadius: 12, style: .continuous)).accessibilityHidden(true)
                Text("הבית").font(.hb(.title3, .bold)).padding(.leading, 6)
                Spacer()
                Menu {
                    Button { showProfile = true } label: { Label("הפרופיל שלי", systemImage: "person.crop.circle") }
                    Button { sheet = .members } label: { Label("בני הבית", systemImage: "person.2") }
                    Button { broadcasting = true } label: { Label("הודעה לכל הבית", systemImage: "megaphone") }
                    Button { showSettings = true } label: { Label("הגדרות", systemImage: "gearshape") }
                } label: {
                    HStack(spacing: 4) { MemberAvatar(member: home.me, size: 32); Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(Color.wellnessSecondary) }
                        .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }.accessibilityLabel("החשבון שלי").accessibilityIdentifier("home-account")
                iconButton("magnifyingglass", label: "חיפוש", id: "home-search") { sheet = .search }
                iconButton("sparkles", label: "העוזר של הבית", id: "assistant-button") { showAssistant = true }
                Menu {
                    Button { sheet = .newSection } label: { Label("מדור חדש", systemImage: "plus.rectangle.on.rectangle") }
                    if let current = home.currentSection { Button { sheet = .editSection(current) } label: { Label("עריכת המדור", systemImage: "pencil") } }
                    Button { sheet = .history } label: { Label("היסטוריה", systemImage: "clock.arrow.circlepath") }
                    Button { sheet = .members } label: { Label("בני הבית", systemImage: "person.2") }
                    Divider()
                    Button { showSettings = true } label: { Label("הגדרות", systemImage: "gearshape") }
                } label: { Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.wellnessInk).frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .accessibilityLabel("עוד אפשרויות").accessibilityIdentifier("home-menu")
            }.padding(.horizontal, 16).padding(.top, 4)
            if !home.sections.isEmpty { tabsPill(proxy).padding(.horizontal, 16) }
        }
        .padding(.bottom, 10)
        .background { UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28, style: .continuous).fill(.regularMaterial).ignoresSafeArea(edges: .top) }
        .overlay(alignment: .bottom) { UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28, style: .continuous).strokeBorder(Color.wellnessHairline, lineWidth: 0.7) }
        .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
    }
    private func iconButton(_ icon: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(icon == "sparkles" ? AnyShapeStyle(.flame) : AnyShapeStyle(Color.wellnessInk)).frame(width: 44, height: 44).contentShape(Rectangle()) }
            .buttonStyle(PressableStyle()).accessibilityLabel(label).accessibilityIdentifier(id)
    }
    private func tabsPill(_ proxy: ScrollViewProxy) -> some View {
        ScrollViewReader { tabs in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(home.sections) { section in
                        let selected = section.id == home.currentSection?.id
                        Button {
                            jumping = true; home.selectedSectionID = section.id
                            withAnimation(.easeInOut(duration: 0.45)) { proxy.scrollTo(section.id, anchor: .top) }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { jumping = false }
                        } label: {
                            HStack(spacing: 6) { if let e = section.emoji { Text(e) }; Text(section.name).font(.hb(.subheadline, .semibold)) }
                                .padding(.horizontal, 14).frame(minHeight: 40)
                                .foregroundStyle(selected ? Color.wellnessOnPrimary : Color.wellnessSecondary)
                                .background { if selected { Capsule().fill(Color.wellnessPrimary).shadow(color: .black.opacity(0.15), radius: 4, y: 2) } }
                                .scaleEffect(selected ? 1.04 : 1)
                        }.buttonStyle(.plain).accessibilityLabel(section.name).accessibilityAddTraits(selected ? [.isSelected] : []).accessibilityIdentifier("section-\(section.id)").id(section.id)
                    }
                }.padding(.horizontal, 6).padding(.vertical, 6).animation(.snappy, value: home.selectedSectionID)
            }
            .background(Capsule().fill(Color.wellnessCard.opacity(0.85))).overlay(Capsule().strokeBorder(Color.wellnessHairline))
            .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
            .onChange(of: home.selectedSectionID) { _, id in if let id { withAnimation(.snappy) { tabs.scrollTo(id, anchor: .center) } } }
            .sensoryFeedback(.selection, trigger: home.selectedSectionID)
        }
    }
}

// MARK: - Section panel

struct SectionPanel: View {
    @EnvironmentObject private var home: HomeStore
    let section: HSection
    @State private var scanning = false
    @State private var comparing = false
    @State private var scanned: String?
    @State private var lookingUp = false
    @State private var unknownCode: String?
    @State private var typedName = ""
    private var openTop: [HTask] { home.tasks(in: section.id).filter { $0.parentID == nil && !$0.isCompleted } }
    private var doneTop: [HTask] { home.tasks(in: section.id).filter { $0.parentID == nil && $0.isCompleted } }
    private var dueChores: Int { home.chores(in: section.id).filter { ($0.nextDue ?? .distantFuture) <= Date() }.count }
    private var progress: Double {
        switch section.kind {
        case "info": return 0
        case "chores": let all = home.chores(in: section.id); return all.isEmpty ? 0 : Double(all.count - dueChores) / Double(all.count)
        default: let total = openTop.count + doneTop.count; return total == 0 ? 0 : Double(doneTop.count) / Double(total)
        }
    }
    private var countText: String {
        switch section.kind {
        case "info": return "\(home.tasks(in: section.id).count) הערות"
        case "chores": return dueChores == 0 ? "הכול בוצע" : "\(dueChores) לביצוע"
        default: return "\(doneTop.count)/\(openTop.count + doneTop.count)"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if section.kind == "shopping" { shoppingActions }
            if section.kind != "info" { ProgressBar(value: progress, tint: Color.wellnessPrimary) }
            switch section.kind {
            case "chores": ChorePanelBody(section: section)
            case "info": TaskPanelBody(section: section, notesStyle: true)
            default: TaskPanelBody(section: section, notesStyle: false)
            }
        }
        .padding(.horizontal, 14).padding(.top, 20).padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Color.wellnessCard)
                .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Color.wellnessHairline))
                .shadow(color: .black.opacity(0.05), radius: 1, y: 1).shadow(color: .black.opacity(0.10), radius: 12, y: 6)
        }
        .overlay(alignment: .top) { UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous).fill(section.kindColor).frame(height: 6) }
        .background(GeometryReader { geo in Color.clear.preference(key: PanelOffsetKey.self, value: [section.id: geo.frame(in: .named("home-scroll")).minY]) })
        .accessibilityElement(children: .contain).accessibilityLabel(section.name)
        .sheet(isPresented: $comparing) { PriceComparisonSheet(section: section).environmentObject(home) }
        .fullScreenCover(isPresented: $scanning) {
            ZStack(alignment: .topLeading) {
                BarcodeScanner { code in scanning = false; Task { await handle(code) } }.ignoresSafeArea()
                Button { scanning = false } label: { Image(systemName: "xmark").font(.headline).padding(14).background(.ultraThinMaterial, in: Circle()) }.padding(20).accessibilityLabel("סגור")
                VStack { Spacer(); Text("כוון את הברקוד למרכז המסגרת").font(.hb(.headline)).padding(14).background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 60) }.frame(maxWidth: .infinity)
            }
        }
        .alert("מוצר לא מוכר", isPresented: Binding(get: { unknownCode != nil }, set: { if !$0 { unknownCode = nil } })) {
            TextField("שם המוצר", text: $typedName)
            Button("הוספה") { let name = typedName; typedName = ""; unknownCode = nil; Task { await home.addTask(title: name, section: section) } }
            Button("ביטול", role: .cancel) { unknownCode = nil }
        } message: { Text("לא מצאנו את הברקוד \(unknownCode ?? ""). אפשר להוסיף אותו בשם ידני.") }
    }
    @MainActor private func handle(_ code: String) async {
        lookingUp = true; defer { lookingUp = false }
        if let product = await home.lookupBarcode(code) { await home.addShoppingItem(title: product.name, price: product.price, section: section) } else { unknownCode = code }
    }
    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.06))
                if let e = section.emoji, !e.isEmpty { Text(e).font(.system(size: 20)) } else { Image(systemName: section.kindIcon).foregroundStyle(section.kindColor) }
            }.frame(width: 36, height: 36).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(section.name).font(.hb(.headline, .bold)).tracking(-0.2).foregroundStyle(Color.wellnessInk).lineLimit(2)
                Text(countText).font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary).monospacedDigit()
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var shoppingActions: some View {
        HStack(spacing: 6) {
            Button { scanning = true } label: { Label("סריקה", systemImage: "barcode.viewfinder").font(.hb(.footnote, .semibold)).lineLimit(1).fixedSize().padding(.horizontal, 12).frame(minHeight: 36).foregroundStyle(Color.wellnessOnPrimary).background(Color.wellnessPrimary, in: Capsule()) }
                .buttonStyle(PressableStyle()).accessibilityLabel("סריקת ברקוד").accessibilityIdentifier("scan-barcode")
            ShareLink(item: home.shareText(for: section)) { Label("שיתוף", systemImage: "square.and.arrow.up").font(.hb(.footnote, .semibold)).lineLimit(1).fixedSize().padding(.horizontal, 12).frame(minHeight: 36).foregroundStyle(Color.wellnessInk).background(Color.wellnessChip, in: Capsule()) }
                .accessibilityLabel("שיתוף הרשימה").accessibilityIdentifier("share-list")
            Button { comparing = true } label: { Label("מחירים", systemImage: "chart.line.downtrend.xyaxis").font(.hb(.footnote, .semibold)).lineLimit(1).fixedSize().padding(.horizontal, 12).frame(minHeight: 36).foregroundStyle(Color.wellnessInk).background(Color.wellnessChip, in: Capsule()) }
                .buttonStyle(PressableStyle()).accessibilityLabel("השוואת מחירים").accessibilityIdentifier("compare-prices")
            Spacer(minLength: 0)
        }
    }
}

struct ProgressBar: View {
    let value: Double
    let tint: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.07))
                Capsule().fill(tint).frame(width: max(0, geo.size.width * min(1, max(0, value))))
            }.environment(\.layoutDirection, .rightToLeft)
        }.frame(height: 6).animation(.spring(response: 0.5, dampingFraction: 0.85), value: value).accessibilityHidden(true)
    }
}

/// Swipe a row sideways to delete it (the web app's gesture). The row also exposes an accessibility action.
struct SwipeToDelete: ViewModifier {
    let onDelete: () -> Void
    @State private var dx: CGFloat = 0
    func body(content: Content) -> some View {
        ZStack(alignment: .leading) {
            HStack { Image(systemName: "trash").font(.headline).foregroundStyle(.white).padding(.leading, 20); Spacer() }
                .frame(maxHeight: .infinity).background(Color.fatCoral, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .environment(\.layoutDirection, .leftToRight).opacity(dx > 6 ? 1 : 0)
            content.background(Color.wellnessCard).offset(x: dx)
                .simultaneousGesture(DragGesture(minimumDistance: 28).onChanged { v in
                    guard abs(v.translation.width) > abs(v.translation.height) * 1.5 else { return }
                    dx = max(0, v.translation.width)
                }.onEnded { v in
                    if v.translation.width > 110 { UINotificationFeedbackGenerator().notificationOccurred(.warning); withAnimation(.easeIn(duration: 0.18)) { dx = 500 }; DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { onDelete() } }
                    else { withAnimation(.snappy) { dx = 0 } }
                })
        }.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityAction(named: "מחיקה", onDelete)
    }
}
extension View { func swipeToDelete(_ action: @escaping () -> Void) -> some View { modifier(SwipeToDelete(onDelete: action)) } }

// MARK: - Tasks, shopping, notes (panel body)

struct TaskPanelBody: View {
    @EnvironmentObject private var home: HomeStore
    let section: HSection
    let notesStyle: Bool
    @State private var draft = ""
    @State private var editing: HTask?
    @State private var showDone = false
    @State private var collapsed: Set<String> = []
    @State private var addingSubFor: String?
    @State private var subDraft = ""
    private var open: [HTask] { home.tasks(in: section.id).filter { $0.parentID == nil && !$0.isCompleted } }
    private var done: [HTask] { home.tasks(in: section.id).filter { $0.parentID == nil && $0.isCompleted } }
    private func children(_ t: HTask) -> [HTask] { home.tasks(in: section.id).filter { $0.parentID == t.id } }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "plus").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.wellnessOnPrimary).frame(width: 26, height: 26).background(Color.wellnessPrimary.opacity(0.9), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                TextField(section.kind == "shopping" ? "מה צריך לקנות?" : notesStyle ? "הערה חדשה…" : "משימה חדשה…", text: $draft).font(.hb(.subheadline)).submitLabel(.done)
                    .onSubmit { let text = draft; draft = ""; Task { await home.addTask(title: text, section: section, isNote: notesStyle, parseDates: true) } }
                    .accessibilityIdentifier("quick-add-field-\(section.id)")
            }.padding(.horizontal, 10).frame(minHeight: 44).background(Color.wellnessChip, in: RoundedRectangle(cornerRadius: 16, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.wellnessHairline))
            if open.isEmpty && done.isEmpty {
                Text(section.kind == "shopping" ? "הרשימה ריקה" : "אין כאן כלום עדיין").font(.hb(.footnote)).foregroundStyle(Color.wellnessSecondary).frame(maxWidth: .infinity).padding(.vertical, 22)
            }
            ForEach(open) { task in
                let kids = children(task)
                row(task, depth: 0, kids: kids.count)
                if addingSubFor == task.id { subtaskField(task) }
                if !kids.isEmpty && !collapsed.contains(task.id) {
                    VStack(spacing: 0) { ForEach(kids) { row($0, depth: 1, kids: 0) } }
                        .padding(.leading, 22).overlay(alignment: .leading) { Rectangle().fill(Color.wellnessHairline).frame(width: 1).padding(.leading, 12).padding(.vertical, 4) }
                }
            }
            if !done.isEmpty {
                Button { withAnimation(.snappy) { showDone.toggle() } } label: {
                    HStack { Text("הושלמו (\(done.count))").font(.hb(.subheadline, .semibold)); Spacer()
                        if section.kind == "shopping" { Button("נקה הכול") { Task { await home.clearCompleted(in: section) } }.font(.hb(.footnote)) }
                        Image(systemName: showDone ? "chevron.up" : "chevron.down").font(.footnote) }
                        .foregroundStyle(Color.wellnessSecondary).frame(minHeight: 44)
                }.buttonStyle(.plain)
                if showDone { ForEach(done) { row($0, depth: 0) } }
            }
        }.sheet(item: $editing) { TaskEditorSheet(task: $0, section: section).environmentObject(home) }
    }
    private func subtaskField(_ parent: HTask) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.turn.down.left").font(.footnote).foregroundStyle(Color.wellnessSecondary)
            TextField("תת-משימה חדשה", text: $subDraft).font(.hb(.subheadline)).submitLabel(.done)
                .onSubmit { let text = subDraft; subDraft = ""; addingSubFor = nil; if !text.trimmingCharacters(in: .whitespaces).isEmpty { Task { await home.addTask(title: text, section: section, parent: parent) } } }
                .accessibilityIdentifier("inline-subtask-\(parent.id)")
        }.padding(.horizontal, 12).frame(minHeight: 40).background(Color.wellnessChip, in: RoundedRectangle(cornerRadius: 12, style: .continuous)).padding(.leading, 34).padding(.bottom, 4)
    }
    private func row(_ task: HTask, depth: Int, kids: Int = 0) -> some View {
        TaskRow(task: task, depth: depth, notesStyle: notesStyle, childCount: kids, expanded: !collapsed.contains(task.id),
                onToggleExpand: { withAnimation(.snappy) { if collapsed.contains(task.id) { collapsed.remove(task.id) } else { collapsed.insert(task.id) } } },
                onAddSubtask: { withAnimation(.snappy) { addingSubFor = addingSubFor == task.id ? nil : task.id; subDraft = "" } },
                quiet: section.kind == "shopping") { editing = task }
            .swipeToDelete { Task { await home.delete(task) } }
            .modifier(ReorderDrag(task: task, enabled: depth == 0 && !notesStyle && !task.isCompleted))
            .contextMenu {
                if !notesStyle { Button { Task { await home.toggle(task) } } label: { Label(task.isCompleted ? "בטל סימון" : "סמן כבוצע", systemImage: "checkmark.circle") } }
                Button { editing = task } label: { Label("עריכה", systemImage: "pencil") }
                if depth == 0 && !notesStyle {
                    Button { Task { await home.move(task, in: section, by: -1) } } label: { Label("הזז למעלה", systemImage: "arrow.up") }
                    Button { Task { await home.move(task, in: section, by: 1) } } label: { Label("הזז למטה", systemImage: "arrow.down") }
                }
                Button(role: .destructive) { Task { await home.delete(task) } } label: { Label("מחיקה", systemImage: "trash") }
            }
    }
}

/// Long-press and drag a task onto another to reorder the list (the web app's drag handles).
private struct ReorderDrag: ViewModifier {
    @EnvironmentObject private var home: HomeStore
    let task: HTask
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content.draggable(task.id) { Text(task.title).font(.hb(.body)).padding(10).background(Color.wellnessCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous)) }
                .dropDestination(for: String.self) { ids, _ in
                    guard let id = ids.first else { return false }
                    Task { await home.reorder(id, onto: task.id) }; return true
                }
        } else { content }
    }
}

struct TaskRow: View {
    @EnvironmentObject private var home: HomeStore
    let task: HTask
    let depth: Int
    let notesStyle: Bool
    var childCount = 0
    var expanded = true
    var onToggleExpand: (() -> Void)? = nil
    var onAddSubtask: (() -> Void)? = nil
    /// Shopping lists stay quiet: no assignee placeholder or subtask button unless they are used.
    var quiet = false
    let onOpen: () -> Void
    private static let dayMonth: DateFormatter = { let f = DateFormatter(); f.dateFormat = "d/M"; return f }()
    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            if !notesStyle {
                if depth == 0 {
                    if childCount > 0 {
                        Button { onToggleExpand?() } label: { Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.wellnessSecondary).rotationEffect(.degrees(expanded ? 0 : 90)).frame(width: 24, height: 40).contentShape(Rectangle()) }
                            .buttonStyle(.plain).accessibilityLabel(expanded ? "כיווץ תתי־משימות" : "הרחבת תתי־משימות")
                    } else { Color.clear.frame(width: 6, height: 1) }
                }
                Button { Task { await home.toggle(task) } } label: { checkbox.frame(width: 40, height: 44).contentShape(Rectangle()) }
                    .buttonStyle(.plain).accessibilityLabel(task.isCompleted ? "בטל סימון \(task.title)" : "סמן \(task.title) כבוצע").accessibilityIdentifier("task-toggle-\(task.id)")
                    .sensoryFeedback(.success, trigger: task.isCompleted) { _, done in done }
            }
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if let p = task.priority, p > 0 { Circle().fill(p == 3 ? Color.kindChores : p == 2 ? Color.kcalAmber : Color.proteinBlue).frame(width: 7, height: 7).accessibilityLabel(p == 3 ? "דחוף" : p == 2 ? "חשוב" : "רגיל") }
                        if let e = task.emoji { Text(e).font(.hb(.subheadline)) }
                        Text(task.title).font(.hb(.callout, notesStyle ? .semibold : .regular)).strikethrough(task.isCompleted).foregroundStyle(task.isCompleted ? Color.wellnessSecondary : Color.wellnessInk).multilineTextAlignment(.leading)
                    }
                    if notesStyle, let n = task.notes, !n.isEmpty { Text(n).font(.hb(.footnote)).foregroundStyle(Color.wellnessSecondary).lineLimit(4).multilineTextAlignment(.leading) }
                    badges
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, notesStyle ? 8 : 4).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("task-open-\(task.id)")
            if !task.assigneeIDs.isEmpty || (!notesStyle && !quiet) {
                AssigneeButton(currentID: task.assigneeIDs.first, size: 30, ids: task.assigneeIDs, badge: true) { id in Task { await home.setAssignee(task, to: id) } }.accessibilityIdentifier("task-assignee-\(task.id)")
            }
            if depth == 0, !notesStyle, !quiet, !task.isCompleted, let onAddSubtask {
                Button(action: onAddSubtask) { Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.wellnessSecondary).frame(width: 30, height: 44).contentShape(Rectangle()) }
                    .buttonStyle(.plain).accessibilityLabel("הוספת תת־משימה").accessibilityIdentifier("task-add-sub-\(task.id)")
            }
        }
        .padding(.horizontal, notesStyle ? 12 : 4)
        .background(notesStyle ? Color.wellnessCard : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(notesStyle ? Color.wellnessHairline : .clear))
    }
    /// Round checkbox (the web app's 20pt circle): hollow ring, filled with a check when done.
    private var checkbox: some View {
        ZStack {
            Circle().strokeBorder(task.isCompleted ? Color.clear : Color.wellnessSecondary.opacity(0.7), lineWidth: 1.6)
            if task.isCompleted { Circle().fill(Color.wellnessPrimary); Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(Color.wellnessOnPrimary) }
        }.frame(width: 22, height: 22).animation(.snappy(duration: 0.2), value: task.isCompleted)
    }
    @ViewBuilder private var badges: some View {
        let items = badgeItems
        if !items.isEmpty {
            HStack(spacing: 5) {
                ForEach(items, id: \.text) { b in
                    Text(b.text).font(.hb(.caption, .medium)).monospacedDigit().padding(.horizontal, 8).frame(height: 22)
                        .foregroundStyle(b.fg).background(b.bg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(b.stroke))
                }
            }
        }
    }
    private struct Badge { let text: String; let fg: Color; let bg: Color; let stroke: Color }
    private var badgeItems: [Badge] {
        var list: [Badge] = []
        if let q = task.quantity { list.append(Badge(text: "×\(q.formatted()) \(task.unit ?? "")".trimmingCharacters(in: .whitespaces), fg: Color.wellnessInk, bg: Color.wellnessChip, stroke: .clear)) }
        if let due = task.dueAt {
            let cal = Calendar.current
            let overdue = !task.isCompleted && cal.startOfDay(for: due) < cal.startOfDay(for: Date())
            let today = !task.isCompleted && cal.isDateInToday(due)
            let text = Self.dayMonth.string(from: due)
            list.append(overdue ? Badge(text: text, fg: Color.fatCoralText, bg: Color.kindChores.opacity(0.12), stroke: Color.kindChores.opacity(0.35))
                : today ? Badge(text: text, fg: Color.amberInk, bg: Color.amberTint, stroke: Color.kcalAmber.opacity(0.5))
                : Badge(text: text, fg: Color.wellnessSecondary, bg: .clear, stroke: Color.wellnessHairline))
        }
        if let price = task.price { list.append(Badge(text: "₪\(price.formatted())", fg: Color.wellnessSecondary, bg: Color.wellnessChip, stroke: .clear)) }
        return list
    }
}

struct TaskEditorSheet: View {
    @EnvironmentObject private var home: HomeStore
    @Environment(\.dismiss) private var dismiss
    let task: HTask
    let section: HSection
    @State private var title = ""
    @State private var notes = ""
    @State private var priority = 0
    @State private var hasDue = false
    @State private var due = Date()
    @State private var assignees: Set<String> = []
    @State private var quantity = ""
    @State private var unit = ""
    @State private var confirmDelete = false
    @State private var subtask = ""
    var body: some View {
        NavigationStack {
            List {
                Section { TextField("כותרת", text: $title).font(.hb(.headline, .semibold)); TextField("הערות", text: $notes, axis: .vertical).lineLimit(1...6) }
                if section.kind != "info" {
                    Section("עדיפות") { Picker("עדיפות", selection: $priority) { Text("ללא").tag(0); Text("רגיל").tag(1); Text("חשוב").tag(2); Text("דחוף").tag(3) }.pickerStyle(.segmented) }
                    Section("מועד") {
                        Toggle("הגדרת מועד", isOn: $hasDue.animation()).tint(Color.wellnessPrimary)
                        if hasDue { DatePicker("מועד", selection: $due).environment(\.locale, Locale(identifier: "he_IL")) }
                    }
                    Section("מי אחראי") {
                        ForEach(home.members) { m in
                            Button { if assignees.contains(m.id) { assignees.remove(m.id) } else { assignees.insert(m.id) } } label: {
                                HStack(spacing: 12) { MemberAvatar(member: m, size: 32); Text(m.name).foregroundStyle(Color.wellnessInk); Spacer(); if assignees.contains(m.id) { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.wellnessInk) } }.frame(minHeight: 44)
                            }.accessibilityAddTraits(assignees.contains(m.id) ? [.isSelected] : [])
                        }
                    }
                }
                if section.kind != "info" && task.parentID == nil {
                    Section("תת-משימות") {
                        ForEach(home.tasks.filter { $0.parentID == task.id }.sorted { $0.position < $1.position }) { child in
                            HStack(spacing: 10) {
                                Button { Task { await home.toggle(child) } } label: { Image(systemName: child.isCompleted ? "checkmark.circle.fill" : "circle").font(.title3).frame(width: 36, height: 36) }.buttonStyle(.plain)
                                Text(child.title).strikethrough(child.isCompleted).foregroundStyle(child.isCompleted ? Color.wellnessSecondary : Color.wellnessInk)
                            }.swipeActions { Button(role: .destructive) { Task { await home.delete(child) } } label: { Label("מחיקה", systemImage: "trash") } }
                        }
                        HStack { Image(systemName: "plus").foregroundStyle(Color.wellnessSecondary); TextField("תת-משימה חדשה", text: $subtask).submitLabel(.done).onSubmit { let text = subtask; subtask = ""; Task { await home.addTask(title: text, section: section, parent: task) } }.accessibilityIdentifier("subtask-field") }
                    }
                }
                if section.kind == "shopping" {
                    Section("כמות") { HStack { TextField("כמות", text: $quantity).keyboardType(.decimalPad); TextField("יחידה (ק״ג, יח׳…)", text: $unit) } }
                }
                AttachmentsSection(taskID: task.id)
                Section { Button("מחיקה", role: .destructive) { confirmDelete = true }.frame(maxWidth: .infinity) }
            }
            .wellnessList().navigationTitle("עריכה").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ביטול") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("שמירה") { Task { await save() } }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
            .confirmationDialog("למחוק?", isPresented: $confirmDelete, titleVisibility: .visible) { Button("מחיקה", role: .destructive) { Task { await home.delete(task); dismiss() } } }
            .onAppear { title = task.title; notes = task.notes ?? ""; priority = task.priority ?? 0; if let d = task.dueAt { hasDue = true; due = d }; assignees = Set(task.assigneeIDs); quantity = task.quantity.map { $0.formatted() } ?? ""; unit = task.unit ?? "" }
        }
    }
    @MainActor private func save() async {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let qty = Double(quantity.replacingOccurrences(of: ",", with: "."))
        let ids = home.members.map(\.id).filter { assignees.contains($0) }
        var fields: [String: JSONValue] = [
            "title": .string(cleanTitle), "notes": notes.isEmpty ? .null : .string(String(notes.prefix(4000))), "priority": priority == 0 ? .null : .number(Double(priority)),
            "due_at": hasDue ? .string(DateParsing.iso(due)) : .null,
            "assignee_kind": .string(ids.isEmpty ? "unassigned" : "member"), "assignee_member_ids": .array(ids.map { .string($0) }), "assignee_member_id": ids.first.map { .string($0) } ?? .null,
        ]
        if section.kind == "shopping" { fields["quantity"] = qty.map { .number($0) } ?? .null; fields["unit"] = unit.isEmpty ? .null : .string(String(unit.prefix(40))) }
        await home.update(task, fields: fields) { t in
            t.title = cleanTitle; t.notes = notes.isEmpty ? nil : notes; t.priority = priority == 0 ? nil : priority; t.dueAt = hasDue ? due : nil
            t.assigneeIDs = ids; t.assigneeKind = ids.isEmpty ? "unassigned" : "member"
            if section.kind == "shopping" { t.quantity = qty; t.unit = unit.isEmpty ? nil : unit }
        }
        dismiss()
    }
}

/// Proactive assistant cards: open suggestions (apply or dismiss) and private notes for me (dismiss = mark read).
struct AssistantCards: View {
    @EnvironmentObject private var home: HomeStore
    @State private var applying: String?
    var body: some View {
        VStack(spacing: 8) {
            ForEach(home.suggestions) { s in
                card(emoji: s.emoji ?? "💡", text: s.summary, ring: Color.wellnessPrimary.opacity(0.3), id: s.id) {
                    HStack(spacing: 6) {
                        if s.isApplicable {
                            Button { applying = s.id; Task { await home.apply(s); applying = nil } } label: { Text("הוספה").font(.hb(.subheadline, .semibold)).lineLimit(1).fixedSize().padding(.horizontal, 14).frame(minHeight: 40).foregroundStyle(Color.wellnessOnPrimary).background(Color.wellnessPrimary, in: Capsule()) }
                                .buttonStyle(PressableStyle()).disabled(applying == s.id).accessibilityIdentifier("suggestion-apply-\(s.id)")
                        }
                        dismissButton { Task { await home.dismiss(s) } }
                    }
                }
            }
            ForEach(home.notes) { n in
                card(emoji: "💜", text: n.summary, ring: Color(red: 0.85, green: 0.27, blue: 0.94).opacity(0.3), id: n.id) { dismissButton { Task { await home.markRead(n) } } }
            }
        }
    }
    private func card<Trailing: View>(emoji: String, text: String, ring: Color, id: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 12) {
            Text(emoji).font(.system(size: 22)).accessibilityHidden(true)
            Text(text).font(.hb(.subheadline)).foregroundStyle(Color.wellnessInk).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading).layoutPriority(0)
            trailing().layoutPriority(1)
        }
        .padding(10)
        .background(Color.wellnessCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(ring, lineWidth: 1.2))
        .shadow(color: .black.opacity(0.05), radius: 1, y: 1).shadow(color: .black.opacity(0.08), radius: 10, y: 5)
        .transition(.scale.combined(with: .opacity)).accessibilityElement(children: .contain)
    }
    private func dismissButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.wellnessSecondary).frame(width: 40, height: 40).contentShape(Rectangle()) }
            .buttonStyle(.plain).accessibilityLabel("סגירה")
    }
}
