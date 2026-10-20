import XCTest
@testable import SensorPlot

final class NumberFormattingTests: XCTestCase {
    func testPortNeverUsesGrouping() {
        // Even in locales that group thousands, exporter ports must stay ungrouped.
        XCTAssertEqual(NumberFormatting.port(9105), "9105")
        XCTAssertEqual(NumberFormatting.port(12_345), "12345")
    }
}
