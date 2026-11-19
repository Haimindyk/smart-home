import SwiftUI
import WellnessCore

// MARK: - Chores

struct ChorePanelBody: View {
    @EnvironmentObject private var home: HomeStore
    let section: HSection
    @State private var confirmDelete: HChore?
    @State private var editing: HChore?
    @State private var draft = ""
    private func status(_ chore: HChore) -> (text: String, color: Color) {
        guard let due = chore.nextDue else { return ("", Color.wellnessSecondary) }
        var cal = Calendar(identifier: .gregorian); cal.timeZone = home.timeZone
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: due)).day ?? 0
        switch days {
        case ..<0: return ("באיחור של \(-days) ימים", .fatCoralText)
        case 0: return ("להיום", .kcalAmberText)
        case 1: return ("מחר", Color.wellnessSecondary)
        default: return ("בעוד \(days) ימים", Color.wellnessSecondary)
        }
    }
    private func repeatText(_ c: HChore) -> String {
        let n = max(1, c.intervalN)
        switch c.freq { case "daily": return n == 1 ? "כל יום" : "כל \(n) ימים"; case "weekly": return n == 1 ? "כל שבוע" : "כל \(n) שבועות"; case "monthly": return n == 1 ? "כל חודש" : "כל \(n) חודשים"; default: return "לפי הצורך" }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "plus").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.wellnessOnPrimary).frame(width: 26, height: 26).background(Color.wellnessPrimary.opacity(0.9), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                TextField("מטלה חדשה (כל שבוע)…", text: $draft).font(.hb(.subheadline)).submitLabel(.done)
                    .onSubmit { let text = draft; draft = ""; Task { await home.addChore(title: text, section: section, freq: "weekly", interval: 1) } }
            }.padding(.horizontal, 10).frame(minHeight: 44).background(Color.wellnessChip, in: RoundedRectangle(cornerRadius: 16, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.wellnessHairline))
            let chores = home.chores(in: section.id)
            if chores.isEmpty { Text("אין מטלות עדיין").font(.hb(.footnote)).foregroundStyle(Color.wellnessSecondary).frame(maxWidth: .infinity).padding(.vertical, 22) }
            ForEach(chores) { chore in
                let s = status(chore)
                let isDue = (chore.nextDue ?? .distantFuture) <= Date()
                HStack(spacing: 8) {
                    Button { Task { await home.complete(chore) } } label: {
                        Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).frame(width: 36, height: 36)
                            .foregroundStyle(isDue ? Color.wellnessOnPrimary : Color.wellnessInk)
                            .background(isDue ? Color.wellnessPrimary : Color.clear, in: Circle())
                            .overlay(Circle().strokeBorder(isDue ? Color.clear : Color.wellnessHairline, lineWidth: 1.5))
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(PressableStyle()).sensoryFeedback(.success, trigger: chore.nextDue).accessibilityLabel("סמן \(chore.title) כבוצע").accessibilityIdentifier("chore-complete-\(chore.id)")
                    Button { editing = chore } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                if let e = chore.emoji, !e.isEmpty { Text(e).font(.hb(.subheadline)) }
                                Text(chore.title).font(.hb(.callout, .medium)).foregroundStyle(isDue ? Color.wellnessInk : Color.wellnessSecondary).multilineTextAlignment(.leading)
                            }
                            HStack(spacing: 6) {
                                Text(repeatText(chore)).font(.hb(.caption2, .medium)).padding(.horizontal, 7).frame(height: 20).background(Color.wellnessChip, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                if !s.text.isEmpty { Text(s.text).font(.hb(.caption2, .semibold)).foregroundStyle(s.color) }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("chore-open-\(chore.id)")
                    if !chore.assigneeIDs.isEmpty {
                        AssigneeButton(currentID: chore.assigneeIDs.first, size: 30, ids: chore.assigneeIDs, badge: true) { id in Task { await home.setAssignee(chore, to: id) } }.accessibilityIdentifier("chore-assignee-\(chore.id)")
                    } else {
                        AssigneeButton(currentID: nil, size: 30) { id in Task { await home.setAssignee(chore, to: id) } }.accessibilityIdentifier("chore-assignee-\(chore.id)")
                    }
                    ChoreHistoryButton(chore: chore)
                }
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.wellnessChip.opacity(0.45), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.wellnessHairline))
                .swipeToDelete { confirmDelete = chore }
            }
        }
        .sheet(item: $editing) { ChoreEditorSheet(chore: $0).environmentObject(home) }
        .confirmationDialog("למחוק את המטלה?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible) {
            Button("מחיקה", role: .destructive) { if let c = confirmDelete { Task { await home.delete(c) } }; confirmDelete = nil }
        }
    }
}

