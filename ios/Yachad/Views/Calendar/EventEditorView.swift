import SwiftUI

struct EventEditorView: View {
    @ObservedObject var store: AreaWorkspaceStore
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var kind: CalendarEventKind = .other
    @State private var date = Date()
    @State private var recurrence: CalendarEventRecurrence = .none
    @State private var notes = ""
    @State private var isSaving = false
    @State private var error: String?

    private var locale: AppLocale { appState.locale }

    var body: some View {
        NavigationStack {
            Form {
                TextField(locale == .he ? "כותרת" : "Title", text: $title)
                Picker(locale == .he ? "סוג" : "Kind", selection: $kind) {
                    ForEach(CalendarEventKind.allCases) { kind in
                        Text("\(kind.emoji) \(kindLabel(kind))").tag(kind)
                    }
                }
                DatePicker(locale == .he ? "תאריך" : "Date", selection: $date, displayedComponents: .date)
                Toggle(locale == .he ? "חוזר כל שנה" : "Repeats yearly", isOn: Binding(
                    get: { recurrence == .yearly },
                    set: { recurrence = $0 ? .yearly : .none }
                ))
                TextField(locale == .he ? "הערות" : "Notes", text: $notes, axis: .vertical)

                if let error {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }
            }
            .navigationTitle(locale == .he ? "אירוע חדש" : "New event")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(locale == .he ? "ביטול" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(locale == .he ? "יצירה" : "Create") { Task { await save() } }
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }

    private func kindLabel(_ kind: CalendarEventKind) -> String {
        switch (kind, locale) {
        case (.birthday, .he): return "יום הולדת"
        case (.birthday, .en): return "Birthday"
        case (.medical, .he): return "רפואי"
        case (.medical, .en): return "Medical"
        case (.other, .he): return "אחר"
        case (.other, .en): return "Other"
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await CalendarService().createEvent(
                areaId: store.area.id, title: title.trimmingCharacters(in: .whitespaces), emoji: nil,
                notes: notes.isEmpty ? nil : notes, kind: kind, date: date, endDate: nil,
                recurrence: recurrence, actorId: store.myMemberId
            )
            await store.loadAll()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
