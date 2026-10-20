import XCTest
@testable import SensorPlot

final class SampleStoreTests: XCTestCase {
    private var directory: URL!
    private var store: SampleStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SensorPlotStore-\(UUID().uuidString)", isDirectory: true)
        store = try SampleStore(directory: directory)
    }

    override func tearDownWithError() throws {
        store = nil
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    func testUpsertInsertSampleAndLatest() throws {
        try store.upsertSensor(makeSensor(id: "s1", metric: "homekit_temperature_celsius"))
        let ts = Date(timeIntervalSince1970: 1_700_000_100)
        try store.insertSample(sensorID: "s1", timestamp: ts, value: 22.5)

        let latest = try store.latestSamples()
        XCTAssertEqual(latest.count, 1)
        XCTAssertEqual(latest[0].value, 22.5, accuracy: 0.0001)
        XCTAssertEqual(latest[0].sensorID, "s1")
    }

    func testHideStillExportsWhenIncludeHidden() throws {
        try store.upsertSensor(makeSensor(id: "s1", metric: "homekit_humidity_percent", hidden: true))
        try store.insertSample(sensorID: "s1", timestamp: Date(), value: 40)

        XCTAssertTrue(try store.latestSamples(includeHidden: false).isEmpty)
        XCTAssertEqual(try store.latestSamples(includeHidden: true).count, 1)
    }

    func testPruneRemovesOldSamples() throws {
        try store.upsertSensor(makeSensor(id: "s1", metric: "homekit_battery_percent"))
        let old = Date().addingTimeInterval(-10 * 86_400)
        let recent = Date()
        try store.insertSample(sensorID: "s1", timestamp: old, value: 50)
        try store.insertSample(sensorID: "s1", timestamp: recent, value: 80)

        let removed = try store.prune(retentionDays: 5)
        XCTAssertEqual(removed, 1)

        let points = try store.samples(
            sensorID: "s1",
            from: Date().addingTimeInterval(-30 * 86_400),
            to: Date().addingTimeInterval(60)
        )
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].value, 80, accuracy: 0.0001)
    }

    func testDeleteMockAndAutoMetrics() throws {
        try store.upsertSensor(makeSensor(id: "mock:temp", metric: "homekit_temperature_celsius"))
        try store.upsertSensor(makeSensor(id: "live", metric: "homekit_temperature_celsius"))
        try store.upsertSensor(makeSensor(id: "auto", metric: "homekit_auto_camera_foo"))
        try store.insertSample(sensorID: "mock:temp", timestamp: Date(), value: 1)
        try store.insertSample(sensorID: "live", timestamp: Date(), value: 2)
        try store.insertSample(sensorID: "auto", timestamp: Date(), value: 3)

        try store.deleteMockSensors()
        try store.deleteAutoMetricSensors()

        let ids = Set(try store.allSensors().map(\.id))
        XCTAssertEqual(ids, ["live"])
    }

    private func makeSensor(
        id: String,
        metric: String,
        hidden: Bool = false,
        blocked: Bool = false
    ) -> SensorRecord {
        SensorRecord(
            id: id,
            homeName: "Home",
            roomName: "Room",
            accessoryName: "Accessory",
            serviceName: "Service",
            characteristicType: "HMCharacteristicTypeCurrentTemperature",
            metricName: metric,
            unit: "value",
            isHidden: hidden,
            isBlocked: blocked,
            autoDiscovered: true,
            lastValue: nil,
            lastUpdated: nil
        )
    }
}
