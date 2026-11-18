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
}