/// Last completions of a chore (who and when), in a small popover like the web app's history button.
struct ChoreHistoryButton: View {
    @EnvironmentObject private var home: HomeStore
    let chore: HChore
    @State private var open = false
    @State private var rows: [(who: String, when: Date)] = []
    @State private var loaded = false
    var body: some View {
        Button { open = true } label: { Image(systemName: "clock.arrow.circlepath").font(.system(size: 14, weight: .medium)).foregroundStyle(Color.wellnessSecondary).frame(width: 36, height: 44).contentShape(Rectangle()) }
            .buttonStyle(.plain).accessibilityLabel("היסטוריית ביצוע").accessibilityIdentifier("chore-history-\(chore.id)")
            .popover(isPresented: $open) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("היסטוריה").font(.hb(.caption, .semibold)).foregroundStyle(Color.wellnessSecondary)
                    if !loaded { ProgressView() }
                    else if rows.isEmpty { Text("עוד לא בוצע").font(.hb(.footnote)).foregroundStyle(Color.wellnessSecondary) }
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                        HStack { Text(r.who).font(.hb(.footnote)); Spacer(minLength: 16); Text(r.when, format: .dateTime.day().month(.abbreviated)).font(.hb(.footnote)).foregroundStyle(Color.wellnessSecondary) }
                    }
                }.padding(14).frame(minWidth: 230).presentationCompactAdaptation(.popover)
                    .task { rows = await home.completions(of: chore); loaded = true }
            }
    }
}

// MARK: - Quick add (the + button on the home tab)

struct QuickAddSheet: View {
    @EnvironmentObject private var home: HomeStore
    @Environment(\.dismiss) private var dismiss
    @State private var sectionID = ""
    @State private var title = ""
    @State private var quantity = ""
    @State private var freq = "weekly"
    @State private var interval = 1
    private var section: HSection? { home.sections.first { $0.id == sectionID } ?? home.currentSection }
    var body: some View {
        NavigationStack {
            Form {
                Section("מדור") {
                    Picker("מדור", selection: $sectionID) { ForEach(home.sections) { Text("\($0.emoji ?? "") \($0.name)").tag($0.id) } }.pickerStyle(.menu)
                }
                Section(section?.kind == "chores" ? "מטלה חוזרת" : section?.kind == "info" ? "הערה" : section?.kind == "shopping" ? "פריט לקנייה" : "משימה") {
                    TextField(section?.kind == "shopping" ? "מה צריך לקנות?" : "כותרת", text: $title).accessibilityIdentifier("quick-add-title")
                    if section?.kind == "shopping" { TextField("כמות (לא חובה)", text: $quantity).keyboardType(.decimalPad) }
                }
                if section?.kind == "chores" {
                    Section("תדירות") {
                        Picker("כל", selection: $freq) { Text("יום").tag("daily"); Text("שבוע").tag("weekly"); Text("חודש").tag("monthly") }.pickerStyle(.segmented)
                        Stepper("כל \(interval)", value: $interval, in: 1...60)
                    }
                }
            }
            .wellnessList().navigationTitle("הוספה").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ביטול") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("הוספה") { Task { await add() } }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || section == nil).accessibilityIdentifier("quick-add-save") }
            }
            .onAppear { sectionID = home.currentSection?.id ?? home.sections.first?.id ?? "" }
        }
    }
    @MainActor private func add() async {
        guard let section else { return }
        if section.kind == "chores" { await home.addChore(title: title, section: section, freq: freq, interval: interval) }
        else { await home.addTask(title: title, section: section, isNote: section.kind == "info", quantity: Double(quantity.replacingOccurrences(of: ",", with: "."))) }
        home.selectedSectionID = section.id
        dismiss()
    }
}

