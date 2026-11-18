import XCTest
@testable import WellnessCore

final class QuickAddTests: XCTestCase {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Jerusalem")!; return c }
    private var now: Date { cal.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 9))! }
    func testTomorrowAndTodayInHebrewAndEnglish() {
        let t = QuickAdd.parse("לקנות חלב מחר", now: now, calendar: cal)
        XCTAssertEqual(t.title, "לקנות חלב"); XCTAssertEqual(t.due, cal.date(from: DateComponents(year: 2026, month: 11, day: 19)))
        XCTAssertEqual(QuickAdd.parse("call mom today", now: now, calendar: cal).due, cal.startOfDay(for: now))
        XCTAssertEqual(QuickAdd.parse("Buy milk Tomorrow", now: now, calendar: cal).title, "Buy milk")
    }
    func testNumericDates() {
        XCTAssertEqual(QuickAdd.parse("לשלם ארנונה 25/1/27", now: now, calendar: cal).due, cal.date(from: DateComponents(year: 2027, month: 1, day: 25)))
        XCTAssertEqual(QuickAdd.parse("תור 3/8", now: now, calendar: cal).due, cal.date(from: DateComponents(year: 2026, month: 8, day: 3)))
        XCTAssertNil(QuickAdd.parse("תור 31/2", now: now, calendar: cal).due, "invalid date is not a due date")
    }
    func testPlainTextAndWordsContainingKeywordsAreUntouched() {
        XCTAssertEqual(QuickAdd.parse("לקנות חלב", now: now, calendar: cal), .init(title: "לקנות חלב", due: nil))
        XCTAssertNil(QuickAdd.parse("מחרוזת פנינים", now: now, calendar: cal).due)
        XCTAssertEqual(QuickAdd.parse("מחר", now: now, calendar: cal).title, "מחר", "never leave an empty title")
    }
}
