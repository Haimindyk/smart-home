import SwiftUI

/// Shared look & feel: warm canvas, soft white cards, rounded numerals, springy touch feedback.
extension Color {
    /// Screen background (warm off-white).
    static let wellnessCanvas = Color(red: 0.961, green: 0.957, blue: 0.945)
    /// Inner chips and placeholders that sit on top of a white card.
    static let wellnessChip = Color(red: 0.945, green: 0.941, blue: 0.929)
    static let wellnessInk = Color(red: 0.07, green: 0.07, blue: 0.08)
    // Macro palette shared with the web app.
    static let kcalAmber = Color(red: 0.91, green: 0.62, blue: 0.18)
    static let proteinBlue = Color(red: 0.36, green: 0.55, blue: 0.94)
    static let carbsGold = Color(red: 0.91, green: 0.72, blue: 0.22)
    static let fatCoral = Color(red: 0.90, green: 0.45, blue: 0.45)
}

extension ShapeStyle where Self == LinearGradient {
    static var flame: LinearGradient { LinearGradient(colors: [Color(red: 1, green: 0.62, blue: 0.2), Color(red: 1, green: 0.32, blue: 0.4)], startPoint: .topLeading, endPoint: .bottomTrailing) }
}

extension View {
    func wellnessCard(padding: CGFloat = 20) -> some View {
        self.padding(padding)
            .background(.white, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.black.opacity(0.07)))
            .shadow(color: .black.opacity(0.04), radius: 14, y: 5)
    }

    /// Full-screen warm background that also fills the safe areas.
    func wellnessScreen() -> some View { background(Color.wellnessCanvas.ignoresSafeArea()) }

    func sectionTitle() -> some View { font(.title3.weight(.bold)).foregroundStyle(Color.wellnessInk) }
}

/// Scale-down + light haptic on press. Used for tappable cards and rows.
struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.94 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

struct PrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).frame(maxWidth: .infinity).frame(minHeight: 56)
            .foregroundStyle(.white)
            .background(Color.wellnessInk.opacity(enabled ? 1 : 0.3), in: Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.72), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .medium), trigger: configuration.isPressed) { _, pressed in pressed && enabled }
    }
}

struct ProgressRing: View {
    let value: Double; let target: Double?; let color: Color; let symbol: String
    var lineWidth: CGFloat = 5
    var gradient: LinearGradient?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var progress: Double { guard let target, target > 0, value.isFinite else { return 0 }; return min(1, max(0, value / target)) }
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.14), lineWidth: lineWidth)
            Circle().trim(from: 0, to: progress)
                .stroke(gradient.map { AnyShapeStyle($0) } ?? AnyShapeStyle(color), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.82), value: progress)
            Image(systemName: symbol).foregroundStyle(color).font(lineWidth > 8 ? .title : .callout)
        }.environment(\.layoutDirection, .leftToRight).accessibilityHidden(true)
    }
}

extension View {
    /// Horizontal swipe turns the day (Hebrew/RTL: swipe left = next day).
    func daySwipe(_ store: AppStore) -> some View {
        simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { drag in
            guard abs(drag.translation.width) > 70, abs(drag.translation.width) > abs(drag.translation.height) * 1.6 else { return }
            withAnimation(.snappy) { store.moveDay(drag.translation.width < 0 ? 1 : -1) }
        })
    }
}
