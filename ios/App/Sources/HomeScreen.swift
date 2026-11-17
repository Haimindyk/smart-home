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

struct HomeScreen: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var home: HomeStore
    @State private var showSettings = false
    @State private var showCoach = false
    @State private var sheet: HomeSheet?
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour < 5 ? "לילה טוב" : hour < 12 ? "בוקר טוב" : hour < 18 ? "צהריים טובים" : hour < 22 ? "ערב טוב" : "לילה טוב"
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                sectionChips
                Group {
                    if let section = home.currentSection {
                        switch section.kind {
                        case "chores": ChoreList(section: section)
                        case "info": TaskList(section: section, notesStyle: true)
                        default: TaskList(section: section, notesStyle: false)
                        }
                    } else if home.loading {
                        ProgressView().frame(maxHeight: .infinity)
                    } else {
                        ContentUnavailableView("אין עדיין מדורים", systemImage: "square.grid.2x2", description: Text("מדורים שתיצור באתר יופיעו כאן."))
                    }
                }
            }
            .wellnessScreen().toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) { SettingsScreen(isSheet: true).environmentObject(store) }
            .sheet(item: $sheet) { which in
                switch which {
                case .search: SearchSheet().environmentObject(home)
                case .newSection: SectionEditorSheet(section: nil).environmentObject(home)
                case .editSection(let section): SectionEditorSheet(section: section).environmentObject(home)
                case .history: HistorySheet().environmentObject(home)
                case .members: MembersSheet().environmentObject(home)
                }
            }
            .sheet(isPresented: $showCoach) { CoachChatView().environmentObject(store) }
            .alert("משהו השתבש", isPresented: Binding(get: { home.error != nil }, set: { if !$0 { home.error = nil } })) { Button("סגור", role: .cancel) {} } message: { Text(home.error ?? "") }
        }
    }
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            MemberAvatar(member: home.me, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting).font(.subheadline).foregroundStyle(Color.wellnessSecondary)
                Text(home.me?.name ?? "").font(.title.bold()).lineLimit(1).minimumScaleFactor(0.7)
                Text(Date(), format: .dateTime.weekday(.wide).day().month(.wide)).font(.footnote).foregroundStyle(Color.wellnessSecondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            roundButton("sparkles", tint: .flame, label: "המאמן שלי", id: "coach-button") { showCoach = true }
            Menu {
                Button { sheet = .search } label: { Label("חיפוש", systemImage: "magnifyingglass") }
                Button { sheet = .newSection } label: { Label("מדור חדש", systemImage: "plus.rectangle.on.rectangle") }
                if let current = home.currentSection { Button { sheet = .editSection(current) } label: { Label("עריכת המדור", systemImage: "pencil") } }
                Button { sheet = .history } label: { Label("היסטוריה", systemImage: "clock.arrow.circlepath") }
                Button { sheet = .members } label: { Label("בני הבית", systemImage: "person.2") }
                Divider()
                Button { showSettings = true } label: { Label("הגדרות", systemImage: "gearshape") }
            } label: {
                Image(systemName: "ellipsis").font(.title3).foregroundStyle(Color.wellnessInk).frame(width: 46, height: 46)
                    .background(Color.wellnessCard, in: Circle()).overlay(Circle().strokeBorder(Color.wellnessHairline))
            }.accessibilityLabel("עוד אפשרויות").accessibilityIdentifier("home-menu")
        }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
    }
    private func roundButton<S: ShapeStyle>(_ icon: String, tint: S, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.title3).foregroundStyle(tint).frame(width: 46, height: 46)
                .background(Color.wellnessCard, in: Circle()).overlay(Circle().strokeBorder(Color.wellnessHairline))
        }.buttonStyle(PressableStyle()).accessibilityLabel(label).accessibilityIdentifier(id)
    }
    private var sectionChips: some View {
        ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(home.sections) { section in
                    let selected = section.id == home.currentSection?.id
                    Button { withAnimation(.snappy) { home.selectedSectionID = section.id } } label: {
                        HStack(spacing: 6) { if let e = section.emoji { Text(e) }; Text(section.name).font(.subheadline.weight(.semibold)) }
                            .padding(.horizontal, 14).frame(minHeight: 44)
                            .foregroundStyle(selected ? Color.wellnessOnInk : Color.wellnessInk)
                            .background(selected ? Color.wellnessInk : Color.wellnessCard, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.wellnessHairline))
                    }.buttonStyle(PressableStyle()).accessibilityLabel(section.name).accessibilityAddTraits(selected ? [.isSelected] : []).accessibilityIdentifier("section-\(section.id)").id(section.id)
                }
            }.padding(.horizontal, 20).padding(.bottom, 10)
        }.sensoryFeedback(.selection, trigger: home.selectedSectionID)
        .onChange(of: home.selectedSectionID) { _, id in if let id { withAnimation(.snappy) { proxy.scrollTo(id, anchor: .center) } } }
        }
    }
}

// MARK: - Tasks, shopping, notes

