import SwiftUI

struct CreateAreaView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @AppStorage("yachad.myNickname") private var myNickname: String = ""

    @State private var name = ""
    @State private var emoji = "🏠"
    @State private var nickname = ""
    @State private var isSaving = false
    @State private var error: String?
    @State private var createdArea: Area?

    private var locale: AppLocale { appState.locale }
    private static let emojiChoices = ["🏠", "👨‍👩‍👧‍👦", "🏡", "🎓", "🏢", "🧑‍🤝‍🧑", "🌱", "🐾"]

    var body: some View {
        NavigationStack {
            Form {
                Section(locale == .he ? "פרטי האזור" : "Area details") {
                    TextField(locale == .he ? "שם (למשל: הבית שלנו)" : "Name (e.g. Our home)", text: $name)
                    Picker(locale == .he ? "אימוג'י" : "Emoji", selection: $emoji) {
                        ForEach(Self.emojiChoices, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section(locale == .he ? "איך לקרוא לך באזור הזה" : "How to address you in this area") {
                    TextField(locale == .he ? "שם/כינוי" : "Name/nickname", text: $nickname)
                }
                if let error {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }
            }
            .navigationTitle(locale == .he ? "אזור חדש" : "New area")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(locale == .he ? "ביטול" : "Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(locale == .he ? "יצירה" : "Create") { Task { await create() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || nickname.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear { if nickname.isEmpty { nickname = myNickname } }
            .sheet(item: $createdArea, onDismiss: { dismiss() }) { area in
                AreaInviteShareView(area: area, isFirstTime: true)
            }
        }
    }

    private func create() async {
        isSaving = true
        error = nil
        defer { isSaving = false }
        do {
            let area = try await appState.areaService.createArea(
                name: name.trimmingCharacters(in: .whitespaces),
                emoji: emoji,
                nickname: nickname.trimmingCharacters(in: .whitespaces)
            )
            await appState.refreshAreas()
            createdArea = area
        } catch {
            self.error = error.localizedDescription
        }
    }
}
