import Foundation

/// Base62 fractional indexing for drag-and-drop reordering — same idea as
/// the website's `lib/ordering/rank.ts` (so two people reordering at the
/// same time can't collide the way integer positions would), reimplemented
/// natively here since this is a separate backend with its own `position`
/// columns.
enum FractionalIndex {
    private static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
    private static let base = alphabet.count

    private static func digit(at index: Int, of s: String) -> Int {
        guard index < s.count else { return 0 }
        let char = s[s.index(s.startIndex, offsetBy: index)]
        return alphabet.firstIndex(of: char) ?? 0
    }

    /// A key that sorts strictly between `lower` and `upper`. Pass `nil` for
    /// either bound to mean "no bound" (start/end of the list).
    static func keyBetween(_ lower: String?, _ upper: String?) -> String {
        let a = lower ?? ""
        var result = ""
        var i = 0
        while i < 128 {
            let digitA = digit(at: i, of: a)
            let hasUpperDigit = upper.map { i < $0.count } ?? false
            let digitB = hasUpperDigit ? digit(at: i, of: upper!) : nil

            if let digitB {
                if digitA == digitB {
                    result.append(alphabet[digitA])
                    i += 1
                    continue
                }
                let gap = digitB - digitA
                if gap > 1 {
                    result.append(alphabet[digitA + gap / 2])
                    return result
                }
                result.append(alphabet[digitA])
                i += 1
                continue
            } else if digitA < base - 1 {
                result.append(alphabet[digitA + (base - digitA) / 2])
                return result
            } else {
                result.append(alphabet[digitA])
                i += 1
                continue
            }
        }
        return result + "V"
    }

    static func rankAtEnd(after lastPosition: String?) -> String {
        keyBetween(lastPosition, nil)
    }

    static func rankBetween(_ before: String?, _ after: String?) -> String {
        keyBetween(before, after)
    }

    static func ranksForCount(_ count: Int) -> [String] {
        guard count > 0 else { return [] }
        var keys: [String] = []
        var previous: String?
        for _ in 0..<count {
            let key = keyBetween(previous, nil)
            keys.append(key)
            previous = key
        }
        return keys
    }
}
