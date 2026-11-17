import XCTest

final class WellnessUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-test-\(scenario)"]
        app.launch(); return app
    }
    private func capture(_ app: XCUIApplication, name: String) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
    private func logicalText(_ value: Any?) -> String {
        // SwiftUI inserts Unicode direction isolates around interpolated Hebrew.
        let text = value as? String ?? ""
        return String(String.UnicodeScalarView(text.unicodeScalars.filter {
            !(0x2066...0x2069).contains($0.value) && $0.value != 0x200e && $0.value != 0x200f
        }))
    }
    func testEmptyDayHasZeroConsumptionAndCalendarOpens() {
        let app = launch("empty")
        let calories = app.descendants(matching: .any)["calories-card"].firstMatch
        XCTAssertTrue(calories.waitForExistence(timeout: 15))
        XCTAssertEqual(logicalText(calories.value), "0 מתוך 1800")
        XCTAssertFalse(app.buttons["הוסף מים"].exists)
        capture(app, name: "native-empty-day")
        app.buttons["date-picker"].tap()
        XCTAssertTrue(app.buttons["סיום"].waitForExistence(timeout: 5))
        app.buttons["סיום"].tap()
    }
    func testMealsHistoryAndHealthNavigation() {
        let app = launch("meal")
        let calories = app.descendants(matching: .any)["calories-card"].firstMatch
        XCTAssertTrue(calories.waitForExistence(timeout: 15))
        XCTAssertEqual(logicalText(calories.value), "150 מתוך 1800")
        capture(app, name: "native-today")
        let meal = app.buttons["meal-33333333-3333-4333-8333-333333333333"]
        // A partially visible card can be reported hittable while its center is
        // under the floating tab bar. Bring the whole card into the viewport.
        app.swipeUp()
        XCTAssertTrue(meal.waitForExistence(timeout: 5)); meal.tap()
        XCTAssertTrue(app.navigationBars["ארוחת בדיקה"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["טונה"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Back"].exists, "System navigation should also use the app's Hebrew localization")
        capture(app, name: "native-meal-details")
        app.buttons["tab-workouts"].tap()
        XCTAssertTrue(app.buttons["workout-55555555-5555-8555-8555-555555555555"].waitForExistence(timeout: 5))
        capture(app, name: "native-workouts")
        app.buttons["tab-health"].tap()
        XCTAssertTrue(app.staticTexts["הפעילות שלך"].waitForExistence(timeout: 5))
        app.buttons["מה נשמר בחשבון?"].tap()
        XCTAssertTrue(app.navigationBars["הנתונים שלך"].waitForExistence(timeout: 5))
        capture(app, name: "native-health-privacy")
    }
    func testLoginRequiresFourDigits() {
        let app = launch("login")
        let pin = app.secureTextFields.firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["כניסה"].isEnabled)
        pin.tap(); pin.typeText("1234")
        XCTAssertTrue(app.buttons["כניסה"].isEnabled)
        capture(app, name: "native-login")
    }
}
