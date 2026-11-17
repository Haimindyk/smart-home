import SwiftUI
import WellnessCore

// MARK: - Chores

struct ChoreList: View {
    @EnvironmentObject private var home: HomeStore
    let section: HSection
    @State private var confirmDelete: HChore?
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
        List {
            let chores = home.chores(in: section.id)
            if chores.isEmpty { ContentUnavailableView("אין מטלות", systemImage: "arrow.triangle.2.circlepath", description: Text("הוסף מטלה חוזרת בכפתור +.")).listRowSeparator(.hidden).listRowBackground(Color.clear) }
            ForEach(chores) { chore in
                let s = status(chore)
                HStack(spacing: 12) {
                    Text(chore.emoji ?? "🧹").font(.title2).frame(width: 46, height: 46).background(Color.wellnessChip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(chore.title).font(.headline).foregroundStyle(Color.wellnessInk).multilineTextAlignment(.leading)
                        HStack(spacing: 8) { Text(s.text).font(.caption.weight(.semibold)).foregroundStyle(s.color); Text(repeatText(chore)).font(.caption).foregroundStyle(Color.wellnessSecondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Button { Task { await home.complete(chore) } } label: { Label("בוצע", systemImage: "checkmark").font(.subheadline.weight(.semibold)).padding(.horizontal, 14).frame(minHeight: 44).foregroundStyle(Color.wellnessOnInk).background(Color.wellnessInk, in: Capsule()) }
                        .buttonStyle(PressableStyle()).sensoryFeedback(.success, trigger: chore.nextDue).accessibilityLabel("סמן \(chore.title) כבוצע").accessibilityIdentifier("chore-complete-\(chore.id)")
                }.wellnessCard(padding: 14).listRowSeparator(.hidden).listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                .swipeActions { Button(role: .destructive) { confirmDelete = chore } label: { Label("מחיקה", systemImage: "trash") } }
            }
            Color.clear.frame(height: 90).listRowSeparator(.hidden).listRowBackground(Color.clear)
        }
        .listStyle(.plain).scrollContentBackground(.hidden).refreshable { await home.refresh() }
        .confirmationDialog("למחוק את המטלה?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }), titleVisibility: .visible) {
            Button("מחיקה", role: .destructive) { if let c = confirmDelete { Task { await home.delete(c) } }; confirmDelete = nil }
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
            .scrollContentBackground(.hidden).background(Color.wellnessCanvas).navigationTitle("הוספה").navigationBarTitleDisplayMode(.inline)
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
    @State private var month = Date()
    @State private var selected: Date?
    @State private var editing: HEvent?
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
                        Text(monthStart, format: .dateTime.month(.wide).year()).font(.title.bold())
                        Spacer()
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
            .sheet(item: $editing) { EventEditorSheet(event: $0).environmentObject(home).presentationDragIndicator(.visible) }
        }
    }
    private func step(_ n: Int) { withAnimation(.snappy) { month = cal.date(byAdding: .month, value: n, to: month) ?? month; selected = nil } }
    private var grid: some View {
        let first = cal.component(.weekday, from: monthStart) - 1
        let days = cal.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let letters = ["א׳", "ב׳", "ג׳", "ד׳", "ה׳", "ו׳", "ש׳"]
        return VStack(spacing: 6) {
            HStack(spacing: 0) { ForEach(letters, id: \.self) { Text($0).font(.caption).foregroundStyle(Color.wellnessSecondary).frame(maxWidth: .infinity) } }
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
                                Text("\(index - first + 1)").font(.callout.weight(cal.isDateInToday(day) ? .bold : .regular).monospacedDigit())
                                Circle().fill(has ? Color.kcalAmber : .clear).frame(width: 5, height: 5)
                            }.frame(maxWidth: .infinity, minHeight: 44).foregroundStyle(isSel ? Color.wellnessOnInk : Color.wellnessInk)
                                .background { if isSel { Circle().fill(Color.wellnessInk) } else if cal.isDateInToday(day) { Circle().strokeBorder(Color.wellnessInk, lineWidth: 1.5) } }
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
            VStack(spacing: 0) { Text(occ.date, format: .dateTime.day()).font(.title3.bold().monospacedDigit()); Text(occ.date, format: .dateTime.month(.abbreviated)).font(.caption2) }
                .frame(width: 52, height: 56).background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous)).foregroundStyle(Color.wellnessInk)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) { Text(e.emoji ?? (e.kind == "birthday" ? "🎂" : e.kind == "medical" ? "🩺" : "📌")); Text(e.title).font(.headline).foregroundStyle(Color.wellnessInk) }
                Text((e.kind == "birthday" ? "יום הולדת" : e.kind == "medical" ? "רפואי" : "אירוע") + (e.recurrence == "yearly" ? " · כל שנה" : "")).font(.caption).foregroundStyle(Color.wellnessSecondary)
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
                Section { DatePicker("תאריך", selection: $date, displayedComponents: .date).environment(\.locale, Locale(identifier: "he_IL")); Toggle("חוזר כל שנה", isOn: $yearly).tint(Color.wellnessInk) }
                if event != nil { Section { Button("מחיקה", role: .destructive) { confirmDelete = true }.frame(maxWidth: .infinity) } }
            }
            .scrollContentBackground(.hidden).background(Color.wellnessCanvas).navigationTitle(event == nil ? "אירוע חדש" : "עריכת אירוע").navigationBarTitleDisplayMode(.inline)
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