// MARK: - Calendar

struct CalendarScreen: View {
    @EnvironmentObject private var home: HomeStore
    @EnvironmentObject private var store: AppStore
    @State private var month = Date()
    @State private var selected: Date?
    @State private var editing: HEvent?
    @State private var subscribing = false
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = home.timeZone; c.firstWeekday = 1; c.locale = Locale(identifier: "he_IL"); return c }
    private struct Occurrence: Identifiable { let event: HEvent; let date: Date; var id: String { event.id + "\(date.timeIntervalSince1970)" } }
    private var monthStart: Date { cal.date(from: cal.dateComponents([.year, .month], from: month)) ?? month }
    private var occurrences: [Occurrence] {
        guard let range = cal.range(of: .day, in: .month, for: monthStart), let end = cal.date(byAdding: .day, value: range.count, to: monthStart) else { return [] }
        return home.events.compactMap { e -> Occurrence? in
            guard let d = e.nextOccurrence(from: monthStart, zone: home.timeZone), d >= monthStart, d < end else { return nil }
            return Occurrence(event: e, date: d)
        }.sorted { $0.date < $1.date }
    }
    private var shown: [Occurrence] { selected.map { day in occurrences.filter { cal.isDate($0.date, inSameDayAs: day) } } ?? occurrences }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text(monthStart, format: .dateTime.month(.wide).year()).font(.hb(.title, .bold))
                        Spacer()
                        Button { subscribing = true } label: { Image(systemName: "calendar.badge.plus").frame(width: 44, height: 44).background(Color.wellnessCard, in: Circle()) }.accessibilityLabel("הוספה ליומן שלי").accessibilityIdentifier("calendar-subscribe")
                        Button { step(-1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44).background(Color.wellnessCard, in: Circle()) }.accessibilityLabel("חודש קודם")
                        Button { step(1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44).background(Color.wellnessCard, in: Circle()) }.accessibilityLabel("חודש הבא")
                    }.foregroundStyle(Color.wellnessInk)
                    grid.wellnessCard(padding: 12)
                    Text(selected == nil ? "אירועי החודש" : selected!.formatted(.dateTime.weekday(.wide).day().month(.wide))).sectionTitle()
                    if shown.isEmpty { ContentUnavailableView("אין אירועים", systemImage: "calendar", description: Text("הוסף אירוע בכפתור +.")) }
                    ForEach(shown) { occ in
                        Button { editing = occ.event } label: { eventRow(occ) }.buttonStyle(PressableStyle()).accessibilityIdentifier("event-\(occ.event.id)")
                    }
                }.padding(20).padding(.bottom, 90)
            }.wellnessScreen().toolbar(.hidden, for: .navigationBar).refreshable { await home.refresh() }
            .sheet(isPresented: $subscribing) { SubscribeCalendarSheet().environmentObject(store) }
            .sheet(item: $editing) { EventEditorSheet(event: $0).environmentObject(home).presentationDragIndicator(.visible) }
        }
    }
    private func step(_ n: Int) { withAnimation(.snappy) { month = cal.date(byAdding: .month, value: n, to: month) ?? month; selected = nil } }
    private var grid: some View {
        let first = cal.component(.weekday, from: monthStart) - 1
        let days = cal.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let letters = ["א׳", "ב׳", "ג׳", "ד׳", "ה׳", "ו׳", "ש׳"]
        return VStack(spacing: 6) {
            HStack(spacing: 0) { ForEach(letters, id: \.self) { Text($0).font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary).frame(maxWidth: .infinity) } }
            let cells = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
            LazyVGrid(columns: cells, spacing: 4) {
                ForEach(0..<(first + days), id: \.self) { index in
                    if index < first { Color.clear.frame(height: 44) }
                    else {
                        let day = cal.date(byAdding: .day, value: index - first, to: monthStart) ?? monthStart
                        let has = occurrences.contains { cal.isDate($0.date, inSameDayAs: day) }
                        let isSel = selected.map { cal.isDate($0, inSameDayAs: day) } ?? false
                        Button { withAnimation(.snappy) { selected = isSel ? nil : day } } label: {
                            VStack(spacing: 3) {
                                Text("\(index - first + 1)").font(.hb(.callout, cal.isDateInToday(day) ? .bold : .regular)).monospacedDigit()
                                Circle().fill(has ? Color.kcalAmber : .clear).frame(width: 5, height: 5)
                            }.frame(maxWidth: .infinity, minHeight: 44).foregroundStyle(isSel ? Color.wellnessOnPrimary : Color.wellnessInk)
                                .background { if isSel { Circle().fill(Color.wellnessPrimary) } else if cal.isDateInToday(day) { Circle().strokeBorder(Color.wellnessInk, lineWidth: 1.5) } }
                        }.buttonStyle(.plain).accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide)) + (has ? ", יש אירועים" : ""))
                    }
                }
            }
        }
    }
    private func eventRow(_ occ: Occurrence) -> some View {
        let e = occ.event
        let tint: Color = e.kind == "birthday" ? .fatCoral : e.kind == "medical" ? .proteinBlue : .carbsGold
        return HStack(spacing: 12) {
            VStack(spacing: 0) { Text(occ.date, format: .dateTime.day()).font(.hb(.title3, .bold)).monospacedDigit(); Text(occ.date, format: .dateTime.month(.abbreviated)).font(.hb(.caption2)) }
                .frame(width: 52, height: 56).background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous)).foregroundStyle(Color.wellnessInk)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) { Text(e.emoji ?? (e.kind == "birthday" ? "🎂" : e.kind == "medical" ? "🩺" : "📌")); Text(e.title).font(.hb(.headline, .semibold)).foregroundStyle(Color.wellnessInk) }
                Text((e.kind == "birthday" ? "יום הולדת" : e.kind == "medical" ? "רפואי" : "אירוע") + (e.recurrence == "yearly" ? " · כל שנה" : "")).font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.wellnessCard(padding: 12)
    }
}

