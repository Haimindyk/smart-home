import Foundation

/// Small natural-language date extraction for quick-add, matching the web app: "היום", "מחר", today/tomorrow,
/// dd/mm[/yy] dates. The matched phrase is removed from the title.
public enum QuickAdd {
    public struct Result: Equatable, Sendable { public let title: String; public let due: Date? }

    public static func parse(_ input: String, now: Date = Date(), calendar: Calendar = .current) -> Result {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        func strip(_ range: Range<String.Index>) -> String {
            var t = text; t.removeSubrange(range)
            let collapsed = t.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
            return collapsed.isEmpty ? text : collapsed
        }
        func word(_ pattern: String) -> Range<String.Index>? { text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) }
        // Whole-word matches (Hebrew has no \b in ICU for these, so use explicit boundaries).
        let boundary = "(?<![\\p{L}\\p{N}])", end = "(?![\\p{L}\\p{N}])"
        let startOfToday = calendar.startOfDay(for: now)
        if let r = word(boundary + "(מחר|tomorrow)" + end), let d = calendar.date(byAdding: .day, value: 1, to: startOfToday) { return Result(title: strip(r), due: d) }
        if let r = word(boundary + "(היום|today)" + end) { return Result(title: strip(r), due: startOfToday) }
        if let r = text.range(of: boundary + "(\\d{1,2})[/.\\-](\\d{1,2})(?:[/.\\-](\\d{2,4}))?" + end, options: .regularExpression) {
            let parts = text[r].split(whereSeparator: { "/.-".contains($0) }).compactMap { Int($0) }
            if parts.count >= 2 {
                var comps = DateComponents(); comps.day = parts[0]; comps.month = parts[1]
                var year = parts.count > 2 ? parts[2] : calendar.component(.year, from: now)
                if year < 100 { year += 2000 }; comps.year = year
                if (1...31).contains(parts[0]), (1...12).contains(parts[1]), let d = calendar.date(from: comps), calendar.component(.day, from: d) == parts[0] { return Result(title: strip(r), due: d) }
            }
        }
        return Result(title: text, due: nil)
    }
}
