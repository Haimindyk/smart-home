import SwiftUI

struct WatchHome: View {
    @EnvironmentObject private var model: WatchModel
    var body: some View {
        NavigationStack {
            ScrollView {
                if let s = model.summary {
                    VStack(spacing: 14) {
                        calories(s)
                        water(s)
                        if let steps = s.steps { Label("\(Int(steps)) צעדים", systemImage: "figure.walk").font(.footnote).foregroundStyle(.secondary) }
                        Text("עודכן " + s.updatedAt.formatted(.relative(presentation: .named))).font(.caption2).foregroundStyle(.secondary)
                    }.padding(.horizontal, 4)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "iphone").font(.largeTitle).foregroundStyle(.secondary)
                        Text("פתח את האפליקציה באייפון כדי לסנכרן").multilineTextAlignment(.center).font(.footnote)
                    }.padding()
                }
            }.navigationTitle("היום")
        }
    }
    private func calories(_ s: WatchSummary) -> some View {
        let remaining = s.kcalRemaining
        return HStack(spacing: 12) {
            ZStack {
                Circle().stroke(Color.orange.opacity(0.2), lineWidth: 8)
                Circle().trim(from: 0, to: s.kcalProgress).stroke(Color.orange, style: StrokeStyle(lineWidth: 8, lineCap: .round)).rotationEffect(.degrees(-90))
                Image(systemName: "flame.fill").foregroundStyle(.orange)
            }.frame(width: 54, height: 54).environment(\.layoutDirection, .leftToRight)
            VStack(alignment: .leading, spacing: 2) {
                Text(Int(max(0, remaining ?? s.kcalConsumed)), format: .number).font(.title2.weight(.bold).monospacedDigit())
                Text(remaining == nil ? "קלוריות נאכלו" : (remaining! < 0 ? "מעל היעד" : "קלוריות נותרו")).font(.caption2).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityElement(children: .combine)
    }
    private func water(_ s: WatchSummary) -> some View {
        let total = s.waterML + Double(model.pendingWater)
        return VStack(spacing: 8) {
            HStack {
                Image(systemName: "drop.fill").foregroundStyle(.blue)
                Text("\(Int(total)) מתוך \(Int(s.waterTarget)) מ״ל").font(.footnote.monospacedDigit())
                Spacer()
            }
            ProgressView(value: min(1, total / max(1, s.waterTarget))).tint(.blue)
            Button { model.addWater(250) } label: { Label("250 מ״ל", systemImage: "plus") }.tint(.blue)
                .sensoryFeedback(.success, trigger: model.feedback)
        }
    }
}
