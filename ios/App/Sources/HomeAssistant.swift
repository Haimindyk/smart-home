import SwiftUI
import WellnessCore

/// Household assistant chat (the web app's assistant dialog): ask in Hebrew, review proposed actions, confirm them one by one.
struct AssistantSheet: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var home: HomeStore
    @Environment(\.dismiss) private var dismiss
    private struct Message: Identifiable { let id = UUID(); let mine: Bool; let text: String; var actions: [JSONValue] = [] }
    @State private var messages: [Message] = []
    @State private var applied: Set<String> = []
    @State private var text = ""
    @State private var sending = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if messages.isEmpty { intro }
                            ForEach(messages) { m in bubble(m).id(m.id) }
                            if sending { HStack(spacing: 8) { ProgressView(); Text("העוזר חושב…").font(.hb(.footnote)).foregroundStyle(Color.wellnessSecondary) } }
                            Color.clear.frame(height: 1).id("end")
                        }.padding(16)
                    }.scrollDismissesKeyboard(.interactively).onChange(of: messages.count) { _, _ in withAnimation { proxy.scrollTo("end") } }
                }
                composer
            }
            .wellnessScreen().navigationTitle("העוזר של הבית").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("סגור") { dismiss() } } }
        }
    }
    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("בקש מהעוזר לעזור בבית", systemImage: "sparkles").font(.hb(.headline, .semibold))
            Text("למשל: \"תוסיף חלב וביצים לרשימת הקניות\" או \"תזכיר לי יום הולדת לנועה ב־22 בנובמבר\". העוזר מציע פעולות, ורק אחרי שתאשר אותן הן מתבצעות.").font(.hb(.footnote)).foregroundStyle(Color.wellnessSecondary)
        }.wellnessCard()
    }
    private func bubble(_ m: Message) -> some View {
        VStack(alignment: m.mine ? .trailing : .leading, spacing: 8) {
            HStack { if !m.mine { Spacer(minLength: 40) }
                Text(m.text).font(.hb(.body)).padding(.horizontal, 16).padding(.vertical, 12).foregroundStyle(m.mine ? Color.wellnessOnPrimary : Color.wellnessInk)
                    .background(m.mine ? Color.wellnessPrimary : Color.wellnessCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(m.mine ? .clear : Color.wellnessHairline)).textSelection(.enabled)
                if m.mine { Spacer(minLength: 40) } }
            ForEach(Array(m.actions.enumerated()), id: \.offset) { index, action in
                let key = "\(m.id.uuidString)-\(index)"
                HStack(spacing: 10) {
                    Image(systemName: applied.contains(key) ? "checkmark.circle.fill" : "wand.and.stars").foregroundStyle(applied.contains(key) ? Color.kindShopping : Color.wellnessSecondary)
                    Text(home.describe(action)).font(.hb(.subheadline)).foregroundStyle(Color.wellnessInk).frame(maxWidth: .infinity, alignment: .leading)
                    if !applied.contains(key) {
                        Button { Task { if await home.perform(action) { applied.insert(key) } } } label: { Text("אישור").font(.hb(.subheadline, .semibold)).lineLimit(1).fixedSize().padding(.horizontal, 14).frame(minHeight: 40).foregroundStyle(Color.wellnessOnPrimary).background(Color.wellnessPrimary, in: Capsule()) }
                            .buttonStyle(PressableStyle()).disabled(!HomeStore.applicableActions.contains(action.str("type") ?? "")).accessibilityIdentifier("assistant-confirm-\(index)")
                    } else { Text("בוצע").font(.hb(.caption, .semibold)).foregroundStyle(Color.wellnessSecondary) }
                }.padding(12).background(Color.wellnessCard, in: RoundedRectangle(cornerRadius: 16, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.wellnessHairline))
            }
        }
    }
    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("מה לעשות בבית?", text: $text, axis: .vertical).lineLimit(1...4).padding(.horizontal, 14).padding(.vertical, 12)
                .background(Color.wellnessCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.wellnessHairline))
                .accessibilityIdentifier("assistant-field")
            Button { Task { await send() } } label: {
                Image(systemName: "arrow.up").font(.headline.weight(.bold)).foregroundStyle(Color.wellnessOnPrimary).frame(width: 46, height: 46).background(Color.wellnessPrimary.opacity(canSend ? 1 : 0.3), in: Circle())
            }.buttonStyle(PressableStyle()).disabled(!canSend).accessibilityLabel("שליחה").accessibilityIdentifier("assistant-send")
        }.padding(.horizontal, 16).padding(.vertical, 10).background(Color.wellnessCanvas)
    }
    private var canSend: Bool { !sending && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    @MainActor private func send() async {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        messages.append(Message(mine: true, text: message)); text = ""; sending = true; defer { sending = false }
        var body: [String: JSONValue] = ["intent": .string("chat"), "message": .string(message)]
        if let me = home.me { body["memberId"] = .string(me.id) }
        switch await store.call("assistant", .object(body)) {
        case .success(let result): messages.append(Message(mine: false, text: result["reply"].stringValue ?? "אין לי תשובה כרגע.", actions: result["proposedActions"].arrayValue))
        case .failure(let e): messages.append(Message(mine: false, text: e == .connection ? "אין חיבור לשרת. נסה שוב בעוד רגע." : "העוזר לא זמין כרגע."))
        }
    }
}
