import XCTest
@testable import HomeSensorPlot

final class NumberFormattingTests: XCTestCase {
    func testPortNeverUsesGrouping() {
        // Even in locales that group thousands, exporter ports must stay ungrouped.
        XCTAssertEqual(NumberFormatting.port(9105), "9105")
        XCTAssertEqual(NumberFormatting.port(12_345), "12345")
    }
}