struct EventEditorSheet: View {
    @EnvironmentObject private var home: HomeStore
    @Environment(\.dismiss) private var dismiss
    let event: HEvent?
    @State private var title = ""
    @State private var kind = "other"
    @State private var date = Date()
    @State private var yearly = false
    @State private var notes = ""
    @State private var confirmDelete = false
    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("כותרת", text: $title).accessibilityIdentifier("event-title"); TextField("הערות", text: $notes, axis: .vertical).lineLimit(1...5) }
                Section("סוג") { Picker("סוג", selection: $kind) { Text("יום הולדת").tag("birthday"); Text("רפואי").tag("medical"); Text("אחר").tag("other") }.pickerStyle(.segmented).onChange(of: kind) { _, k in if event == nil { yearly = k == "birthday" } } }
                Section { DatePicker("תאריך", selection: $date, displayedComponents: .date).environment(\.locale, Locale(identifier: "he_IL")); Toggle("חוזר כל שנה", isOn: $yearly).tint(Color.wellnessPrimary) }
                if event != nil { Section { Button("מחיקה", role: .destructive) { confirmDelete = true }.frame(maxWidth: .infinity) } }
            }
            .wellnessList().navigationTitle(event == nil ? "אירוע חדש" : "עריכת אירוע").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ביטול") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("שמירה") { Task { await home.saveEvent(id: event?.id, title: title, kind: kind, date: date, yearly: yearly, notes: notes, emoji: event?.emoji); dismiss() } }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty).accessibilityIdentifier("event-save") }
            }
            .confirmationDialog("למחוק את האירוע?", isPresented: $confirmDelete, titleVisibility: .visible) { Button("מחיקה", role: .destructive) { if let event { Task { await home.delete(event); dismiss() } } } }
            .onAppear {
                guard let event else { return }
                title = event.title; kind = event.kind; yearly = event.recurrence == "yearly"; notes = event.notes ?? ""; date = DateParsing.day(event.eventDate, zone: home.timeZone) ?? Date()
            }
        }
    }
}

