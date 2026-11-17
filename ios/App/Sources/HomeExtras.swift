import SwiftUI
import WellnessCore

// MARK: - Section editor

struct SectionEditorSheet: View {
    @EnvironmentObject private var home: HomeStore
    @Environment(\.dismiss) private var dismiss
    let section: HSection?
    @State private var name = ""
    @State private var emoji = ""
    @State private var kind = "tasks"
    @State private var confirmDelete = false
    private let kinds = [("tasks", "משימות"), ("shopping", "קניות"), ("chores", "מטלות"), ("info", "מידע")]
    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("שם המדור", text: $name).accessibilityIdentifier("section-name"); TextField("אימוג׳י (לא חובה)", text: $emoji) }
                if section == nil {
                    Section("סוג") { Picker("סוג", selection: $kind) { ForEach(kinds, id: \.0) { Text($0.1).tag($0.0) } }.pickerStyle(.segmented) }
                } else {
                    Section { Button("מחיקת המדור", role: .destructive) { confirmDelete = true }.frame(maxWidth: .infinity) } footer: { Text("המשימות והמטלות שבמדור יימחקו איתו.") }
                }
            }
            .scrollContentBackground(.hidden).background(Color.wellnessCanvas).navigationTitle(section == nil ? "מדור חדש" : "עריכת מדור").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("ביטול") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("שמירה") { Task { if let section { await home.rename(section, name: name, emoji: emoji) } else { await home.addSection(name: name, emoji: emoji, kind: kind) }; dismiss() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty).accessibilityIdentifier("section-save")
                }
            }
            .confirmationDialog("למחוק את המדור?", isPresented: $confirmDelete, titleVisibility: .visible) { Button("מחיקה", role: .destructive) { if let section { Task { await home.delete(section); dismiss() } } } }
            .onAppear { if let section { name = section.name; emoji = section.emoji ?? ""; kind = section.kind } }
        }
    }
}

// MARK: - History

struct HistorySheet: View {
    @EnvironmentObject private var home: HomeStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if home.activity.isEmpty { ContentUnavailableView("אין עדיין פעילות", systemImage: "clock.arrow.circlepath", description: Text("שינויים שמבצעים בבית יופיעו כאן.")).listRowBackground(Color.clear) }
                ForEach(home.activity) { item in
                    HStack(alignment: .top, spacing: 12) {
                        MemberAvatar(member: item.actorID.flatMap { home.member($0) }, size: 36)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.summary.isEmpty ? "\(item.entityType) · \(item.action)" : item.summary).font(.hb(.body)).foregroundStyle(Color.wellnessInk)
                            if let when = item.createdAt { Text(when, format: .relative(presentation: .named)).font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary) }
                        }
                    }.accessibilityElement(children: .combine)
                }
            }
            .wellnessList().navigationTitle("היסטוריה").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("סגור") { dismiss() } } }
            .task { await home.loadActivity() }
        }
    }
}

// MARK: - Members

struct MembersSheet: View {
    @EnvironmentObject private var home: HomeStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("בני הבית") {
                    ForEach(home.members) { m in
                        HStack(spacing: 14) {
                            MemberAvatar(member: m, size: 44)
                            Text(m.name).font(.hb(.headline, .semibold))
                            Spacer()
                            if m.id == home.me?.id { Text("זה אתה").font(.hb(.caption, .semibold)).padding(.horizontal, 10).padding(.vertical, 4).background(Color.wellnessChip, in: Capsule()) }
                        }.frame(minHeight: 52).accessibilityElement(children: .combine)
                    }
                }
            }
            .wellnessList().navigationTitle("בני הבית").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("סגור") { dismiss() } } }
        }
    }
}

// MARK: - Search

struct SearchSheet: View {
    @EnvironmentObject private var home: HomeStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    private struct Hit: Identifiable { let id: String; let icon: String; let title: String; let subtitle: String; let sectionID: String?; let tab: Int }
    private var hits: [Hit] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard q.count >= 1 else { return [] }
        var list: [Hit] = []
        for t in home.tasks where t.title.lowercased().contains(q) || (t.notes ?? "").lowercased().contains(q) {
            list.append(Hit(id: "t" + t.id, icon: t.isCompleted ? "checkmark.circle" : "circle", title: t.title, subtitle: home.sections.first { $0.id == t.sectionID }?.name ?? "", sectionID: t.sectionID, tab: 0))
        }
        for c in home.chores where c.title.lowercased().contains(q) {
            list.append(Hit(id: "c" + c.id, icon: "arrow.triangle.2.circlepath", title: c.title, subtitle: home.sections.first { $0.id == c.sectionID }?.name ?? "", sectionID: c.sectionID, tab: 0))
        }
        for e in home.events where e.title.lowercased().contains(q) || (e.notes ?? "").lowercased().contains(q) {
            list.append(Hit(id: "e" + e.id, icon: "calendar", title: e.title, subtitle: e.eventDate, sectionID: nil, tab: 1))
        }
        return list
    }
    var body: some View {
        NavigationStack {
            List {
                if !query.isEmpty && hits.isEmpty { ContentUnavailableView.search(text: query).listRowBackground(Color.clear) }
                ForEach(hits) { hit in
                    Button { if let id = hit.sectionID { home.selectedSectionID = id }; dismiss() } label: {
                        HStack(spacing: 12) {
                            Image(systemName: hit.icon).foregroundStyle(Color.wellnessSecondary).frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) { Text(hit.title).foregroundStyle(Color.wellnessInk); Text(hit.subtitle).font(.hb(.caption)).foregroundStyle(Color.wellnessSecondary) }
                        }.frame(minHeight: 44)
                    }.accessibilityElement(children: .combine)
                }
            }
            .wellnessList().searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "חיפוש משימות, מטלות ואירועים")
            .navigationTitle("חיפוש").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("סגור") { dismiss() } } }
        }
    }
}
