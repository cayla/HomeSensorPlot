import XCTest
@testable import HomeSensorPlot

final class NumberFormattingTests: XCTestCase {
    func testPortNeverUsesGrouping() {
        // Even in locales that group thousands, exporter ports must stay ungrouped.
        XCTAssertEqual(NumberFormatting.port(9105), "9105")
        XCTAssertEqual(NumberFormatting.port(12_345), "12345")
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
