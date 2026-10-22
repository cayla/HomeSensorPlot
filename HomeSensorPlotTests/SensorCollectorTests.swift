import XCTest
@testable import HomeSensorPlot

@MainActor
final class SensorCollectorTests: XCTestCase {
    private var directory: URL!
    private var store: SampleStore!
    private var settings: AppSettings!
    private var defaultsSuite: String!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HomeSensorPlotCollector-\(UUID().uuidString)", isDirectory: true)
        store = try SampleStore(directory: directory)
        defaultsSuite = "HomeSensorPlotTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        defaults.removePersistentDomain(forName: defaultsSuite)
        settings = AppSettings(defaults: defaults)
        settings.useMockData = true
        settings.collectUnknownCharacteristics = false
    }

    override func tearDownWithError() throws {
        store = nil
        settings = nil
        if let defaultsSuite {
            UserDefaults(suiteName: defaultsSuite)?.removePersistentDomain(forName: defaultsSuite)
        }
        defaultsSuite = nil
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
        collector.suspendCollectForTesting = true
        defer { collector.resumeCollectHoldForTesting() }

        let first = Task { await collector.forceCollectOnce() }
        let deadline = Date().addingTimeInterval(2)
        while !collector.isCollecting, Date() < deadline {
            await Task.yield()
        }
        XCTAssertTrue(collector.isCollecting)

        let second = await collector.forceCollectOnce()
        XCTAssertFalse(second)

        collector.resumeCollectHoldForTesting()
        let firstResult = await first.value
        XCTAssertTrue(firstResult)
        XCTAssertFalse(try store.sensors(mockOnly: true).isEmpty)
    }
}