struct TaskList: View {
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
        List {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill").foregroundStyle(Color.wellnessSecondary).font(.title3)
                TextField(section.kind == "shopping" ? "מה צריך לקנות?" : notesStyle ? "הערה חדשה…" : "משימה חדשה…", text: $draft).submitLabel(.done)
                    .onSubmit { let text = draft; draft = ""; Task { await home.addTask(title: text, section: section, isNote: notesStyle) } }
                    .accessibilityIdentifier("quick-add-field")
            }.padding(.horizontal, 16).frame(minHeight: 52).background(Color.wellnessCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.wellnessHairline)).listRowSeparator(.hidden).listRowBackground(Color.clear)
            if open.isEmpty && done.isEmpty {
                ContentUnavailableView(section.kind == "shopping" ? "הרשימה ריקה" : "אין כאן כלום עדיין", systemImage: section.kind == "shopping" ? "cart" : "checkmark.circle", description: Text("הוסף פריט בשדה למעלה."))
                    .listRowSeparator(.hidden).listRowBackground(Color.clear)
            }
            ForEach(open) { task in
                row(task, depth: 0)
                ForEach(children(task)) { child in row(child, depth: 1) }
            }
            if !done.isEmpty {
                Section {
                    Button { withAnimation(.snappy) { showDone.toggle() } } label: {
                        HStack { Text("הושלמו (\(done.count))").font(.subheadline.weight(.semibold)); Spacer(); if section.kind == "shopping" { Button("נקה הכול") { Task { await home.clearCompleted(in: section) } }.font(.footnote) }; Image(systemName: showDone ? "chevron.up" : "chevron.down") }
                            .foregroundStyle(Color.wellnessSecondary).frame(minHeight: 44)
                    }.buttonStyle(.plain).listRowSeparator(.hidden).listRowBackground(Color.clear)
                    if showDone { ForEach(done) { row($0, depth: 0) } }
                }
            }
            Color.clear.frame(height: 90).listRowSeparator(.hidden).listRowBackground(Color.clear)
        }
        .listStyle(.plain).scrollContentBackground(.hidden).environment(\.defaultMinListRowHeight, 10)
        .refreshable { await home.refresh() }
        .sheet(item: $editing) { TaskEditorSheet(task: $0, section: section).environmentObject(home) }
    }
    private func row(_ task: HTask, depth: Int) -> some View {
        TaskRow(task: task, depth: depth, notesStyle: notesStyle) { editing = task }
            .listRowSeparator(.hidden).listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 4, leading: 16 + CGFloat(depth) * 22, bottom: 4, trailing: 16))
            .swipeActions(edge: .trailing, allowsFullSwipe: true) { Button(role: .destructive) { Task { await home.delete(task) } } label: { Label("מחיקה", systemImage: "trash") } }
            .swipeActions(edge: .leading) { if !notesStyle { Button { Task { await home.toggle(task) } } label: { Label(task.isCompleted ? "בטל" : "בוצע", systemImage: "checkmark") }.tint(.green) } }
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
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(task.isCompleted ? Color.wellnessInk : Color.wellnessSecondary)
                        .symbolEffect(.bounce, value: task.isCompleted).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel(task.isCompleted ? "בטל סימון \(task.title)" : "סמן \(task.title) כבוצע").accessibilityIdentifier("task-toggle-\(task.id)").sensoryFeedback(.success, trigger: task.isCompleted) { _, done in done }
            }
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        if let e = task.emoji { Text(e) }
                        Text(task.title).font(.body.weight(notesStyle ? .semibold : .regular)).strikethrough(task.isCompleted).foregroundStyle(task.isCompleted ? Color.wellnessSecondary : Color.wellnessInk).multilineTextAlignment(.leading)
                    }
                    if notesStyle, let n = task.notes, !n.isEmpty { Text(n).font(.subheadline).foregroundStyle(Color.wellnessSecondary).lineLimit(4).multilineTextAlignment(.leading) }
                    meta
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, notesStyle ? 10 : 8).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, notesStyle ? 14 : 4).background(notesStyle ? Color.wellnessCard : Color.clear, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(notesStyle ? Color.wellnessHairline : .clear))
    }
    @ViewBuilder private var meta: some View {
        let parts = chips
        if !parts.isEmpty || !task.assigneeIDs.isEmpty {
            HStack(spacing: 6) {
                ForEach(parts, id: \.text) { chip in Label(chip.text, systemImage: chip.icon).font(.caption.weight(.medium)).padding(.horizontal, 8).padding(.vertical, 4).foregroundStyle(chip.color).background(chip.color.opacity(0.13), in: Capsule()) }
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
    var body: some View {
        NavigationStack {
            List {
                Section { TextField("כותרת", text: $title).font(.headline); TextField("הערות", text: $notes, axis: .vertical).lineLimit(1...6) }
                if section.kind != "info" {
                    Section("עדיפות") { Picker("עדיפות", selection: $priority) { Text("ללא").tag(0); Text("רגיל").tag(1); Text("חשוב").tag(2); Text("דחוף").tag(3) }.pickerStyle(.segmented) }
                    Section("מועד") {
                        Toggle("הגדרת מועד", isOn: $hasDue.animation()).tint(Color.wellnessInk)
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
