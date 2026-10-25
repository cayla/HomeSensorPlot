import XCTest
@testable import HomeSensorPlot

final class NumberFormattingTests: XCTestCase {
    func testPortNeverUsesGrouping() {
        // Even in locales that group thousands, exporter ports must stay ungrouped.
        XCTAssertEqual(NumberFormatting.port(9105), "9105")
        XCTAssertEqual(NumberFormatting.port(12_345), "12345")
    }

    func testMeasurementStopsAtOneDecimal() {
        XCTAssertEqual(NumberFormatting.measurement(46.04), NumberFormatting.measurement(46))
        XCTAssertEqual(NumberFormatting.measurement(64), NumberFormatting.measurement(64.0))
        XCTAssertNotEqual(NumberFormatting.measurement(64), "64")
        XCTAssertEqual(NumberFormatting.measurement(67.64), NumberFormatting.measurement(67.6))
        XCTAssertEqual(
            NumberFormatting.withUnit(NumberFormatting.measurement(67.64), "°"),
            NumberFormatting.measurement(67.6) + "°"
        )
        XCTAssertEqual(NumberFormatting.withUnit("12.3", "lux"), "12.3 lux")
        XCTAssertEqual(NumberFormatting.withUnit("4.2", "µg/m³"), "4.2 µg/m³")
    }

    func testLargeMeasurementsUseACompactSuffix() {
        XCTAssertEqual(
            NumberFormatting.measurement(5_347.7),
            NumberFormatting.measurement(5.3477) + "k"
        )
        XCTAssertEqual(
            NumberFormatting.measurement(1_000),
            NumberFormatting.measurement(1) + "k"
        )
        XCTAssertEqual(
            NumberFormatting.measurement(-2_500),
            NumberFormatting.measurement(-2.5) + "k"
        )
        XCTAssertEqual(
            NumberFormatting.measurement(1_500_000),
            NumberFormatting.measurement(1.5) + "M"
        )
        XCTAssertFalse(NumberFormatting.measurement(999.9).hasSuffix("k"))
    }
}

final class WindowFrameStoreTests: XCTestCase {
    func testAppKitBottomLeftConvertsToSystemTopLeft() {
        // Primary screen is 1000pt tall. A 200×100 window flush with the bottom-left
        // sits 900pt down from the top-left in system coordinates.
        let appKit = CGRect(x: 10, y: 0, width: 200, height: 100)
        let system = WindowFrameStore.systemFrame(fromAppKitFrame: appKit, primaryScreenMaxY: 1000)
        XCTAssertEqual(system, CGRect(x: 10, y: 900, width: 200, height: 100))
    }

    func testWindowUnderTheMenuBarStaysNearTheTop() {
        let appKit = CGRect(x: 40, y: 900, width: 200, height: 100)
        let system = WindowFrameStore.systemFrame(fromAppKitFrame: appKit, primaryScreenMaxY: 1000)
        XCTAssertEqual(system.origin.x, 40)
        XCTAssertEqual(system.origin.y, 0)
    }
}
