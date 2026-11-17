import XCTest
@testable import WellnessCore

final class FractionalIndexTests: XCTestCase {
    /// Vectors from the reference `fractional-indexing` library the web app uses.
    func testMatchesReferenceVectors() throws {
        let cases: [(String?, String?, String)] = [
            (nil, nil, "a0"), ("a0", nil, "a1"), ("a1", nil, "a2"), (nil, "a0", "Zz"),
            ("a0", "a1", "a0V"), ("a1", "a2", "a1V"), ("a0V", "a1", "a0l"), ("Zz", "a0", "ZzV"),
            ("Zz", "a1", "a0"), (nil, "Y00", "Xzzz"), ("bzz", nil, "c000"), ("a0", "a0V", "a0G"),
            ("a0", "a0G", "a08"), ("b125", "b129", "b127"), ("a0", "a1V", "a1"), ("Zz", "a01", "a0"), (nil, "a0V", "a0"),
        ]
        for (a, b, expected) in cases { XCTAssertEqual(try FractionalIndex.between(a, b), expected, "between(\(a ?? "nil"), \(b ?? "nil"))") }
    }
    func testRejectsInvalidAndUnorderedKeys() {
        XCTAssertThrowsError(try FractionalIndex.between("a1", "a0"))
        XCTAssertThrowsError(try FractionalIndex.between("a1", "a1"))
        XCTAssertThrowsError(try FractionalIndex.between("a10", nil), "trailing zero is not a valid fractional part")
    }
    func testAppendingManyKeepsStrictOrder() throws {
        var keys: [String] = []; var last: String?
        for _ in 0..<200 { let next = try FractionalIndex.atEnd(last); keys.append(next); last = next }
        XCTAssertEqual(keys, keys.sorted()); XCTAssertEqual(Set(keys).count, keys.count)
    }
    func testInsertingBetweenNeighboursStaysBetween() throws {
        var a = "a0", b = "a1"
        for _ in 0..<40 { let mid = try FractionalIndex.between(a, b); XCTAssertTrue(a < mid && mid < b); b = mid }
        _ = a; a = "a0"
    }
}
