import XCTest
@testable import HomeSensorPlot

@MainActor
final class HomeKitSensorProviderTests: XCTestCase {
    func testWaitUntilHomesUpdateReturnsWithinTimeout() async {
        let provider = HomeKitSensorProvider()
        let start = Date()
        await provider.waitUntilHomesUpdate(timeoutSeconds: 0.25)
        let elapsed = Date().timeIntervalSince(start)
        // Either HomeKit answered quickly or the timeout resumed waiters.
        XCTAssertLessThan(elapsed, 2.0)
    }
}
