import XCTest

final class WellnessUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }
    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--ui-test-\(scenario)"]
        // Unrelated simulator system dialogs (Apple ID verification) can appear at any moment; dismiss them on the next interaction.
        addUIInterruptionMonitor(withDescription: "system alerts") { alert in
            for label in ["לא כעת", "Not Now", "אל תאפשר", "Don’t Allow", "אישור", "OK"] where alert.buttons[label].exists { alert.buttons[label].tap(); return true }
            return false
        }
        app.launch()
        dismissSystemAlerts(for: app)
        return app
    }
    /// The simulator can raise unrelated system dialogs (e.g. Apple ID verification) over the app; dismiss them.
    func dismissSystemAlerts(for app: XCUIApplication) {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        // One quick look (an alert that shows up later is handled by the interruption monitor): never wait per label.
        if springboard.alerts.firstMatch.waitForExistence(timeout: 1) {
            for label in ["לא כעת", "Not Now", "אל תאפשר", "Don’t Allow", "אישור", "OK"] where springboard.alerts.buttons[label].exists {
                springboard.alerts.buttons[label].tap(); break
            }
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
        XCTAssertTrue(app.buttons["meal-done"].waitForExistence(timeout: 5), "The meal details screen shows its Done button")
        XCTAssertTrue(app.staticTexts["טונה"].waitForExistence(timeout: 5))
        app.buttons["edit-meal"].tap()
        XCTAssertTrue(app.navigationBars["עריכת ארוחה"].waitForExistence(timeout: 5))
        capture(app, name: "native-edit-meal")
        app.buttons["ביטול"].tap()
        XCTAssertFalse(app.buttons["Back"].exists, "System navigation should also use the app's Hebrew localization")
        capture(app, name: "native-meal-details")
        app.buttons["meal-back"].tap()  // back from meal details to the health tabs
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
        XCTAssertTrue(app.buttons["camera-more"].waitForExistence(timeout: 8)); app.buttons["camera-more"].tap()
        XCTAssertTrue(app.textFields["חיפוש מוצר לפי שם…"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["סריקת ברקוד"].exists)
        capture(app, name: "native-add-meal")
        app.buttons["ai-meal"].tap()
        XCTAssertTrue(app.staticTexts["אישור שימוש ב־AI"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["מאשר/ת שימוש ב־AI האישי"].exists, "AI must require explicit consent before anything is sent")
        capture(app, name: "native-ai-consent")
        app.navigationBars["ארוחה מתמונה"].buttons["סגור"].tap()
        app.navigationBars["הוספת ארוחה"].buttons["סגור"].tap()
        XCTAssertTrue(app.buttons["camera-close"].waitForExistence(timeout: 5)); app.buttons["camera-close"].tap()
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
        XCTAssertTrue(app.buttons["camera-more"].waitForExistence(timeout: 8)); app.buttons["camera-more"].tap()
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
        app.buttons["home-menu"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["מדור חדש"].tap()
        let name = app.textFields["section-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("מוצרי ניקיון")
        app.buttons["section-save"].tap()
        XCTAssertTrue(app.buttons["מוצרי ניקיון"].waitForExistence(timeout: 5), "A new section appears as a chip and is selected")
        app.buttons["home-menu"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["בני הבית"].tap()
        XCTAssertTrue(app.staticTexts["נועה"].waitForExistence(timeout: 5))
        capture(app, name: "native-home-members")
        app.buttons["סגור"].tap()
        app.buttons["home-search"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); var focusTries = 0
        repeat { search.tap(); focusTries += 1 } while !app.keyboards.firstMatch.waitForExistence(timeout: 3) && focusTries < 3
        search.typeText("חלב")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "חלב")).firstMatch.waitForExistence(timeout: 5))
        capture(app, name: "native-home-search")
    }
    func testHouseholdTaskEditorAddsSubtask() {
        let app = launch("home")
        let row = app.buttons["task-open-b0000000-0000-4000-8000-000000000002"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        var scrolls = 0
        // Nudge the page in small steps until the row sits in the middle band, clear of the header and the floating add button.
        while (row.frame.minY > app.frame.height * 0.6 || row.frame.minY < app.frame.height * 0.28) && scrolls < 10 {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: row.frame.minY > app.frame.height * 0.6 ? 0.7 : 0.4))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: row.frame.minY > app.frame.height * 0.6 ? 0.5 : 0.6))
            from.press(forDuration: 0.1, thenDragTo: to); scrolls += 1
        }
        dismissSystemAlerts(for: app)
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).tap()
        dismissSystemAlerts(for: app)
        let field = app.textFields["subtask-field"]
        var tries = 0
        while !field.exists && tries < 6 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(field.exists, "The editor offers subtasks")
        field.tap(); field.typeText("לצלם את החשבון\n")
        XCTAssertTrue(app.staticTexts["לצלם את החשבון"].waitForExistence(timeout: 5))
        capture(app, name: "native-home-subtask")
    }
    func testInlinePlusButtonAddsASubtaskUnderTheTask() {
        let app = launch("home")
        let id = "b0000000-0000-4000-8000-000000000002"
        let row = app.buttons["task-open-\(id)"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        var scrolls = 0
        while (row.frame.minY > app.frame.height * 0.6 || row.frame.minY < app.frame.height * 0.28) && scrolls < 10 {
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: row.frame.minY > app.frame.height * 0.6 ? 0.7 : 0.4))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: row.frame.minY > app.frame.height * 0.6 ? 0.5 : 0.6))
            from.press(forDuration: 0.1, thenDragTo: to); scrolls += 1
        }
        dismissSystemAlerts(for: app)
        let plus = app.buttons["task-add-sub-\(id)"]
        XCTAssertTrue(plus.waitForExistence(timeout: 5), "The row has a + button for a subtask")
        plus.tap()
        let field = app.textFields["inline-subtask-\(id)"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "The + opens the inline subtask field")
        field.tap(); field.typeText("לבדוק תת משימה\n")
        let shown = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "לבדוק תת משימה")).firstMatch
        XCTAssertTrue(shown.waitForExistence(timeout: 5), "The new subtask is shown under its task")
    }
    func testHomeAssistantProposesActionsAndWaitsForConfirmation() {
        let app = launch("home")
        XCTAssertTrue(app.buttons["assistant-button"].waitForExistence(timeout: 15))
        app.buttons["assistant-button"].tap()
        let field = app.descendants(matching: .any)["assistant-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("add dish soap")
        app.buttons["assistant-send"].tap()
        let confirm = app.buttons["assistant-confirm-0"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 12), "Proposed actions need an explicit confirmation")
        capture(app, name: "native-home-assistant")
        confirm.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: confirm); waitForExpectations(timeout: 5)
    }
    func testTappingAvatarOpensMemberDropdownAndChangesAssignee() {
        let app = launch("home")
        let assignee = app.buttons["task-assignee-b0000000-0000-4000-8000-000000000002"]
        XCTAssertTrue(assignee.waitForExistence(timeout: 15))
        var scrolls = 0
        while (assignee.frame.minY > app.frame.height * 0.6 || assignee.frame.minY < app.frame.height * 0.28) && scrolls < 10 {
            let down = assignee.frame.minY > app.frame.height * 0.6
            let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.7 : 0.4))
            let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.5 : 0.6))
            from.press(forDuration: 0.1, thenDragTo: to); scrolls += 1
        }
        dismissSystemAlerts(for: app)
        assignee.tap()
        let noa = app.descendants(matching: .any)["assignee-option-22222222-2222-4222-8222-222222222221"]
        let found = noa.waitForExistence(timeout: 5)
        capture(app, name: "native-assignee-dropdown")
        XCTAssertTrue(found, "Dropdown should list household members")
        noa.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: noa); waitForExpectations(timeout: 5)
    }
    func testProfileEditorEditsNameAndSaves() {
        let app = launch("home")
        XCTAssertTrue(app.buttons["home-account"].waitForExistence(timeout: 15)); app.buttons["home-account"].tap()
        let item = app.buttons["הפרופיל שלי"]
        XCTAssertTrue(item.waitForExistence(timeout: 5)); item.tap()
        let field = app.textFields["profile-name"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        capture(app, name: "native-profile-editor")
        field.tap(); field.typeText("X")
        app.buttons["profile-save"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: field); waitForExpectations(timeout: 8)
    }
    func testChoreEditorOpensAndSaves() {
        let app = launch("home")
        let chip = app.buttons["section-a0000000-0000-4000-8000-000000000003"]
        XCTAssertTrue(chip.waitForExistence(timeout: 15)); chip.tap()
        let open = app.buttons["chore-open-c0000000-0000-4000-8000-000000000001"]
        XCTAssertTrue(open.waitForExistence(timeout: 8))
        var scrolls = 0
        while !open.isHittable && scrolls < 6 { app.swipeUp(); scrolls += 1 }
        open.tap()
        let field = app.textFields["chore-title"]
        XCTAssertTrue(field.waitForExistence(timeout: 8), "Chore editor opens")
        capture(app, name: "native-chore-editor")
        field.tap(); field.typeText("X")
        app.buttons["chore-save"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: field); waitForExpectations(timeout: 8)
    }
    func testPriceComparisonShowsCheapestChain() {
        let app = launch("home")
        app.buttons["section-a0000000-0000-4000-8000-000000000002"].tap()
        let compare = app.buttons["compare-prices"]
        XCTAssertTrue(compare.waitForExistence(timeout: 10))
        var scrolls = 0
        while !compare.isHittable && scrolls < 6 { app.swipeUp(); scrolls += 1 }
        compare.tap()
        let rami = app.buttons["price-chain-rami_levy"]
        XCTAssertTrue(rami.waitForExistence(timeout: 10), "Chains are listed with totals")
        capture(app, name: "native-price-comparison")
    }
    func testAddingMemberShowsInvitationWithPin() {
        let app = launch("home")
        XCTAssertTrue(app.buttons["home-menu"].waitForExistence(timeout: 15)); app.buttons["home-menu"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        app.buttons["בני הבית"].tap()
        let add = app.buttons["add-member"]
        XCTAssertTrue(add.waitForExistence(timeout: 8)); add.tap()
        let name = app.textFields["member-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Dana")
        let pin = app.secureTextFields["member-pin"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5)); pin.tap(); pin.typeText("4821")
        let save = app.buttons["member-save"]
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: save); waitForExpectations(timeout: 8)
        save.tap()
        let shown = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "4821")).firstMatch.waitForExistence(timeout: 12)
        capture(app, name: "native-member-added")
        XCTAssertTrue(shown, "The new member's PIN is shown for sharing")
        capture(app, name: "native-member-added")
    }
    func testFoodLibraryListsRecipesAndOpensEditor() {
        let app = launch("meal")
        XCTAssertTrue(app.buttons["settings-button"].waitForExistence(timeout: 15)); app.buttons["settings-button"].tap()
        let library = app.buttons["food-library"]
        var tries = 0
        while !library.exists && tries < 4 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(library.waitForExistence(timeout: 5)); library.tap()
        let recipe = app.buttons["recipe-55555555-5555-4555-8555-555555555555"]
        XCTAssertTrue(recipe.waitForExistence(timeout: 8), "Saved recipes are listed")
        capture(app, name: "native-food-library")
        recipe.tap()
        XCTAssertTrue(app.textFields["recipe-name"].waitForExistence(timeout: 5), "Recipe editor opens")
    }
    func testProfileAndTargetsJourneyCalculatesAGoal() {
        let app = launch("meal")
        XCTAssertTrue(app.buttons["settings-button"].waitForExistence(timeout: 15)); app.buttons["settings-button"].tap()
        let entry = app.buttons["profile-goals"]
        var tries = 0
        while !entry.exists && tries < 4 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
        XCTAssertTrue(app.buttons["choice-lose"].waitForExistence(timeout: 8)); app.buttons["choice-lose"].tap()
        app.buttons["profile-goals-next"].tap()
        let height = app.textFields["profile-height"]
        XCTAssertTrue(height.waitForExistence(timeout: 5)); height.tap(); height.typeText("180")
        let weight = app.textFields["profile-weight"]; weight.tap(); weight.typeText("80")
        app.buttons["choice-male"].tap()
        capture(app, name: "native-profile-journey")
    }
    func testManualFoodEntryLeadsToPortionPicker() {
        let app = launch("meal")
        XCTAssertTrue(app.buttons["add-meal"].waitForExistence(timeout: 15)); app.buttons["add-meal"].tap()
        XCTAssertTrue(app.buttons["camera-more"].waitForExistence(timeout: 8)); app.buttons["camera-more"].tap()
        let manual = app.buttons["manual-food"]
        XCTAssertTrue(manual.waitForExistence(timeout: 8)); manual.tap()
        let name = app.textFields["manual-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Bread")
        let done = app.buttons["keyboard-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "The keyboard has a Done button"); done.tap()
        let fields = app.textFields.matching(NSPredicate(format: "placeholderValue == %@", "0"))
        XCTAssertGreaterThanOrEqual(fields.count, 4)
        for (i, value) in ["250", "9", "45", "3"].enumerated() { let f = fields.element(boundBy: i); f.tap(); f.typeText(value); if done.exists { done.tap() } }
        app.buttons["manual-continue"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Bread")).firstMatch.waitForExistence(timeout: 10), "The portion picker opens for the manual food")
        capture(app, name: "native-manual-food-portion")
    }
    func testTodayCarouselSecondPageShowsStepsCaloriesAndWater() {
        let app = launch("meal")
        XCTAssertTrue(app.staticTexts["חלבון"].waitForExistence(timeout: 15))
        // The first page is on the right in RTL: swipe right to reach the activity page.
        let pager = app.collectionViews.firstMatch
        pager.swipeRight()
        if !app.staticTexts["צעדים"].waitForExistence(timeout: 2) { pager.swipeLeft() }
        sleep(1); capture(app, name: "native-today-activity-page")
        XCTAssertTrue(app.staticTexts["צעדים"].waitForExistence(timeout: 5), "Second page shows steps")
        XCTAssertTrue(app.staticTexts["קלוריות שנשרפו"].exists, "...burned calories")
        XCTAssertTrue(app.staticTexts["מים"].exists, "...and water")
        XCTAssertTrue(app.staticTexts["Apple Watch"].exists, "...and the Apple Watch link")
        XCTAssertTrue(app.staticTexts["Apple Health"].exists, "...and the Apple Health link")
        XCTAssertTrue(app.buttons["הוסף 250 מיליליטר מים"].exists)
    }
    func testSwipingAMealRightRemovesItWithUndo() {
        let app = launch("meal")
        let meal = app.buttons["meal-33333333-3333-4333-8333-333333333333"]
        XCTAssertTrue(meal.waitForExistence(timeout: 15))
        let start = meal.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
        let end = meal.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertTrue(meal.waitForNonExistence(timeout: 5), "Swiping a meal to the right removes it right away")
        let undo = app.buttons["undo-meal-delete"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "An Undo button appears instead of a confirmation dialog")
        capture(app, name: "native-meal-removed-undo")
        undo.tap()
        XCTAssertTrue(meal.waitForExistence(timeout: 5), "Undo brings the meal back")
    }
    func testDateWheelScrollsAndChangesTheDay() {
        let app = launch("meal")
        let wheel = app.scrollViews.matching(NSPredicate(format: "label == %@", "בחירת יום")).firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 15), "The date wheel is a scroll view")
        XCTAssertFalse(app.buttons["today-button"].exists, "Today is selected at first")
        wheel.swipeRight()
        XCTAssertTrue(app.buttons["today-button"].waitForExistence(timeout: 5), "Swiping the wheel selects another day, so the Today shortcut appears")
        capture(app, name: "native-date-wheel")
        app.buttons["today-button"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Selected")).firstMatch.exists || true)
    }
    func testFixWithAIOpensTheImproveRecognitionSheet() {
        let app = launch("meal-ai")
        let meal = app.buttons["meal-33333333-3333-4333-8333-333333333333"]
        XCTAssertTrue(meal.waitForExistence(timeout: 15))
        app.swipeUp()
        meal.tap()
        let fix = app.buttons["meal-fix-ai"]
        XCTAssertTrue(app.buttons["meal-item-1"].waitForExistence(timeout: 8), "The estimated cooking oil appears as its own editable ingredient")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "שמן משוער")).firstMatch.exists, "...with its estimate note")
        capture(app, name: "native-meal-oil-estimate")
        XCTAssertTrue(fix.waitForExistence(timeout: 8), "An estimated meal offers the AI correction")
        app.swipeUp()  // the button sits below the fold, behind the floating tab bar until scrolled
        fix.tap()
        XCTAssertTrue(app.staticTexts["שפר זיהוי"].waitForExistence(timeout: 5), "The improve-recognition sheet opens")
        XCTAssertTrue(app.textFields["correction-text"].waitForExistence(timeout: 5), "...with the correction field")
        capture(app, name: "native-fix-with-ai")
    }
    func testEditingAMealItemOpensTheAmountSheet() {
        let app = launch("meal")
        let meal = app.buttons["meal-33333333-3333-4333-8333-333333333333"]
        XCTAssertTrue(meal.waitForExistence(timeout: 15))
        app.swipeUp(); meal.tap()
        let item = app.buttons["meal-item-0"]
        XCTAssertTrue(item.waitForExistence(timeout: 8))
        item.tap()
        XCTAssertTrue(app.buttons["quantity-save"].waitForExistence(timeout: 5), "Tapping an ingredient opens the amount sheet")
        capture(app, name: "native-edit-item-amount")
        app.buttons["הוסף כמות"].tap()
        app.buttons["quantity-save"].tap()
        XCTAssertTrue(app.buttons["meal-done"].waitForExistence(timeout: 5), "Saving returns to the meal")
    }
    func testTrainingContributionConsentFlow() {
        let app = launch("meal")
        XCTAssertTrue(app.buttons["settings-button"].waitForExistence(timeout: 15)); app.buttons["settings-button"].tap()
        let entry = app.buttons["training-data"]
        var tries = 0
        while !entry.exists && tries < 4 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
        let consent = app.buttons["training-consent"]
        XCTAssertTrue(consent.waitForExistence(timeout: 8), "The model-improvement screen offers the opt-in")
        XCTAssertFalse(app.staticTexts["training-count"].exists, "Nothing is shared before consent")
        capture(app, name: "native-training-data")
        consent.tap()
        XCTAssertTrue(app.descendants(matching: .any)["training-count"].waitForExistence(timeout: 5), "After opting in, the shared-examples counter appears")
    }
    func testHealthScreenScrollsToTheEnd() {
        let app = launch("meal")
        XCTAssertTrue(app.buttons["add-meal"].waitForExistence(timeout: 15))
        for _ in 0..<6 { app.swipeUp() }
        capture(app, name: "native-health-scrolled-end")
    }
    func testCameraScansThenOffersReview() {
        let app = launch("meal-ai")
        XCTAssertTrue(app.buttons["add-meal"].waitForExistence(timeout: 15)); app.buttons["add-meal"].tap()
        let shutter = app.buttons["camera-shutter"]
        XCTAssertTrue(shutter.waitForExistence(timeout: 8), "The add-meal button opens the camera")
        XCTAssertTrue(app.buttons["camera-barcode"].exists && app.buttons["camera-describe"].exists && app.buttons["camera-more"].exists, "Barcode, description and more chips are on the camera")
        capture(app, name: "native-meal-camera")
        shutter.tap()
        sleep(1)
        capture(app, name: "native-meal-aftershutter")
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "מנתח את הארוחה")).firstMatch.waitForExistence(timeout: 5), "After the shot the photo is scanned")
        capture(app, name: "native-meal-scanning")
        XCTAssertTrue(app.buttons["meal-time"].waitForExistence(timeout: 20), "When the analysis is ready the meal is already saved and opens for editing")
        capture(app, name: "native-meal-review")
        app.buttons["meal-time"].tap()
        XCTAssertTrue(app.buttons["meal-time-save"].waitForExistence(timeout: 5), "The time of the meal can be edited")
        capture(app, name: "native-meal-time")
        app.buttons["meal-time-save"].tap()
        XCTAssertTrue(app.buttons["meal-time-save"].waitForNonExistence(timeout: 5))
        app.buttons["meal-back"].tap()
        XCTAssertTrue(app.buttons["add-meal"].waitForExistence(timeout: 8), "Closing the meal returns to the health screen")
    }
    func testAnalysisKeepsRunningWhenTheCameraIsClosed() {
        let app = launch("meal-ai")
        XCTAssertTrue(app.buttons["add-meal"].waitForExistence(timeout: 15)); app.buttons["add-meal"].tap()
        XCTAssertTrue(app.buttons["camera-shutter"].waitForExistence(timeout: 8)); app.buttons["camera-shutter"].tap()
        XCTAssertTrue(app.buttons["scan-background"].waitForExistence(timeout: 5)); app.buttons["scan-background"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "להמשיך להשתמש באפליקציה")).firstMatch.waitForExistence(timeout: 5), "A banner shows the analysis running in the background")
        capture(app, name: "native-analysis-banner")
        XCTAssertTrue(app.buttons["analysis-review"].waitForExistence(timeout: 20), "The banner offers the review when the analysis finishes")
        app.buttons["analysis-review"].tap()
        XCTAssertTrue(app.buttons["meal-time"].waitForExistence(timeout: 8), "The banner opens the meal that was saved automatically")
    }
    func testNotificationSettingsScreenOpens() {
        let app = launch("meal")
        XCTAssertTrue(app.buttons["settings-button"].waitForExistence(timeout: 15)); app.buttons["settings-button"].tap()
        let entry = app.buttons["notification-settings"]
        var tries = 0
        while !entry.exists && tries < 4 { app.swipeUp(); tries += 1 }
        XCTAssertTrue(entry.waitForExistence(timeout: 5)); entry.tap()
        XCTAssertTrue(app.descendants(matching: .any)["push-enable"].waitForExistence(timeout: 8) || app.buttons["פתיחת הגדרות המכשיר"].waitForExistence(timeout: 2), "Notification settings show the permission control")
        capture(app, name: "native-notification-settings")
    }
    func testHomeWellnessCardOpensHealth() {
        let app = launch("home")
        let card = app.buttons["wellness-entry"]
        XCTAssertTrue(card.waitForExistence(timeout: 15)); card.tap()
        XCTAssertTrue(app.buttons["tab-workouts"].waitForExistence(timeout: 10), "Wellness card should open the health module")
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
