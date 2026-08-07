import SwiftUI

/// Design tokens ported from the website's `src/app/globals.css` (the
/// shadcn/Tailwind `oklch(...)` custom properties) so the two apps read as
/// the same product. Where the website derives a color from `oklch()`,
/// the SwiftUI value below is a manually-converted sRGB approximation —
/// this was written without a way to render/screenshot SwiftUI to check
/// pixel-for-pixel fidelity, so treat these as "same family, worth a
/// visual pass in Xcode" rather than exact.
enum Theme {
    /// The website's `--primary` (a warm terracotta/amber, `oklch(0.64 0.15 45)`
    /// light / `oklch(0.72 0.14 45)` dark) — also set as the app's
    /// AccentColor asset, so every default-tinted control (buttons, links,
    /// toggles, the selected tab) picks this up automatically.
    static let accent = Color(
        light: Color(red: 0xD4 / 255, green: 0x69 / 255, blue: 0x34 / 255),
        dark: Color(red: 0xEB / 255, green: 0x85 / 255, blue: 0x56 / 255)
    )

    static let background = Color(
        light: .white,
        dark: Color(red: 0x21 / 255, green: 0x1D / 255, blue: 0x1A / 255)
    )

    static let card = Color(
        light: .white,
        dark: Color(red: 0x2B / 255, green: 0x27 / 255, blue: 0x23 / 255)
    )

    static let border = Color(
        light: Color(red: 0xE8 / 255, green: 0xE5 / 255, blue: 0xE1 / 255),
        dark: Color.white.opacity(0.1)
    )

    static let muted = Color(
        light: Color(red: 0xF7 / 255, green: 0xF6 / 255, blue: 0xF4 / 255),
        dark: Color(red: 0x35 / 255, green: 0x30 / 255, blue: 0x2B / 255)
    )

    static let mutedForeground = Color(
        light: Color(red: 0x87 / 255, green: 0x80 / 255, blue: 0x7A / 255),
        dark: Color(red: 0xB8 / 255, green: 0xAE / 255, blue: 0xA4 / 255)
    )

    /// Corner radii — the website's `--radius: 0.9rem` (≈14.4pt at its
    /// 112.5%-scaled root) scaled the same way Tailwind derives
    /// `--radius-{sm,md,lg,xl,2xl,3xl}` from it.
    enum Radius {
        static let sm: CGFloat = 9
        static let md: CGFloat = 12
        static let lg: CGFloat = 14
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 26
        /// Dashboard cards (`rounded-3xl`) — the roundest shape in the UI.
        static let card: CGFloat = 32
    }

    /// The website's fixed, hue-per-kind palette for section cards
    /// (`KIND_COLOR` in `section-panel.tsx`) — deliberately independent of
    /// the accent color, so sections stay visually distinguishable from
    /// "the app's own color."
    enum SectionKindColor {
        static let tasks = Color(red: 0x63 / 255, green: 0x66 / 255, blue: 0xF1 / 255)     // indigo-500
        static let shopping = Color(red: 0x10 / 255, green: 0xB9 / 255, blue: 0x81 / 255)  // emerald-500
        static let chores = Color(red: 0xF4 / 255, green: 0x3F / 255, blue: 0x5E / 255)    // rose-500
        static let info = Color(red: 0x0E / 255, green: 0xA5 / 255, blue: 0xE9 / 255)      // sky-500

        static func forKind(_ kind: SectionKind) -> Color {
            switch kind {
            case .tasks: return tasks
            case .shopping: return shopping
            case .chores: return chores
            case .info: return info
            }
        }
    }

    /// The soft, multi-layer "surface-shadow" utility class, approximated
    /// as a single SwiftUI shadow (SwiftUI doesn't support stacking
    /// multiple `.shadow()` values on one layer as cheaply as CSS does).
    static func surfaceShadow<S: Shape>(_ shape: S) -> some View {
        shape
            .fill(Color.clear)
            .shadow(color: .black.opacity(0.10), radius: 16, x: 0, y: 10)
            .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 1)
    }
}

extension Color {
    /// A dynamic color that resolves per-appearance, the SwiftUI
    /// equivalent of the website's `:root` / `.dark` CSS variable pairs.
    init(light: Color, dark: Color) {
        #if canImport(UIKit)
        self.init(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #else
        self = light
        #endif
    }
}
