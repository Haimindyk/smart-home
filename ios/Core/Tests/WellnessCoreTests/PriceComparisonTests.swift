import XCTest
@testable import WellnessCore

private struct FakeSource: PriceComparison.Source {
    var exact: [String: PriceComparison.Product] = [:]
    var results: [String: [PriceComparison.Product]] = [:]
    func product(barcode: String) async throws -> PriceComparison.Product? { exact[barcode] }
    func search(_ query: String) async throws -> [PriceComparison.Product] { results[query] ?? [] }
}

final class PriceComparisonTests: XCTestCase {
    typealias P = PriceComparison.Product
    func testFillerWordsAndSynonyms() {
        XCTAssertEqual(PriceComparison.stripFiller("צריך לקנות חלב"), "חלב")
        XCTAssertEqual(PriceComparison.stripFiller("לקנות"), "לקנות", "a title that is only filler is kept")
        XCTAssertEqual(Set(PriceComparison.expandSynonyms("סבון גוף דאב")), ["סבון גוף דאב", "תחליב רחצה דאב", "תחליב גוף דאב"])
    }
    func testFullyPricedChainsRankByTotalAndPartialChainsNeverWin() async throws {
        let milk = P(barcode: "1", name: "חלב", prices: ["shufersal": 6, "rami_levy": 5, "carrefour": 7])
        let eggs = P(barcode: "2", name: "ביצים", prices: ["shufersal": 12, "rami_levy": 10])
        let src = FakeSource(results: ["חלב": [milk], "ביצים": [eggs]])
        let r = try await PriceComparison.compare([.init(id: "a", title: "חלב"), .init(id: "b", title: "ביצים")], excluding: ["super_pharm", "osher_ad"], source: src)
        XCTAssertEqual(r.ranked.map(\.chain.key), ["rami_levy", "shufersal", "carrefour"], "carrefour only prices milk, so it is listed after fully priced chains")
        XCTAssertEqual(r.cheapest?.chain.key, "rami_levy"); XCTAssertEqual(r.cheapest?.total, 15)
        XCTAssertEqual(r.mostExpensive?.chain.key, "shufersal"); XCTAssertEqual(r.savings, 3); XCTAssertEqual(r.savingsPercent, 16.7)
        XCTAssertEqual(r.ranked.last?.matched, 1)
    }
    func testScannedBarcodeIsAnExactMatchAndUnknownItemsAreNotFound() async throws {
        let cola = P(barcode: "7290012345678", name: "קולה", prices: ["shufersal": 8])
        let src = FakeSource(exact: ["7290012345678": cola])
        let r = try await PriceComparison.compare([.init(id: "a", title: "משהו", notes: "ברקוד: 7290012345678"), .init(id: "b", title: "לא קיים")], excluding: ["rami_levy", "carrefour", "super_pharm", "osher_ad"], source: src)
        XCTAssertEqual(r.ranked.count, 1); XCTAssertEqual(r.ranked[0].items[0].status, .exact); XCTAssertEqual(r.ranked[0].items[1].status, .notFound)
        XCTAssertNil(r.cheapest, "a chain missing an item cannot be the cheapest")
    }
    func testSharedCandidateKeepsChainsComparingTheSameProduct() async throws {
        let a = P(barcode: "1", name: "A", prices: ["shufersal": 10]), b = P(barcode: "2", name: "B", prices: ["shufersal": 9, "rami_levy": 8])
        let r = try await PriceComparison.compare([.init(id: "x", title: "מוצר")], excluding: ["carrefour", "super_pharm", "osher_ad"], source: FakeSource(results: ["מוצר": [a, b]]))
        XCTAssertEqual(r.ranked.flatMap(\.items).compactMap(\.productName), ["B", "B"])
    }
    func testChainExclusionForGroceryList() { XCTAssertEqual(PriceComparison.excludedChains(forSection: " קניות בסופר "), ["super_pharm"]); XCTAssertTrue(PriceComparison.excludedChains(forSection: "סופר פארם").isEmpty) }
}
