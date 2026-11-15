import Foundation

/// Minimal he/en switch, mirroring the website's locale store: Hebrew (RTL)
/// is the default, with a full English (LTR) translation of the app chrome.
enum AppLocale: String, CaseIterable, Identifiable {
    case he
    case en

    var id: String { rawValue }
    var isRTL: Bool { self == .he }

    static var systemDefault: AppLocale {
        let preferred = Locale.preferredLanguages.first ?? "he"
        return preferred.hasPrefix("en") ? .en : .he
    }
}
