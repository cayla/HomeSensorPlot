import XCTest
@testable import SensorPlot

final class TimeBoxTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    func testPresetOffsets() {
        XCTAssertEqual(
            TimeBox.oneHour.startDate(relativeTo: now).timeIntervalSince1970,
            now.timeIntervalSince1970 - 3600,
            accuracy: 0.001
        )
        XCTAssertEqual(
            TimeBox.twentyFourHours.startDate(relativeTo: now).timeIntervalSince1970,
            now.timeIntervalSince1970 - 86_400,
            accuracy: 0.001
        )
        XCTAssertEqual(
            TimeBox.sevenDays.startDate(relativeTo: now).timeIntervalSince1970,
            now.timeIntervalSince1970 - 7 * 86_400,
            accuracy: 0.001
        )
        XCTAssertEqual(
            TimeBox.thirtyDays.startDate(relativeTo: now).timeIntervalSince1970,
            now.timeIntervalSince1970 - 30 * 86_400,
            accuracy: 0.001
        )
    }

    func testCustomUsesProvidedStart() {
        let custom = Date(timeIntervalSince1970: 1_699_000_000)
        XCTAssertEqual(TimeBox.custom.startDate(relativeTo: now, customStart: custom), custom)
    }

    func testCustomFallsBackToOneDay() {
        let start = TimeBox.custom.startDate(relativeTo: now, customStart: nil)
        XCTAssertEqual(start.timeIntervalSince1970, now.timeIntervalSince1970 - 86_400, accuracy: 0.001)
    }
}
