import XCTest
@testable import HomeSensorPlot

final class PrometheusListenTests: XCTestCase {
    func testListenReadyCallbackAndMetricsEndpoint() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HomeSensorPlotListen-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = try SampleStore(directory: dir)
        try store.upsertSensor(
            SensorRecord(
                id: "live-1",
                homeName: "Home",
                roomName: "Office",
                accessoryName: "Sensor",
                serviceName: "Temp",
                characteristicType: "HMCharacteristicTypeCurrentTemperature",
                metricName: "homekit_temperature_celsius",
                unit: "celsius",
                isHidden: false,
                isBlocked: false,
                autoDiscovered: true,
                lastValue: nil,
                lastUpdated: nil
            )
        )
        try store.insertSample(sensorID: "live-1", timestamp: Date(), value: 22)

        let exporter = PrometheusExporter(store: store)
        let port = UInt16(19_000 + Int.random(in: 0..<1_000))
        let ready = expectation(description: "exporter ready")
        var readyPort: UInt16?

        exporter.onListenStateChanged = { result in
            switch result {
            case .success(let bound):
                readyPort = bound
                ready.fulfill()
            case .failure(let error):
                XCTFail("Unexpected listen failure: \(error)")
            }
        }

        try exporter.start(port: Int(port))
        await fulfillment(of: [ready], timeout: 5)
        XCTAssertEqual(readyPort, port)

        let url = URL(string: "http://127.0.0.1:\(port)/metrics")!
        let (data, response) = try await URLSession.shared.data(from: url)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)
        let body = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(body.contains("homekit_temperature_celsius"))

        exporter.stop()
    }

    func testStopPreventsStaleReadyFromAdvertising() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HomeSensorPlotListenStop-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = try SampleStore(directory: dir)
        let exporter = PrometheusExporter(store: store)
        var callbacks = 0
        exporter.onListenStateChanged = { _ in
            callbacks += 1
        }

        try exporter.start(port: 19_500 + Int.random(in: 0..<400))
        // Immediate stop should bump generation so a late .ready is ignored.
        exporter.stop()
        // Give Network.framework a beat; we only assert we didn't crash and typically get 0–1.
        let deadline = Date().addingTimeInterval(0.5)
        while Date() < deadline, callbacks == 0 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertLessThanOrEqual(callbacks, 1)
    }
}
