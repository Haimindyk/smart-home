import SwiftUI
import WellnessCore

/// Coach chat backed by the existing `wellness-chat` function (state / send / clear), same limits as the web app.
struct CoachChatView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var turns: [JSONValue] = []
    @State private var used = 0
    @State private var limit = 0
    @State private var version = 0
    @State private var generation = ""
    @State private var available = true
    @State private var loaded = false
    @State private var text = ""
    @State private var includeDiary = false
    @State private var sending = false
    @State private var error: String?
    @State private var retryID: String?
    @State private var retryText = ""
    @State private var confirmClear = false
    var body: some View {
        NavigationStack {
            Group {
                if !store.aiEligible {
                    ContentUnavailableView("המאמן זמין מגיל 18", systemImage: "person.crop.circle.badge.exclamationmark", description: Text("השלם תאריך לידה בפרופיל באפליקציה הרגילה כדי להפעיל את המאמן."))
                } else if !store.aiConsented { AIConsentView() }
                else { chat }
            }
            .wellnessScreen().navigationTitle("המאמן שלי").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("סגור") { dismiss() } }
                if store.aiEligible && store.aiConsented && !turns.isEmpty { ToolbarItem(placement: .primaryAction) { Menu { Button("מחיקת השיחה", role: .destructive) { confirmClear = true } } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("אפשרויות שיחה") } }
            }
            .confirmationDialog("למחוק את היסטוריית השיחה?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("מחיקה", role: .destructive) { Task { await clear() } }
            } message: { Text("המכסה היומית לא מתאפסת.") }
            .task(id: store.aiConsented) { if store.aiEligible && store.aiConsented { await load() } }
        }
    }
    private var chat: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if turns.isEmpty && loaded { intro }
                        ForEach(turns, id: \.["id"].stringValue) { turn in
                            bubble(turn["user_text"].stringValue ?? "", mine: true)
                            let answer = turn["answer"]
                            VStack(alignment: .leading, spacing: 8) {
                                bubble(answer["reply"].stringValue ?? "", mine: false)
                                if turn["id"].stringValue == turns.last?["id"].stringValue {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack { ForEach(answer["followUps"].arrayValue.compactMap(\.stringValue), id: \.self) { f in
                                            Button(f) { text = f }.font(.hb(.footnote)).padding(.horizontal, 12).padding(.vertical, 8).background(Color.wellnessCard, in: Capsule()).overlay(Capsule().strokeBorder(Color.wellnessHairline)).buttonStyle(PressableStyle())
                                        } }
                                    }
                                }
                            }
                        }
                        if sending { HStack(spacing: 8) { ProgressView(); Text("המאמן חושב…").font(.hb(.footnote)).foregroundStyle(Color.wellnessSecondary) }.id("typing") }
                        Color.clear.frame(height: 1).id("end")
                    }.padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: turns.count) { _, _ in withAnimation { proxy.scrollTo("end") } }
                .onChange(of: sending) { _, _ in withAnimation { proxy.scrollTo("end") } }
            }
            if let error { Text(error).font(.hb(.footnote)).foregroundStyle(Color.fatCoral).padding(.horizontal, 16).padding(.bottom, 6).frame(maxWidth: .infinity, alignment: .leading) }
            composer
        }
    }
    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("שאל על תזונה, אימונים וטכניקה", systemImage: "sparkles").font(.hb(.headline, .semibold))
            Text("מידע כללי ב־AI, לא תחליף לתזונאי או לאיש מקצוע רפואי. השיחה פרטית ונשמרת עד 30 יום; רק ההודעות האחרונות נשלחות. סיכום יומן נשלח רק בסימון שלך, ללא תמונות, שם או הערות אישיות. הצ׳אט לא משנה יומן או תוכנית.")
                .font(.hb(.footnote)).foregroundStyle(Color.wellnessSecondary)
        }.wellnessCard()
    }
    private func bubble(_ message: String, mine: Bool) -> some View {
        HStack { if !mine { Spacer(minLength: 40) }
            Text(message).padding(.horizontal, 16).padding(.vertical, 12)
                .foregroundStyle(mine ? Color.wellnessOnPrimary : Color.wellnessInk)
                .background(mine ? Color.wellnessInk : Color.wellnessCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(mine ? .clear : Color.wellnessHairline))
                .textSelection(.enabled)
            if mine { Spacer(minLength: 40) } }
    }
    private var composer: some View {
        VStack(spacing: 8) {
            Toggle("שתף סיכום יומן עם המאמן", isOn: $includeDiary).font(.hb(.footnote)).tint(Color.wellnessPrimary)
            HStack(alignment: .bottom, spacing: 10) {
                TextField("שאל שאלה על תזונה…", text: $text, axis: .vertical).lineLimit(1...5).padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Color.wellnessCard, in: RoundedRectangle(cornerRadius: 22, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.wellnessHairline))
                    .onChange(of: text) { _, value in if value.count > 2000 { text = String(value.prefix(2000)) } }
                Button { Task { await send() } } label: {
                    Image(systemName: "arrow.up").font(.hb(.headline, .bold)).foregroundStyle(Color.wellnessOnPrimary).frame(width: 46, height: 46).background(Color.wellnessPrimary.opacity(canSend ? 1 : 0.3), in: Circle())
                }.buttonStyle(PressableStyle()).disabled(!canSend).accessibilityLabel("שליחה")
            }
            if limit > 0 { Text("\(used)/\(limit) הודעות היום").font(.hb(.caption2)).foregroundStyle(Color.wellnessSecondary) }
        }.padding(.horizontal, 16).padding(.vertical, 10).background(Color.wellnessCanvas)
    }
    private var canSend: Bool { !sending && available && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (limit == 0 || used < limit) }
    private func message(for error: BackendError) -> String {
        switch error {
        case .connection: return "אין חיבור לשרת. נסה שוב בעוד רגע."
        case .conflict: return "השיחה השתנתה במקום אחר. רענן ונסה שוב."
        default: return "המאמן לא זמין כרגע. אפשר לנסות שוב מאוחר יותר."
        }
    }
    private func apply(_ state: JSONValue) {
        turns = state["turns"].arrayValue; used = Int(state["used"].doubleValue ?? 0); limit = Int(state["limit"].doubleValue ?? 0)
        version = Int(state["version"].doubleValue ?? 0); generation = state["generation"].stringValue ?? ""
        available = state["available"].boolValue ?? true; loaded = true
    }
    @MainActor private func load(keepError: Bool = false) async {
        switch await store.call("wellness-chat", .object(["action": .string("state")])) {
        case .success(let state): apply(state); if !available { error = "המאמן עדיין לא זמין." } else if !keepError { error = nil }
        case .failure(let e): loaded = true; error = message(for: e)
        }
    }
    @MainActor private func send() async {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        sending = true; error = nil; defer { sending = false }
        // Re-send with the same id after a failure so the server can dedupe the request.
        let id = (retryID != nil && retryText == message) ? retryID! : UUID().uuidString.lowercased()
        retryID = id; retryText = message
        let body: JSONValue = .object(["action": .string("send"), "requestId": .string(id), "message": .string(message), "includeDiary": .bool(includeDiary), "generation": .string(generation), "version": .number(Double(version))])
        switch await store.call("wellness-chat", body) {
        case .success:
            retryID = nil; text = ""
            await load()
        case .failure(let e):
            self.error = self.message(for: e)
            if e == .conflict { retryID = nil }
            let failure = self.error
            await load(keepError: true)
            if error == nil { error = failure }
        }
    }
    @MainActor private func clear() async {
        switch await store.call("wellness-chat", .object(["action": .string("clear")])) {
        case .success: turns = []; await load()
        case .failure(let e): error = message(for: e)
        }
    }
}
