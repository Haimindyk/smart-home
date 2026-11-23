import XCTest
@testable import WellnessCore

final class GoalCalculatorTests: XCTestCase {
    func testAgeCountsBirthdaysWithoutTimeZones() throws {
        XCTAssertEqual(try GoalCalculator.calendarAge(birthDate: "1990-06-15", on: "2026-06-14"), 35)
        XCTAssertEqual(try GoalCalculator.calendarAge(birthDate: "1990-06-15", on: "2026-06-15"), 36)
        XCTAssertThrowsError(try GoalCalculator.calendarAge(birthDate: "2030-01-01", on: "2026-06-15"))
        XCTAssertThrowsError(try GoalCalculator.calendarAge(birthDate: "1990-02-31", on: "2026-06-15"))
        XCTAssertThrowsError(try GoalCalculator.calendarAge(birthDate: "1800-01-01", on: "2026-06-15"), "older than 120")
    }
    func testMifflinStJeorTargetsMatchTheWebFormula() throws {
        // BMR = 10*80 + 6.25*180 - 5*36 + 5 = 1750; light x1.375 = 2406.25 -> 2406 kcal; protein 128; fat 67; carbs round((2406-512-603)/4)=323
        let goal = try GoalCalculator.calculate(.init(birthDate: "1990-06-15", height: 180, weight: 80, physiology: "male", activity: "light", objective: "maintain"), on: "2026-06-15")
        XCTAssertEqual(goal, .init(date: "2026-06-15", kcal: 2406, protein: 128, carbs: 323, fat: 67, method: "calculated"))
        let loss = try GoalCalculator.calculate(.init(birthDate: "1990-06-15", height: 165, weight: 60, physiology: "female", activity: "sedentary", objective: "lose"), on: "2026-06-15")
        // BMR = 600 + 1031.25 - 180 - 161 = 1290.25; sedentary x1.2 x0.9 = 1393.47
        XCTAssertEqual(loss.kcal, 1393)
        let tiny = try GoalCalculator.calculate(.init(birthDate: "1990-06-15", height: 150, weight: 45, physiology: "female", activity: "sedentary", objective: "lose"), on: "2026-06-15")
        XCTAssertGreaterThanOrEqual(tiny.kcal, 1000, "a deficit never goes below the BMR")
    }
    func testMinorsAndIncompleteProfilesNeedManualTargets() {
        XCTAssertThrowsError(try GoalCalculator.calculate(.init(birthDate: "2015-01-01", height: 150, weight: 40, physiology: "male"), on: "2026-06-15")) { XCTAssertEqual($0 as? GoalCalculator.Failure, .adultProfileRequired) }
        XCTAssertThrowsError(try GoalCalculator.calculate(.init(birthDate: "1990-06-15", height: nil, weight: 80, physiology: "male"), on: "2026-06-15"))
        XCTAssertThrowsError(try GoalCalculator.calculate(.init(), on: "2026-06-15"))
    }
    func testImplausibleMeasurementsNeedManualTargets() {
        for (h, w) in [(-170.0, 70.0), (170, 0), (170, -5), (30, 70), (170, 900)] {
            XCTAssertThrowsError(try GoalCalculator.calculate(.init(birthDate: "1990-06-15", height: h, weight: w, physiology: "male"), on: "2026-06-15")) { XCTAssertEqual($0 as? GoalCalculator.Failure, .adultProfileRequired) }
        }
    }
}