/// Full chore editor (the web app's chore sheet): title, emoji, notes, frequency, weekdays, assignees.
struct ChoreEditorSheet: View {
    @EnvironmentObject private var home: HomeStore
    @Environment(\.dismiss) private var dismiss
    let chore: HChore
    @State private var title = ""
    @State private var emoji = ""
    @State private var notes = ""
    @State private var freq = "weekly"
    @State private var interval = 1
    @State private var weekdays: Set<Int> = []
    @State private var anyone = true
    @State private var assignees: Set<String> = []
    @State private var confirmDelete = false
    private static let dayNames = ["א׳", "ב׳", "ג׳", "ד׳", "ה׳", "ו׳", "ש׳"]
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 10) {
                        TextField("🧹", text: $emoji).multilineTextAlignment(.center).frame(width: 54).onChange(of: emoji) { _, v in if v.count > 4 { emoji = String(v.prefix(4)) } }
                        TextField("שם המטלה", text: $title).font(.hb(.headline, .semibold)).accessibilityIdentifier("chore-title")
                    }
                    TextField("הערות", text: $notes, axis: .vertical).lineLimit(1...5)
                }
                Section("תדירות") {
                    Picker("תדירות", selection: $freq) { Text("יומי").tag("daily"); Text("שבועי").tag("weekly"); Text("חודשי").tag("monthly"); Text("לפי הצורך").tag("as_needed") }.pickerStyle(.segmented)
                    if freq != "as_needed" { Stepper(value: $interval, in: 1...60) { Text("כל \(interval) \(unit)").font(.hb(.body)) } }
                    if freq == "weekly" {
                        HStack(spacing: 6) {
                            ForEach(0..<7, id: \.self) { d in
                                Button { if weekdays.contains(d) { weekdays.remove(d) } else { weekdays.insert(d) } } label: {
                                    Text(Self.dayNames[d]).font(.hb(.subheadline, .semibold)).frame(maxWidth: .infinity, minHeight: 40)
                                        .foregroundStyle(weekdays.contains(d) ? Color.wellnessOnPrimary : Color.wellnessInk)
                                        .background(weekdays.contains(d) ? Color.wellnessPrimary : Color.wellnessChip, in: Capsule())
                                }.buttonStyle(.plain).accessibilityAddTraits(weekdays.contains(d) ? [.isSelected] : [])
                            }
                        }.padding(.vertical, 4)
                    }
                }
                Section("מי אחראי") {
                    Picker("אחראי", selection: $anyone) { Text("כל אחד").tag(true); Text("אנשים מסוימים").tag(false) }.pickerStyle(.segmented)
                    if !anyone {
                        ForEach(home.members) { m in
                            Button { if assignees.contains(m.id) { assignees.remove(m.id) } else { assignees.insert(m.id) } } label: {
                                HStack(spacing: 12) { MemberAvatar(member: m, size: 32); Text(m.name).foregroundStyle(Color.wellnessInk); Spacer(); if assignees.contains(m.id) { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.wellnessInk) } }.frame(minHeight: 44)
                            }.accessibilityAddTraits(assignees.contains(m.id) ? [.isSelected] : [])
                        }
                    }
                }
                AttachmentsSection(choreID: chore.id)
                Section { Button("מחיקה", role: .destructive) { confirmDelete = true }.frame(maxWidth: .infinity) }
            }
            .wellnessList().navigationTitle("עריכת מטלה").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ביטול") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("שמירה") { Task { await save(); dismiss() } }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty).accessibilityIdentifier("chore-save") }
            }
            .onAppear { title = chore.title; emoji = chore.emoji ?? ""; notes = chore.notes ?? ""; freq = chore.freq; interval = max(1, chore.intervalN); weekdays = Set(chore.weekdays)
                anyone = chore.assigneeIDs.isEmpty; assignees = Set(chore.assigneeIDs) }
            .confirmationDialog("למחוק את המטלה?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("מחיקה", role: .destructive) { Task { await home.delete(chore); dismiss() } }
            }
        }
    }
    private var unit: String { freq == "daily" ? "ימים" : freq == "weekly" ? "שבועות" : "חודשים" }
    private func save() async {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 300 else { return }
        let ids = home.members.map(\.id).filter { assignees.contains($0) && !anyone }
        let days = freq == "weekly" ? weekdays.sorted() : []
        let fields: [String: JSONValue] = [
            "title": .string(clean), "emoji": emoji.isEmpty ? .null : .string(emoji), "notes": notes.isEmpty ? .null : .string(String(notes.prefix(2000))),
            "freq": .string(freq), "interval_n": .number(Double(interval)), "weekdays": days.isEmpty ? .null : .array(days.map { .number(Double($0)) }),
            "assignee_kind": .string(ids.isEmpty ? "anyone" : "member"), "assignee_member_ids": .array(ids.map { .string($0) }), "assignee_member_id": ids.first.map { .string($0) } ?? .null]
        await home.update(chore, fields: fields) { c in
            c.title = clean; c.emoji = emoji.isEmpty ? nil : emoji; c.notes = notes.isEmpty ? nil : notes; c.freq = freq; c.intervalN = interval; c.weekdays = days
            c.assigneeIDs = ids; c.assigneeKind = ids.isEmpty ? "anyone" : "member"
        }
    }
}

