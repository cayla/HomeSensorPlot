import XCTest
@testable import HomeSensorPlot

final class SampleAcceptanceDebouncerTests: XCTestCase {
    func testAcceptsFirstThenDebouncesWithinWindow() {
        var gate = SampleAcceptanceDebouncer(window: 2)
        let t0 = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(gate.shouldAccept(sensorID: "a", at: t0))
        XCTAssertFalse(gate.shouldAccept(sensorID: "a", at: t0.addingTimeInterval(1.9)))
        XCTAssertTrue(gate.shouldAccept(sensorID: "a", at: t0.addingTimeInterval(2.0)))
    }

    func testDifferentSensorsIndependent() {
        var gate = SampleAcceptanceDebouncer(window: 2)
        let t0 = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(gate.shouldAccept(sensorID: "a", at: t0))
        XCTAssertTrue(gate.shouldAccept(sensorID: "b", at: t0.addingTimeInterval(0.1)))
        XCTAssertFalse(gate.shouldAccept(sensorID: "a", at: t0.addingTimeInterval(0.5)))
    }
}
