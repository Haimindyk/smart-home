import SwiftUI

/// User-entered content (task titles, notes) should read in its own
/// direction regardless of the app chrome's locale — same reasoning as the
/// website's `bidi-text.tsx` — so mixed Hebrew/English/number text never
/// scrambles.
struct BidiText: View {
    private let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .environment(\.layoutDirection, Self.isRTL(text) ? .rightToLeft : .leftToRight)
            .multilineTextAlignment(Self.isRTL(text) ? .trailing : .leading)
    }

    private static func isRTL(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF: // Hebrew/Arabic blocks
                return true
            case 0x0041...0x005A, 0x0061...0x007A: // Latin letters
                return false
            default:
                continue
            }
        }
        return false
    }
}
