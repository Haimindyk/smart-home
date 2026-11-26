import XCTest
@testable import WellnessCore

final class ReorderTests: XCTestCase {
    private func list() -> [(id: String, position: String)] {
        var out: [(String, String)] = [], last: String?
        for id in ["a", "b", "c", "d"] { let p = try! FractionalIndex.atEnd(last); out.append((id, p)); last = p }
        return out
    }
    private func order(_ items: [(id: String, position: String)], moving: String, to position: String) -> [String] {
        var m = items; m[m.firstIndex { $0.id == moving }!].position = position
        return m.sorted { $0.position < $1.position }.map(\.id)
    }
    func testDroppingDownwardLandsAfterTheTarget() {
        let l = list(); let p = Reorder.position(l, moving: "a", onto: "c")!
        XCTAssertEqual(order(l, moving: "a", to: p), ["b", "c", "a", "d"])
        XCTAssertEqual(order(l, moving: "a", to: Reorder.position(l, moving: "a", onto: "d")!), ["b", "c", "d", "a"])
    }
    func testDroppingUpwardLandsBeforeTheTarget() {
        let l = list()
        XCTAssertEqual(order(l, moving: "d", to: Reorder.position(l, moving: "d", onto: "b")!), ["a", "d", "b", "c"])
        XCTAssertEqual(order(l, moving: "c", to: Reorder.position(l, moving: "c", onto: "a")!), ["c", "a", "b", "d"])
    }
    func testSelfDropAndUnknownIdsDoNothing() {
        XCTAssertNil(Reorder.position(list(), moving: "a", onto: "a")); XCTAssertNil(Reorder.position(list(), moving: "x", onto: "a"))
    }
    func testDroppingIntoAnotherListPlacesBeforeTheTargetOrAtTheEnd() throws {
        let list = [("a", "a1"), ("b", "a2"), ("c", "a3")].map { (id: $0.0, position: $0.1) }
        let beforeB = try XCTUnwrap(Reorder.positionInOtherList(list, before: "b"))
        XCTAssertTrue(beforeB > "a1" && beforeB < "a2", "between a and b: \(beforeB)")
        let beforeFirst = try XCTUnwrap(Reorder.positionInOtherList(list, before: "a"))
        XCTAssertTrue(beforeFirst < "a1")
        let atEnd = try XCTUnwrap(Reorder.positionInOtherList(list, before: nil))
        XCTAssertTrue(atEnd > "a3")
        let unknown = try XCTUnwrap(Reorder.positionInOtherList(list, before: "missing"))
        XCTAssertTrue(unknown > "a3", "an unknown target falls back to the end")
        XCTAssertNotNil(Reorder.positionInOtherList([], before: nil), "an empty list still gets a position")
    }
}
