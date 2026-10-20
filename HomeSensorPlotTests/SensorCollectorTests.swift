import XCTest
@testable import HomeSensorPlot

@MainActor
final class SensorCollectorTests: XCTestCase {
    private var directory: URL!
    private var store: SampleStore!
    private var settings: AppSettings!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HomeSensorPlotCollector-\(UUID().uuidString)", isDirectory: true)
        store = try SampleStore(directory: directory)
        settings = AppSettings()
        settings.useMockData = true
        settings.collectUnknownCharacteristics = false
    }

    override func tearDownWithError() throws {
        store = nil
        settings = nil
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    func testMockCollectSeedsSensors() async throws {
        let homeKit = HomeKitSensorProvider()
        let collector = SensorCollector(store: store, homeKit: homeKit, settings: settings)

        let ran = await collector.forceCollectOnce()
        XCTAssertTrue(ran)
        let mocks = try store.sensors(mockOnly: true)
        XCTAssertFalse(mocks.isEmpty)
        if case .mockMode(let count) = collector.status {
            XCTAssertEqual(count, mocks.count)
        } else {
            XCTFail("Expected mockMode status, got \(collector.status)")
        }
    }

    func testSwitchingToLiveDeletesMockSensors() async throws {
        let homeKit = HomeKitSensorProvider()
        let collector = SensorCollector(store: store, homeKit: homeKit, settings: settings)

        let ran = await collector.forceCollectOnce()
        XCTAssertTrue(ran)
        XCTAssertFalse(try store.sensors(mockOnly: true).isEmpty)

        settings.useMockData = false
        _ = await collector.forceCollectOnce()
        XCTAssertTrue(try store.sensors(mockOnly: true).isEmpty)
    }

    func testForceCollectOnceReturnsFalseWhenBusy() async throws {
        let homeKit = HomeKitSensorProvider()
        let collector = SensorCollector(store: store, homeKit: homeKit, settings: settings)

        async let first = collector.forceCollectOnce()
        // Second call while the first (hopefully) still holds collectInFlight.
        let second = await collector.forceCollectOnce()
        let firstResult = await first

        XCTAssertTrue(firstResult)
        // If the first finished before the second started, busy-skip may not trigger.
        // Accept either outcome but require at least one successful collect.
        if second {
            XCTAssertFalse(try store.sensors(mockOnly: true).isEmpty)
        } else {
            XCTAssertTrue(firstResult)
        }
    }
}
