import XCTest

final class WellnessUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-test-\(scenario)"]
        app.launch()
        dismissSystemAlerts(for: app)
        return app
    }
    /// The simulator can raise unrelated system dialogs (e.g. Apple ID verification) over the app; dismiss them.
    private func dismissSystemAlerts(for app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["לא כעת", "Not Now", "אל תאפשר", "Don’t Allow", "אישור", "OK"] {
            let button = springboard.alerts.buttons[label]
            if button.waitForExistence(timeout: 1.5) { button.tap(); break }
        }
        if app.state != .runningForeground { app.activate() }
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
        app.navigationBars.buttons["BackButton"].tap()  // back from meal details to the health tabs
        app.buttons["tab-workouts"].tap()
        XCTAssertTrue(app.buttons["workout-55555555-5555-8555-8555-555555555555"].waitForExistence(timeout: 5))
        capture(app, name: "native-workouts")
        app.buttons["new-plan"].tap()
        XCTAssertTrue(app.textFields["plan-name"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["save-plan"].isEnabled, "An empty plan must not be savable")
        capture(app, name: "native-new-plan")
        app.buttons["pick-exercise"].tap()
        XCTAssertTrue(app.navigationBars["קטלוג תרגילים"].waitForExistence(timeout: 5))
        capture(app, name: "native-exercise-catalog")
        app.buttons["catalog-Push_Up"].firstMatch.tap()
        XCTAssertTrue(app.textFields["שכיבות סמיכה"].waitForExistence(timeout: 5), "Picking a catalog exercise fills the exercise name")
        XCTAssertFalse(app.buttons["save-plan"].isEnabled, "A plan still needs a name before it can be saved")
        app.buttons["ביטול"].tap()
        app.buttons["plan-99999999-9999-4999-8999-999999999999"].tap()
        XCTAssertTrue(app.buttons["start-workout"].waitForExistence(timeout: 5))
        capture(app, name: "native-plan")
        app.buttons["demo-Cable_Crossover"].tap()
        XCTAssertTrue(app.navigationBars["פרפר בכבלים"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["דגשי ביצוע"].exists)
        capture(app, name: "native-exercise-demo")
        app.buttons["סגור"].tap()
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
    func testAITrainerFlowRequiresApprovalBeforeSaving() {
        let app = launch("coach")
        XCTAssertTrue(app.descendants(matching: .any)["calories-card"].firstMatch.waitForExistence(timeout: 15))
        app.buttons["tab-workouts"].tap()
        app.buttons["trainer-button"].tap()
        XCTAssertTrue(app.navigationBars["מאמן AI"].waitForExistence(timeout: 5))
        capture(app, name: "native-trainer-form")
        var tries = 0
        while !app.buttons["trainer-generate"].exists && tries < 6 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(app.buttons["trainer-generate"].exists, "The form must be able to reach its submit button")
        app.buttons["trainer-generate"].tap()
        XCTAssertTrue(app.buttons["trainer-apply"].waitForExistence(timeout: 5), "The proposal must be shown for approval before anything is saved")
        XCTAssertTrue(app.staticTexts["שכיבות סמיכה"].exists)
        capture(app, name: "native-trainer-proposal")
    }
    func testHouseholdHomeShoppingChoresAndCalendar() {
        let app = launch("home")
        let tasksChip = app.buttons["section-a0000000-0000-4000-8000-000000000001"]
        _ = tasksChip.waitForExistence(timeout: 10); capture(app, name: "native-home-landing")
        XCTAssertTrue(tasksChip.exists, "The household home is the landing screen")
        let toggle = app.buttons["task-toggle-b0000000-0000-4000-8000-000000000001"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        capture(app, name: "native-home-tasks")
        let apply = app.buttons["suggestion-apply-e0000000-0000-4000-8000-000000000001"]
        XCTAssertTrue(apply.exists, "Open assistant suggestions are shown with an apply button")
        apply.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: apply); waitForExpectations(timeout: 5)
        toggle.tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: toggle); waitForExpectations(timeout: 5)  // moves to the completed group at once
        app.buttons["section-a0000000-0000-4000-8000-000000000002"].tap()
        XCTAssertTrue(app.staticTexts["חלב"].waitForExistence(timeout: 5))
        capture(app, name: "native-home-shopping")
        app.buttons["section-a0000000-0000-4000-8000-000000000003"].tap()
        XCTAssertTrue(app.staticTexts["להוציא את הזבל"].waitForExistence(timeout: 5))
        capture(app, name: "native-home-chores")
        let notesChip = app.buttons["section-a0000000-0000-4000-8000-000000000004"]
        if !notesChip.isHittable { app.buttons["section-a0000000-0000-4000-8000-000000000003"].swipeRight() }
        notesChip.tap()
        XCTAssertTrue(app.staticTexts["קוד ל-WiFi של האורחים"].waitForExistence(timeout: 5))
        capture(app, name: "native-home-notes")
        app.buttons["add-meal"].tap()
        XCTAssertTrue(app.textFields["quick-add-title"].waitForExistence(timeout: 5))
        capture(app, name: "native-home-quick-add")
        app.buttons["ביטול"].tap()
        app.buttons["root-calendar"].tap()
        XCTAssertTrue(app.buttons["event-d0000000-0000-4000-8000-000000000001"].waitForExistence(timeout: 5))
        capture(app, name: "native-calendar")
    }
    func testHouseholdMenuCreatesSectionSearchesAndListsMembers() {
        let app = launch("home")
        XCTAssertTrue(app.buttons["home-menu"].waitForExistence(timeout: 15))
        app.buttons["home-menu"].tap()
        app.buttons["מדור חדש"].tap()
        let name = app.textFields["section-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("מוצרי ניקיון")
        app.buttons["section-save"].tap()
        XCTAssertTrue(app.buttons["מוצרי ניקיון"].waitForExistence(timeout: 5), "A new section appears as a chip and is selected")
        app.buttons["home-menu"].tap()
        app.buttons["בני הבית"].tap()
        XCTAssertTrue(app.staticTexts["נועה"].waitForExistence(timeout: 5))
        capture(app, name: "native-home-members")
        app.buttons["סגור"].tap()
        app.buttons["home-search"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("חלב")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "חלב")).firstMatch.waitForExistence(timeout: 5))
        capture(app, name: "native-home-search")
    }
    func testHouseholdTaskEditorAddsSubtask() {
        let app = launch("home")
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "לשלם ארנונה")).element(boundBy: 0)
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()
        let field = app.textFields["subtask-field"]
        var tries = 0
        while !field.exists && tries < 6 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(field.exists, "The editor offers subtasks")
        field.tap(); field.typeText("לצלם את החשבון\n")
        XCTAssertTrue(app.staticTexts["לצלם את החשבון"].waitForExistence(timeout: 5))
        capture(app, name: "native-home-subtask")
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
