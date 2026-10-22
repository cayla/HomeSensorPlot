import XCTest
@testable import HomeSensorPlot

final class SampleStoreTests: XCTestCase {
    private var directory: URL!
    private var store: SampleStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HomeSensorPlotStore-\(UUID().uuidString)", isDirectory: true)
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

    func testBlockedSensorsOmittedFromLatest() throws {
        try store.upsertSensor(makeSensor(id: "ok", metric: "homekit_temperature_celsius"))
        try store.upsertSensor(makeSensor(id: "nope", metric: "homekit_temperature_celsius", blocked: true))
        try store.insertSample(sensorID: "ok", timestamp: Date(), value: 20)
        try store.insertSample(sensorID: "nope", timestamp: Date(), value: 99)

        let latest = try store.latestSamples(includeHidden: true)
        XCTAssertEqual(latest.map(\.sensorID), ["ok"])
    }

    func testInsertSamplesEmptyIsNoOp() throws {
        try store.insertSamples([])
        XCTAssertTrue(try store.latestSamples().isEmpty)
    }

    func testInsertSamplesRollsBackOnFailure() throws {
        try store.upsertSensor(makeSensor(id: "s1", metric: "homekit_temperature_celsius"))
        let ts = Date()
        XCTAssertThrowsError(
            try store.insertSamples([
                (sensorID: "s1", timestamp: ts, value: 21),
                (sensorID: "missing-fk", timestamp: ts, value: 22),
            ])
        )
        // First row must not commit when a later insert fails.
        XCTAssertTrue(try store.latestSamples().isEmpty)
    }

    func testRebindMovesSamplesAndKeepsFlags() throws {
        let existing = makeSensor(id: "old-home:acc:svc:chr", metric: "homekit_temperature_celsius", hidden: true, blocked: true)
        try store.upsertSensor(existing)
        let ts = Date(timeIntervalSince1970: 1_700_000_000)
        try store.insertSample(sensorID: existing.id, timestamp: ts, value: 19)

        var discovered = existing
        discovered.id = "new-home:acc:svc:chr"
        discovered.isHidden = false
        discovered.isBlocked = false
        try store.rebind([SensorContinuityPair(existing: existing, discovered: discovered)])

        let sensors = try store.allSensors()
        XCTAssertEqual(sensors.map(\.id), [discovered.id])
        XCTAssertTrue(sensors[0].isHidden)
        XCTAssertTrue(sensors[0].isBlocked)
        let points = try store.samples(sensorID: discovered.id, from: ts.addingTimeInterval(-1))
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].value, 19, accuracy: 0.0001)
        XCTAssertTrue(try store.samples(sensorID: existing.id, from: ts.addingTimeInterval(-1)).isEmpty)
    }

    func testDeleteAllCollectedDataKeepsTheFile() throws {
        try store.upsertSensor(makeSensor(id: "s1", metric: "homekit_temperature_celsius"))
        try store.insertSample(sensorID: "s1", timestamp: Date(), value: 1)
        try store.deleteAllCollectedData()
        XCTAssertTrue(try store.allSensors().isEmpty)
        XCTAssertEqual(try store.sampleCount(), 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.databaseURL.path))
    }

    func testLegacyDatabaseIsCopiedOncePerChannel() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HomeSensorPlotLegacy-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        var seeded: SampleStore? = try SampleStore(directory: dir, channel: .development)
        try seeded?.upsertSensor(makeSensor(id: "kept", metric: "homekit_temperature_celsius"))
        try seeded?.insertSample(sensorID: "kept", timestamp: Date(), value: 3)
        let seededURL = try XCTUnwrap(seeded?.databaseURL)
        seeded = nil

        let legacy = dir.appendingPathComponent(SampleStore.legacyDatabaseFileName)
        try FileManager.default.moveItem(at: seededURL, to: legacy)
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: seededURL.path + suffix)
            guard FileManager.default.fileExists(atPath: sidecar.path) else { continue }
            try FileManager.default.moveItem(at: sidecar, to: URL(fileURLWithPath: legacy.path + suffix))
        }

        let testflight = try SampleStore(directory: dir, channel: .testflight)
        XCTAssertEqual(try testflight.allSensors().map(\.id), ["kept"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))

        let appStore = try SampleStore(directory: dir, channel: .appStore)
        XCTAssertEqual(try appStore.allSensors().map(\.id), ["kept"])

        try FileManager.default.removeItem(at: testflight.databaseURL)
        let reopened = try SampleStore(directory: dir, channel: .testflight)
        XCTAssertTrue(try reopened.allSensors().isEmpty)
        XCTAssertEqual(SampleStore.legacyCopiedChannels(in: dir), ["app-store", "testflight"])
    }

    func testOutdoorTemperaturesUpsertAndReplace() throws {
        let hour = Date(timeIntervalSince1970: 1_700_000_000)
        try store.upsertOutdoorTemperatures([
            OutdoorTemperaturePoint(timestamp: hour, celsius: 10),
            OutdoorTemperaturePoint(timestamp: hour.addingTimeInterval(3600), celsius: 11),
        ])
        try store.upsertOutdoorTemperatures([
            OutdoorTemperaturePoint(timestamp: hour, celsius: 12),
        ])

        let points = try store.outdoorTemperatures(
            from: hour.addingTimeInterval(-60),
            to: hour.addingTimeInterval(7200)
        )
        XCTAssertEqual(points.map(\.celsius), [12, 11])
    }

    func testPruneRemovesOldOutdoorHours() throws {
        let old = Date().addingTimeInterval(-10 * 86_400)
        try store.upsertOutdoorTemperatures([
            OutdoorTemperaturePoint(timestamp: old, celsius: 1),
            OutdoorTemperaturePoint(timestamp: Date(), celsius: 2),
        ])
        _ = try store.prune(retentionDays: 5)
        let points = try store.outdoorTemperatures(
            from: Date().addingTimeInterval(-30 * 86_400),
            to: Date().addingTimeInterval(60)
        )
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].celsius, 2, accuracy: 0.0001)
    }

    func testLatestSampleBeforeIsStrict() throws {
        try store.upsertSensor(makeSensor(id: "s1", metric: "homekit_temperature_celsius"))
        let boundary = Date(timeIntervalSince1970: 1_700_000_000)
        try store.insertSample(sensorID: "s1", timestamp: boundary.addingTimeInterval(-120), value: 10)
        try store.insertSample(sensorID: "s1", timestamp: boundary, value: 11)
        try store.insertSample(sensorID: "s1", timestamp: boundary.addingTimeInterval(60), value: 12)

        let anchor = try XCTUnwrap(store.latestSample(sensorID: "s1", before: boundary))
        XCTAssertEqual(anchor.value, 10, accuracy: 0.0001)
        XCTAssertNil(try store.latestSample(sensorID: "s1", before: boundary.addingTimeInterval(-120)))
        XCTAssertNil(try store.latestSample(sensorID: "missing", before: boundary))
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
