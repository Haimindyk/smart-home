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
        app.buttons["edit-meal"].tap()
        XCTAssertTrue(app.navigationBars["עריכת ארוחה"].waitForExistence(timeout: 5))
        capture(app, name: "native-edit-meal")
        app.buttons["ביטול"].tap()
        XCTAssertFalse(app.buttons["Back"].exists, "System navigation should also use the app's Hebrew localization")
        capture(app, name: "native-meal-details")
        app.buttons["tab-workouts"].tap()
        XCTAssertTrue(app.buttons["workout-55555555-5555-8555-8555-555555555555"].waitForExistence(timeout: 5))
        capture(app, name: "native-workouts")
        app.buttons["plan-99999999-9999-4999-8999-999999999999"].tap()
        XCTAssertTrue(app.buttons["start-workout"].waitForExistence(timeout: 5))
        capture(app, name: "native-plan")
        app.buttons["start-workout"].tap()
        XCTAssertTrue(app.staticTexts["0 מתוך 6 סטים"].waitForExistence(timeout: 5))
        let firstSet = app.buttons.matching(identifier: "סמן סט 1 כהושלם").element(boundBy: 0)
        XCTAssertTrue(firstSet.waitForExistence(timeout: 5)); firstSet.tap()
        XCTAssertTrue(app.staticTexts["1 מתוך 6 סטים"].waitForExistence(timeout: 5))
        capture(app, name: "native-live-workout")
        app.buttons["המשך אחר כך"].tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["tab-health"].tap()
        XCTAssertTrue(app.staticTexts["הפעילות שלך"].waitForExistence(timeout: 5))
        app.buttons["מה נשמר בחשבון?"].tap()
        XCTAssertTrue(app.navigationBars["הנתונים שלך"].waitForExistence(timeout: 5))
        capture(app, name: "native-health-privacy")
    }
    func testAddMealSettingsAndWaterScreens() {
        let app = launch("meal")
        XCTAssertTrue(app.descendants(matching: .any)["calories-card"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["add-meal"].tap()
        XCTAssertTrue(app.textFields["חיפוש מוצר לפי שם…"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["סריקת ברקוד"].exists)
        capture(app, name: "native-add-meal")
        app.buttons["ai-meal"].tap()
        XCTAssertTrue(app.staticTexts["אישור שימוש ב־AI"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["מאשר/ת שימוש ב־AI האישי"].exists, "AI must require explicit consent before anything is sent")
        capture(app, name: "native-ai-consent")
        app.navigationBars["ארוחה מתמונה"].buttons["סגור"].tap()
        app.navigationBars["הוספת ארוחה"].buttons["סגור"].tap()
        app.buttons["coach-button"].tap()
        XCTAssertTrue(app.buttons["מאשר/ת שימוש ב־AI האישי"].waitForExistence(timeout: 5), "Coach chat must require the same explicit AI consent")
        capture(app, name: "native-coach-consent")
        app.navigationBars["המאמן שלי"].buttons["סגור"].tap()
        app.buttons["settings-button"].tap()
        if !app.buttons["יציאה מהחשבון"].waitForExistence(timeout: 3) { app.swipeUp() }
        XCTAssertTrue(app.buttons["יציאה מהחשבון"].waitForExistence(timeout: 5))
        capture(app, name: "native-settings")
        app.buttons["סיום"].tap()
        app.buttons["tab-progress"].tap()
        XCTAssertTrue(app.staticTexts["ההתקדמות שלך"].waitForExistence(timeout: 5))
        capture(app, name: "native-progress")
    }
    /// Apple's automated accessibility audit, run as a report: findings are attached to the test result
    /// (contrast, hit-target size, clipped text, Dynamic Type) so regressions are visible without
    /// failing CI on simulator-specific heuristics.
    func testAccessibilityAuditReport() throws {
        let app = launch("meal")
        XCTAssertTrue(app.descendants(matching: .any)["calories-card"].firstMatch.waitForExistence(timeout: 15))
        var findings: [String] = []
        func audit(_ screen: String) {
            do {
                try app.performAccessibilityAudit { issue in
                    findings.append("[\(screen)] \(issue.compactDescription) – '\(issue.element?.label ?? "?")'")
                    return true
                }
            } catch { findings.append("[\(screen)] audit unavailable: \(error.localizedDescription)") }
        }
        audit("today")
        for tab in ["workouts", "health", "progress"] {
            app.buttons["tab-\(tab)"].tap(); sleep(1); audit(tab)
        }
        app.buttons["tab-today"].tap()
        app.buttons["add-meal"].tap()
        XCTAssertTrue(app.textFields["חיפוש מוצר לפי שם…"].waitForExistence(timeout: 5))
        audit("add-meal")
        let report = XCTAttachment(string: findings.isEmpty ? "No findings." : findings.joined(separator: "\n"))
        report.name = "accessibility-audit-findings"; report.lifetime = .keepAlways; add(report)
    }
    func testCoachChatShowsConversationAndComposer() {
        let app = launch("coach")
        XCTAssertTrue(app.descendants(matching: .any)["calories-card"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["coach-button"].tap()
        XCTAssertTrue(app.staticTexts["איך מגיעים לזה עם תזונה צמחונית?"].waitForExistence(timeout: 5) || app.buttons["איך מגיעים לזה עם תזונה צמחונית?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["2/20 הודעות היום"].exists)
        capture(app, name: "native-coach-chat")
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
