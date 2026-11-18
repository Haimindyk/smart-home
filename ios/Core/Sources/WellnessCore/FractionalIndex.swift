import Foundation

/// Port of the `fractional-indexing` algorithm (base 62) the web app uses for `position` columns,
/// so items ordered on iOS sort identically on the web and vice versa.
public enum FractionalIndex {
    public enum Failure: Error, Equatable { case invalidKey, notOrdered, exhausted }
    private static let digits = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
    private static let zero: Character = "0"
    private static let smallestInteger = "A" + String(repeating: "0", count: 26)

    public static func between(_ a: String?, _ b: String?) throws -> String {
        if let a { try validateOrderKey(a) }
        if let b { try validateOrderKey(b) }
        if let a, let b, a >= b { throw Failure.notOrdered }
        switch (a, b) {
        case (nil, nil): return "a" + String(zero)
        case (nil, let b?):
            let ib = try integerPart(b), fb = String(b.dropFirst(ib.count))
            if ib == smallestInteger { return ib + (try midpoint("", fb)) }
            if ib < b { return ib }
            guard let res = try decrement(ib) else { throw Failure.exhausted }
            return res
        case (let a?, nil):
            let ia = try integerPart(a), fa = String(a.dropFirst(ia.count))
            if let i = try increment(ia) { return i }
            return ia + (try midpoint(fa, nil))
        case (let a?, let b?):
            let ia = try integerPart(a), fa = String(a.dropFirst(ia.count))
            let ib = try integerPart(b), fb = String(b.dropFirst(ib.count))
            if ia == ib { return ia + (try midpoint(fa, fb)) }
            guard let i = try increment(ia) else { throw Failure.exhausted }
            if i < b { return i }
            return ia + (try midpoint(fa, nil))
        }
    }
    /// Rank for an item appended to the end of a list.
    public static func atEnd(_ last: String?) throws -> String { try between(last, nil) }

    private static func midpoint(_ a: String, _ b: String?) throws -> String {
        if let b, a >= b { throw Failure.notOrdered }
        if a.last == zero || b?.last == zero { throw Failure.invalidKey }
        let aChars = Array(a)
        if let b {
            let bChars = Array(b)
            var n = 0
            while (n < aChars.count ? aChars[n] : zero) == (n < bChars.count ? bChars[n] : nil) { n += 1 }
            if n > 0 { return String(bChars[0..<n]) + (try midpoint(String(aChars.dropFirst(n)), String(bChars.dropFirst(n)))) }
        }
        let digitA = aChars.first.flatMap { digits.firstIndex(of: $0) } ?? 0
        let digitB = b?.first.flatMap { digits.firstIndex(of: $0) } ?? digits.count
        if digitB - digitA > 1 {
            return String(digits[Int((0.5 * Double(digitA + digitB)).rounded(.toNearestOrAwayFromZero))])
        }
        if let b, b.count > 1 { return String(b.first!) }
        return String(digits[digitA]) + (try midpoint(String(aChars.dropFirst()), nil))
    }
    private static func integerLength(_ head: Character) throws -> Int {
        guard let v = head.asciiValue else { throw Failure.invalidKey }
        if head >= "a" && head <= "z" { return Int(v) - 97 + 2 }
        if head >= "A" && head <= "Z" { return 90 - Int(v) + 2 }
        throw Failure.invalidKey
    }
    private static func integerPart(_ key: String) throws -> String {
        guard let head = key.first else { throw Failure.invalidKey }
        let length = try integerLength(head)
        guard length <= key.count else { throw Failure.invalidKey }
        return String(key.prefix(length))
    }
    private static func validateOrderKey(_ key: String) throws {
        if key == smallestInteger { throw Failure.invalidKey }
        let i = try integerPart(key)
        if key.dropFirst(i.count).last == zero { throw Failure.invalidKey }
    }
    private static func increment(_ x: String) throws -> String? {
        guard x.count == (try integerLength(x.first ?? "~")) else { throw Failure.invalidKey }
        var chars = Array(x); let head = chars.removeFirst(); var carry = true
        var i = chars.count - 1
        while carry && i >= 0 {
            let d = (digits.firstIndex(of: chars[i]) ?? 0) + 1
            if d == digits.count { chars[i] = digits[0] } else { chars[i] = digits[d]; carry = false }
            i -= 1
        }
        if carry {
            if head == "Z" { return "a" + String(digits[0]) }
            if head == "z" { return nil }
            let h = Character(UnicodeScalar(head.asciiValue! + 1))
            if h > "a" { chars.append(digits[0]) } else { chars.removeLast() }
            return String(h) + String(chars)
        }
        return String(head) + String(chars)
    }
    private static func decrement(_ x: String) throws -> String? {
        guard x.count == (try integerLength(x.first ?? "~")) else { throw Failure.invalidKey }
        var chars = Array(x); let head = chars.removeFirst(); var borrow = true
        var i = chars.count - 1
        while borrow && i >= 0 {
            let d = (digits.firstIndex(of: chars[i]) ?? 0) - 1
            if d == -1 { chars[i] = digits.last! } else { chars[i] = digits[d]; borrow = false }
            i -= 1
        }
        if borrow {
            if head == "a" { return "Z" + String(digits.last!) }
            if head == "A" { return nil }
            let h = Character(UnicodeScalar(head.asciiValue! - 1))
            if h < "Z" { chars.append(digits.last!) } else { chars.removeLast() }
            return String(h) + String(chars)
        }
        return String(head) + String(chars)
    }
}

/// Drag-and-drop ordering: the new position for the dragged item so it lands where the target is.
public enum Reorder {
    /// `siblings` are `(id, position)` pairs sorted by position. Dropping downward puts the item after the target, upward before it.
    public static func position(_ siblings: [(id: String, position: String)], moving: String, onto target: String) -> String? {
        guard moving != target, let from = siblings.firstIndex(where: { $0.id == moving }), let to = siblings.firstIndex(where: { $0.id == target }) else { return nil }
        var rest = siblings; rest.remove(at: from)
        return try? FractionalIndex.between(to > 0 ? rest[to - 1].position : nil, to < rest.count ? rest[to].position : nil)
    }
}
