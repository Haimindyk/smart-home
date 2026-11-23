import SwiftUI
import Network

/// Shared look & feel: warm canvas, soft white cards, rounded numerals, springy touch feedback.
private func adaptive(_ light: (Double, Double, Double), _ dark: (Double, Double, Double), lightAlpha: Double = 1, darkAlpha: Double = 1) -> Color {
    Color(UIColor { traits in
        let c = traits.userInterfaceStyle == .dark ? dark : light
        return UIColor(red: c.0, green: c.1, blue: c.2, alpha: traits.userInterfaceStyle == .dark ? darkAlpha : lightAlpha)
    })
}

extension Color {
    /// Screen background: warm off-white in light mode, near-black in dark mode.
    static let wellnessCanvas = adaptive((0.980, 0.980, 0.980), (0.039, 0.039, 0.043))
    /// Card surface.
    static let wellnessCard = adaptive((1, 1, 1), (0.105, 0.105, 0.115))
    /// Inner chips and placeholders that sit on top of a card.
    static let wellnessChip = adaptive((0.945, 0.949, 0.957), (0.18, 0.18, 0.195))
    /// Primary ink (text and filled buttons) and the color that sits on top of it.
    static let wellnessInk = adaptive((0.07, 0.07, 0.08), (0.96, 0.96, 0.97))
    static let wellnessOnInk = adaptive((1, 1, 1), (0.07, 0.07, 0.08))
    /// Secondary text with at least 4.5:1 contrast on cards and canvas in both appearances.
    static let wellnessSecondary = adaptive((0.40, 0.41, 0.45), (0.70, 0.70, 0.74))
    static let wellnessHairline = adaptive((0.914, 0.918, 0.929), (1, 1, 1), lightAlpha: 1, darkAlpha: 0.10)
    /// Filled primary controls: near-black in light mode, warm amber in dark mode (as on the web).
    static let wellnessPrimary = adaptive((0.09, 0.09, 0.09), (0.96, 0.73, 0.22))
    static let wellnessOnPrimary = adaptive((1, 1, 1), (0.09, 0.09, 0.09))
    // Section kind colors (web: indigo, emerald, rose, sky).
    static let kindTasks = Color(red: 0.388, green: 0.400, blue: 0.945)
    static let kindShopping = Color(red: 0.063, green: 0.725, blue: 0.506)
    static let kindChores = Color(red: 0.957, green: 0.247, blue: 0.369)
    static let kindInfo = Color(red: 0.055, green: 0.647, blue: 0.914)
    static let amberTint = adaptive((1, 0.957, 0.843), (0.30, 0.22, 0.08))
    static let amberInk = adaptive((0.47, 0.333, 0), (0.96, 0.73, 0.22))
    // Macro palette shared with the web app.
    // Text-safe variants (>= 4.5:1 on cards); the base colors stay for rings, bars and icons.
    static let kcalAmberText = adaptive((0.64, 0.36, 0.0), (0.96, 0.72, 0.30))
    static let proteinBlueText = adaptive((0.13, 0.35, 0.76), (0.55, 0.72, 1.0))
    static let fatCoralText = adaptive((0.72, 0.20, 0.20), (1.0, 0.60, 0.60))
    static let kcalAmber = Color(red: 0.91, green: 0.62, blue: 0.18)
    static let proteinBlue = Color(red: 0.36, green: 0.55, blue: 0.94)
    static let carbsGold = Color(red: 0.91, green: 0.72, blue: 0.22)
    static let fatCoral = Color(red: 0.90, green: 0.45, blue: 0.45)
}

extension ShapeStyle where Self == LinearGradient {
    static var flame: LinearGradient { LinearGradient(colors: [Color(red: 1, green: 0.62, blue: 0.2), Color(red: 1, green: 0.32, blue: 0.4)], startPoint: .topLeading, endPoint: .bottomTrailing) }
}