/// How to subscribe to the family calendar from Apple/Google Calendar (the web app's subscribe dialog).
struct SubscribeCalendarSheet: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var copied = false
    private var feed: URL? { store.backend?.calendarFeedURL }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let feed {
                        Button { if var c = URLComponents(url: feed, resolvingAgainstBaseURL: false) { c.scheme = "webcal"; if let url = c.url { openURL(url) } } } label: { Label("פתיחה ביומן", systemImage: "calendar.badge.plus").font(.hb(.headline, .semibold)) }.accessibilityIdentifier("calendar-open")
                        HStack {
                            Text(feed.absoluteString).font(.footnote.monospaced()).foregroundStyle(Color.wellnessSecondary).lineLimit(2).environment(\.layoutDirection, .leftToRight).textSelection(.enabled)
                            Spacer(minLength: 8)
                            Button { UIPasteboard.general.string = feed.absoluteString; copied = true } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc").frame(width: 44, height: 44) }.buttonStyle(.plain).accessibilityLabel("העתקת קישור היומן")
                        }
                    } else { Text("הקישור ליומן אינו זמין כרגע.").foregroundStyle(Color.wellnessSecondary) }
                } footer: { Text("בטלפון זה פותח את אפליקציית היומן ומציע להוסיף את הלוח כמנוי. אם לא קרה כלום, השתמשו בקישור.") }
                Section("יומן Apple (iPhone / Mac)") { Text("הגדרות ← יומן ← חשבונות ← הוספת חשבון ← אחר ← \"הוספת יומן מנוי\" ← הדביקו את הקישור.").font(.hb(.subheadline)).foregroundStyle(Color.wellnessSecondary) }
                Section("Google Calendar (במחשב)") { Text("היכנסו ל-calendar.google.com ← ליד \"יומנים אחרים\" לחצו על + ← \"לפי כתובת URL\" ← הדביקו את הקישור שהעתקתם.").font(.hb(.subheadline)).foregroundStyle(Color.wellnessSecondary) }
            }
            .wellnessList().navigationTitle("הוספה ליומן שלי").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("סגור") { dismiss() } } }
        }
    }
}
