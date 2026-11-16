import XCTest
@testable import WellnessCore

final class ImportTests: XCTestCase {
    let owner = "11111111-1111-4111-8111-111111111111"
    func workout(energy: Double? = nil) -> AppleWorkout {
        AppleWorkout(id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!, name: "הליכה", activityType: 52, sourceName: "Apple Watch", start: Date(timeIntervalSince1970: 1_730_505_000), end: Date(timeIntervalSince1970: 1_730_506_800), duration: 1800, energyKcal: energy, distanceMeters: 2500)
    }
    func testPayloadPreservesUnknownEnergyAndDoesNotInventSets() throws {
        let data = try workout().payload(timeZone: "Asia/Jerusalem")
        XCTAssertEqual(data["appleHealth"]["energyKcal"], .null)
        XCTAssertEqual(data["appleHealth"]["distanceMeters"], .number(2500))
        XCTAssertEqual(data["exercises"], .array([]))
        XCTAssertEqual(data["status"], .string("completed"))
        XCTAssertEqual(data["appleHealth"]["durationSeconds"], .number(1800))
    }
    func testRepeatedQueriesAndImportedUUIDsDoNotCreateMoreCandidates() {
        let w = workout()
        XCTAssertEqual(pendingAppleWorkouts([w,w], existing: []).count, 1)
        XCTAssertTrue(pendingAppleWorkouts([w], existing: [w.id.uuidString]).isEmpty)
    }
    func testSourceKeysAreOwnerScoped() throws {
        XCTAssertNotEqual(try workout().sourceKey(owner: owner), try workout().sourceKey(owner: "33333333-3333-4333-8333-333333333333"))
        XCTAssertThrowsError(try workout().sourceKey(owner: "untrusted"))
    }
    func testRejectsNonFiniteDataAndUnknownTimeZone() {
        XCTAssertThrowsError(try workout(energy: .infinity).payload(timeZone: "UTC"))
        XCTAssertThrowsError(try workout().payload(timeZone: "Unknown/Zone"))
    }
    func testWireJSONRetainsProductPhotosAndNullNutrients() throws {
        let json = #"{"imagePath":"owner/photo.jpg","per100":{"fiber":null},"extra":{"known":true}}"#.data(using: .utf8)!
        let value = try JSONDecoder().decode(JSONValue.self, from: json)
        XCTAssertEqual(value["imagePath"].stringValue, "owner/photo.jpg")
        XCTAssertEqual(try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value)), value)
    }
    func testNutrientTotalsRespectEachFoodBasisAndIgnoreMissingValues() throws {
        let json = #"{"id":"meal","owner_user_id":"owner","version":1,"data":{"items":[{"quantity":50,"food":{"basis":"g","per100":{"kcal":200}}},{"quantity":250,"food":{"basis":"ml","per100":{"kcal":40}}},{"quantity":30,"food":{"per100":{"fiber":null}}}]}}"#
        let meal = try JSONDecoder().decode(HealthRow.self, from: Data(json.utf8))
        XCTAssertEqual(nutrientTotal(meals: [meal], nutrient: "kcal"), 200)
        XCTAssertEqual(nutrientTotal(meals: [], nutrient: "kcal"), 0)
    }
}