extension View {
    func wellnessCard(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background(Color.wellnessCard, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.wellnessHairline))
            .shadow(color: .black.opacity(0.05), radius: 1, y: 1)
            .shadow(color: .black.opacity(0.10), radius: 12, y: 6)
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
        configuration.label.font(.hb(.headline, .semibold)).frame(maxWidth: .infinity).frame(minHeight: 56)
            .foregroundStyle(Color.wellnessOnPrimary)
            .background(Color.wellnessPrimary.opacity(enabled ? 1 : 0.3), in: Capsule())
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

/// Shimmering placeholder used while the first load is in flight.
struct Shimmer: ViewModifier {
    let active: Bool
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .redacted(reason: active ? .placeholder : [])
            .overlay {
                if active && !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, Color.white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.6).offset(x: phase * geo.size.width * 1.6)
                            .onAppear { withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 } }
                    }.allowsHitTesting(false).blendMode(.plusLighter).clipped()
                }
            }
            .allowsHitTesting(!active)
    }
}
extension View {
    func shimmer(_ active: Bool) -> some View { modifier(Shimmer(active: active)) }
    /// Grouped list that follows the app canvas and card colors (light and dark).
    func wellnessList() -> some View { scrollContentBackground(.hidden).scrollDismissesKeyboard(.interactively).keyboardDoneButton().background(Color.wellnessCanvas.ignoresSafeArea()).font(.hb(.body)).tint(Color.wellnessPrimary).listSectionSpacing(10).environment(\.defaultMinListRowHeight, 40) }
}

/// Non-blocking error banner that slides in from the top and dismisses itself.
struct ErrorBanner: ViewModifier {
    @Binding var message: String?
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let message {
                Button { self.message = nil } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.white)
                        Text(message).font(.hb(.subheadline, .semibold)).foregroundStyle(.white).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(Color.red.opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                }
                .buttonStyle(.plain).padding(.horizontal, 16).padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .sensoryFeedback(.error, trigger: message)
                .accessibilityIdentifier("error-banner")
                .task(id: message) { try? await Task.sleep(for: .seconds(4)); withAnimation { self.message = nil } }
            }
        }.animation(.spring(duration: 0.35), value: message)
    }
}
extension View { func errorBanner(_ message: Binding<String?>) -> some View { modifier(ErrorBanner(message: message)) } }

extension View {
    /// "Done" above the keyboard, so number pads (which have no return key) can be dismissed.
    func keyboardDoneButton() -> some View {
        toolbar { ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("סיום") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }.accessibilityIdentifier("keyboard-done")
        } }
    }
}

/// Tracks connectivity so the app can say when it is offline (the web app shows the same banner).
@MainActor final class NetworkMonitor: ObservableObject {
    @Published private(set) var online = true
    private let monitor = NWPathMonitor()
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let ok = path.status == .satisfied
            Task { @MainActor in self?.online = ok }
        }
        monitor.start(queue: DispatchQueue(label: "kh.network-monitor"))
    }
    deinit { monitor.cancel() }
}
struct OfflineBanner: View {
    var body: some View {
        Label("אין חיבור לאינטרנט. שינויים לא יישמרו עד שהחיבור יחזור.", systemImage: "wifi.slash")
            .font(.hb(.footnote, .semibold)).foregroundStyle(Color.amberInk)
            .frame(maxWidth: .infinity).padding(.vertical, 7).padding(.horizontal, 12)
            .background(Color.amberTint)
            .accessibilityIdentifier("offline-banner")
    }
}

/// Swipe a card to the right to reveal a red delete action. Past the threshold the card springs back and `onConfirm` runs,
/// so the caller can ask "delete?" and a cancel leaves the card exactly where it was.
struct SwipeToConfirmDelete: ViewModifier {
    var slideOut = false
    let onConfirm: () -> Void
    @State private var offset: CGFloat = 0
    @State private var armed = false
    private let threshold: CGFloat = 96
    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .background {
                if offset > 4 {
                    RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Color.red.opacity(armed ? 0.95 : 0.72))
                        .overlay(alignment: .leading) {
                            Image(systemName: "trash.fill").font(.title3.weight(.semibold)).foregroundStyle(.white).scaleEffect(armed ? 1.15 : 1).padding(.leading, 28)
                        }
                        .environment(\.layoutDirection, .leftToRight)
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 18)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) * 1.3 else { return }
                        offset = max(0, min(170, value.translation.width))
                        let now = offset >= threshold
                        if now != armed { armed = now }
                    }
                    .onEnded { _ in
                        let fire = armed
                        if fire && slideOut {
                            // Slide the card away, then remove it; if it is still here a moment later (the delete was refused) bring it back.
                            withAnimation(.easeIn(duration: 0.2)) { offset = 520 }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { onConfirm() }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { offset = 0; armed = false } }
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { offset = 0; armed = false }
                            if fire { onConfirm() }
                        }
                    }
            )
            .sensoryFeedback(.impact(weight: .medium), trigger: armed) { _, now in now }
            .accessibilityAction(named: "מחיקה", onConfirm)
    }
}
extension View { func swipeToConfirmDelete(slideOut: Bool = false, _ onConfirm: @escaping () -> Void) -> some View { modifier(SwipeToConfirmDelete(slideOut: slideOut, onConfirm: onConfirm)) } }
