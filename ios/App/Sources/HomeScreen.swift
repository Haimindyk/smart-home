import SwiftUI
import WellnessCore

struct MemberAvatar: View {
    let member: HMember?
    var size: CGFloat = 36
    var body: some View {
        let tint = Color(hex: member?.color ?? "#888888")
        Text(member?.emoji ?? String(member?.name.prefix(1) ?? "?")).font(.system(size: size * 0.5))
            .frame(width: size, height: size).background(tint.opacity(0.22), in: Circle()).overlay(Circle().strokeBorder(tint.opacity(0.5), lineWidth: 1.5))
            .accessibilityLabel(member?.name ?? "")
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
                        AssistantCards()
                        if home.sections.isEmpty && !home.loading { ContentUnavailableView("אין עדיין מדורים", systemImage: "square.grid.2x2", description: Text("צור מדור חדש בתפריט ⋯.")) }
                        ForEach(home.sections) { SectionPanel(section: $0).id($0.id) }
                        Color.clear.frame(height: 110)
                    }.padding(.horizontal, 16).padding(.top, 6).shimmer(home.loading && home.sections.isEmpty)
                }
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
            .alert("משהו השתבש", isPresented: Binding(get: { home.error != nil }, set: { if !$0 { home.error = nil } })) { Button("סגור", role: .cancel) {} } message: { Text(home.error ?? "") }
        }
    }

    // MARK: Hero
    private var hero: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("הבית").font(.hb(.caption2, .semibold)).tracking(2.2).foregroundStyle(Color.wellnessPrimary)
                (Text("\(greeting)").foregroundStyle(Color.wellnessInk) + Text(home.me.map { ", " + $0.name } ?? "").foregroundStyle(Color.amberInk))
                    .font(.hb(.title, .bold)).tracking(-0.5).fixedSize(horizontal: false, vertical: true)
                Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide)).font(.hb(.footnote)).foregroundStyle(Color.wellnessSecondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            MemberAvatar(member: home.me, size: 56)
        }
        .padding(22)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Color.wellnessCard)
                .overlay(RadialGradient(colors: [Color.wellnessPrimary.opacity(0.09), .clear], center: UnitPoint(x: 1, y: -0.1), startRadius: 0, endRadius: 320).clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous)))
                .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Color.wellnessHairline))
                .shadow(color: .black.opacity(0.05), radius: 1, y: 1).shadow(color: .black.opacity(0.10), radius: 12, y: 6)
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
        VStack(alignment: .leading, spacing: 14) {
            header
            if section.kind == "shopping" { shoppingActions }
            if section.kind != "info" { ProgressBar(value: progress, tint: Color.wellnessPrimary) }
            switch section.kind {
            case "chores": ChorePanelBody(section: section)
            case "info": TaskPanelBody(section: section, notesStyle: true)
            default: TaskPanelBody(section: section, notesStyle: false)
            }
        }
        .padding(.horizontal, 18).padding(.top, 24).padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Color.wellnessCard)
                .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Color.wellnessHairline))
                .shadow(color: .black.opacity(0.05), radius: 1, y: 1).shadow(color: .black.opacity(0.10), radius: 12, y: 6)
        }
        .overlay(alignment: .top) { UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous).fill(section.kindColor).frame(height: 6) }
        .background(GeometryReader { geo in Color.clear.preference(key: PanelOffsetKey.self, value: [section.id: geo.frame(in: .named("home-scroll")).minY]) })
        .accessibilityElement(children: .contain).accessibilityLabel(section.name)
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
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.06))
                if let e = section.emoji, !e.isEmpty { Text(e).font(.system(size: 20)) } else { Image(systemName: section.kindIcon).foregroundStyle(section.kindColor) }
            }.frame(width: 42, height: 42).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(section.name).font(.hb(.title3, .bold)).tracking(-0.3).foregroundStyle(Color.wellnessInk).lineLimit(2)
                Text(countText).font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary).monospacedDigit()
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private var shoppingActions: some View {
        HStack(spacing: 8) {
            Button { scanning = true } label: { Label("סריקת ברקוד", systemImage: "barcode.viewfinder").font(.hb(.footnote, .semibold)).padding(.horizontal, 14).frame(minHeight: 40).foregroundStyle(Color.wellnessOnPrimary).background(Color.wellnessPrimary, in: Capsule()) }
                .buttonStyle(PressableStyle()).accessibilityIdentifier("scan-barcode")
            ShareLink(item: home.shareText(for: section)) { Label("שיתוף הרשימה", systemImage: "square.and.arrow.up").font(.hb(.footnote, .semibold)).padding(.horizontal, 14).frame(minHeight: 40).foregroundStyle(Color.wellnessInk).background(Color.wellnessChip, in: Capsule()) }
                .accessibilityIdentifier("share-list")
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
    private var open: [HTask] { home.tasks(in: section.id).filter { $0.parentID == nil && !$0.isCompleted } }
    private var done: [HTask] { home.tasks(in: section.id).filter { $0.parentID == nil && $0.isCompleted } }
    private func children(_ t: HTask) -> [HTask] { home.tasks(in: section.id).filter { $0.parentID == t.id } }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "plus").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.wellnessSecondary)
                TextField(section.kind == "shopping" ? "מה צריך לקנות?" : notesStyle ? "הערה חדשה…" : "משימה חדשה…", text: $draft).submitLabel(.done)
                    .onSubmit { let text = draft; draft = ""; Task { await home.addTask(title: text, section: section, isNote: notesStyle) } }
                    .accessibilityIdentifier("quick-add-field-\(section.id)")
            }.padding(.horizontal, 14).frame(minHeight: 46).background(Color.wellnessChip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            if open.isEmpty && done.isEmpty {
                Text(section.kind == "shopping" ? "הרשימה ריקה" : "אין כאן כלום עדיין").font(.hb(.footnote)).foregroundStyle(Color.wellnessSecondary).frame(maxWidth: .infinity).padding(.vertical, 22)
            }
            ForEach(open) { task in
                row(task, depth: 0)
                ForEach(children(task)) { row($0, depth: 1) }
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
    private func row(_ task: HTask, depth: Int) -> some View {
        TaskRow(task: task, depth: depth, notesStyle: notesStyle) { editing = task }
            .padding(.leading, CGFloat(depth) * 22)
            .swipeToDelete { Task { await home.delete(task) } }
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

struct TaskRow: View {
    @EnvironmentObject private var home: HomeStore
    let task: HTask
    let depth: Int
    let notesStyle: Bool
    let onOpen: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if !notesStyle {
                Button { Task { await home.toggle(task) } } label: {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle").font(.hb(.title2)).foregroundStyle(task.isCompleted ? Color.wellnessInk : Color.wellnessSecondary)
                        .symbolEffect(.bounce, value: task.isCompleted).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel(task.isCompleted ? "בטל סימון \(task.title)" : "סמן \(task.title) כבוצע").accessibilityIdentifier("task-toggle-\(task.id)").sensoryFeedback(.success, trigger: task.isCompleted) { _, done in done }
            }
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        if let e = task.emoji { Text(e) }
                        Text(task.title).font(.hb(.body, notesStyle ? .semibold : .regular)).strikethrough(task.isCompleted).foregroundStyle(task.isCompleted ? Color.wellnessSecondary : Color.wellnessInk).multilineTextAlignment(.leading)
                    }
                    if notesStyle, let n = task.notes, !n.isEmpty { Text(n).font(.hb(.subheadline)).foregroundStyle(Color.wellnessSecondary).lineLimit(4).multilineTextAlignment(.leading) }
                    meta
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, notesStyle ? 10 : 8).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("task-open-\(task.id)")
        }
        .padding(.horizontal, notesStyle ? 14 : 4).background(notesStyle ? Color.wellnessCard : Color.clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(notesStyle ? Color.wellnessHairline : .clear))
    }
    @ViewBuilder private var meta: some View {
        let parts = chips
        if !parts.isEmpty || !task.assigneeIDs.isEmpty {
            HStack(spacing: 6) {
                ForEach(parts, id: \.text) { chip in Label(chip.text, systemImage: chip.icon).font(.hb(.caption, .medium)).padding(.horizontal, 8).padding(.vertical, 4).foregroundStyle(chip.color).background(chip.color.opacity(0.13), in: Capsule()) }
                ForEach(task.assigneeIDs.prefix(3), id: \.self) { MemberAvatar(member: home.member($0), size: 22) }
            }
        }
    }
    private struct Chip { let text: String; let icon: String; let color: Color }
    private var chips: [Chip] {
        var list: [Chip] = []
        if let due = task.dueAt {
            let overdue = due < Date() && !task.isCompleted
            list.append(Chip(text: due.formatted(.dateTime.day().month(.abbreviated).hour().minute()), icon: "clock", color: overdue ? .fatCoralText : Color.wellnessSecondary))
        }
        if let p = task.priority, p > 0 { list.append(Chip(text: p == 3 ? "דחוף" : p == 2 ? "חשוב" : "רגיל", icon: "flag.fill", color: p == 3 ? .fatCoralText : .kcalAmberText)) }
        if let q = task.quantity { list.append(Chip(text: "\(q.formatted()) \(task.unit ?? "")".trimmingCharacters(in: .whitespaces), icon: "number", color: Color.wellnessSecondary)) }
        if let price = task.price { list.append(Chip(text: "₪\(price.formatted())", icon: "shekelsign", color: Color.wellnessSecondary)) }
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
        VStack(spacing: 10) {
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
        .padding(14)
        .background(Color.wellnessCard, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(ring, lineWidth: 1.2))
        .shadow(color: .black.opacity(0.05), radius: 1, y: 1).shadow(color: .black.opacity(0.08), radius: 10, y: 5)
        .transition(.scale.combined(with: .opacity)).accessibilityElement(children: .contain)
    }
    private func dismissButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.wellnessSecondary).frame(width: 40, height: 40).contentShape(Rectangle()) }
            .buttonStyle(.plain).accessibilityLabel("סגירה")
    }
}
