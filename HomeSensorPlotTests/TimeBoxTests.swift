import XCTest
@testable import HomeSensorPlot

final class TimeBoxTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testTrailingWindowsEndAtNow() {
        assertTrailing(.lastHour, seconds: 3600)
        assertTrailing(.lastDay, seconds: 86_400)
        assertTrailing(.lastWeek, seconds: 7 * 86_400)
        assertTrailing(.lastMonth, seconds: 30 * 86_400)
    }

    func testCalendarWindowsAreTheContainingUnit() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 1

        assertCalendar(.thisHour, component: .hour, calendar: calendar)
        assertCalendar(.today, component: .day, calendar: calendar)
        assertCalendar(.thisWeek, component: .weekOfYear, calendar: calendar)
        assertCalendar(.thisMonth, component: .month, calendar: calendar)
    }

    func testCalendarWindowIsNotTheTrailingWindow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let hour = TimeBox.thisHour.window(relativeTo: now, calendar: calendar)
        XCTAssertNotEqual(hour.start, now.addingTimeInterval(-3600))
        XCTAssertGreaterThan(hour.end, now)
    }

    func testCustomUsesProvidedStartAndEndsAtNow() {
        let custom = now.addingTimeInterval(-5000)
        let window = TimeBox.custom.window(relativeTo: now, customStart: custom)
        XCTAssertEqual(window.start, custom)
        XCTAssertEqual(window.end, now)
    }

    func testCustomFallsBackToOneDay() {
        let window = TimeBox.custom.window(relativeTo: now, customStart: nil)
        XCTAssertEqual(window.start, now.addingTimeInterval(-86_400))
        XCTAssertEqual(window.end, now)
    }

    func testCustomStartInTheFutureStaysNearNow() {
        let window = TimeBox.custom.window(relativeTo: now, customStart: now.addingTimeInterval(3600))
        XCTAssertEqual(window.start, now)
        XCTAssertEqual(window.end, now.addingTimeInterval(60))
    }

    func testPlottedDomainEndsAtNow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let hour = TimeBox.thisHour.window(relativeTo: now, calendar: calendar)
        let plotted = hour.plottedDomain(now: now)
        XCTAssertEqual(plotted.lowerBound, hour.start)
        XCTAssertEqual(plotted.upperBound, now)
        XCTAssertLessThan(now, hour.end)

        let trailing = TimeBox.lastHour.window(relativeTo: now).plottedDomain(now: now)
        XCTAssertEqual(trailing.lowerBound, now.addingTimeInterval(-3600))
        XCTAssertEqual(trailing.upperBound, now)
    }

    func testSampleEndStopsAtNow() {
        let window = ChartTimeWindow(start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(3600))
        XCTAssertEqual(window.sampleEnd(now: now), now)
        let trailing = ChartTimeWindow(start: now.addingTimeInterval(-3600), end: now)
        XCTAssertEqual(trailing.sampleEnd(now: now), now)
    }

    private func assertTrailing(_ box: TimeBox, seconds: TimeInterval) {
        let window = box.window(relativeTo: now)
        XCTAssertEqual(window.end, now)
        XCTAssertEqual(window.start.timeIntervalSince1970, now.timeIntervalSince1970 - seconds, accuracy: 0.001)
    }

    private func assertCalendar(_ box: TimeBox, component: Calendar.Component, calendar: Calendar) {
        let window = box.window(relativeTo: now, calendar: calendar)
        let expected = calendar.dateInterval(of: component, for: now)!
        XCTAssertEqual(window.start, expected.start)
        XCTAssertEqual(window.end, expected.end)
        XCTAssertLessThanOrEqual(window.start, now)
        XCTAssertGreaterThan(window.end, now)
    }
}
