import Foundation

/// Builds/parses the `yachad://join?code=...` links used for sharing an
/// area invite and encoding it into a QR code. A custom URL scheme (rather
/// than a universal link) is deliberate — it needs no domain or hosted
/// apple-app-site-association file, and the invite code alone (paste it
/// into "Join with a code") already works without any link at all.
enum InviteLink {
    static let scheme = "yachad"

    static func url(forInviteCode code: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "join"
        components.queryItems = [URLQueryItem(name: "code", value: code)]
        return components.url!
    }

    static func inviteCode(from url: URL) -> String? {
        guard url.scheme == scheme, url.host == "join" else { return nil }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "code" })?
            .value
    }

    /// Accepts either a bare invite code or a full yachad:// link pasted by
    /// the user, so "join with a code" and "paste a link" are the same box.
    static func normalizedCode(fromPastedText text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), let code = inviteCode(from: url) {
            return code
        }
        return trimmed
    }

    static func shareText(areaName: String, code: String, locale: AppLocale) -> String {
        let url = url(forInviteCode: code).absoluteString
        switch locale {
        case .he:
            return "הצטרפו אליי ב\"\(areaName)\" ביחד 👋\n\(url)\nאו הזינו את הקוד: \(code)"
        case .en:
            return "Join me in \"\(areaName)\" on Yachad 👋\n\(url)\nOr enter the code: \(code)"
        }
    }
}
