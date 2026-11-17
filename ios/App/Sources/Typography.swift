import SwiftUI

/// Heebo (SIL OFL), the typeface the web app uses. Sizes scale with Dynamic Type like the system text styles.
extension Font {
    private static func face(_ weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light, .regular: return "Heebo-Regular"
        case .medium: return "Heebo-Medium"
        case .semibold: return "Heebo-SemiBold"
        case .bold: return "Heebo-Bold"
        default: return "Heebo-ExtraBold"
        }
    }
    private static func base(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline: return 17
        case .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        @unknown default: return 17
        }
    }
    /// A text style rendered in Heebo; scales with Dynamic Type.
    static func hb(_ style: Font.TextStyle, _ weight: Font.Weight = .regular) -> Font {
        .custom(face(weight), size: base(style), relativeTo: style)
    }
    /// A fixed point size (use with values already scaled by `@ScaledMetric`).
    static func hbFixed(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .custom(face(weight), fixedSize: size) }
}
