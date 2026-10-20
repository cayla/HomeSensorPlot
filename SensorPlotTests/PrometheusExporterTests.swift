import XCTest
@testable import SensorPlot

final class PrometheusExporterTests: XCTestCase {
    func testEscapeLabel() {
        XCTAssertEqual(PrometheusExporter.escapeLabel(#"a\b"c"#), #"a\\b\"c"#)
        XCTAssertEqual(PrometheusExporter.escapeLabel("line\nbreak"), #"line\nbreak"#)
    }

    func testFormatValueSpecials() {
        XCTAssertEqual(PrometheusExporter.formatValue(.nan), "NaN")
        XCTAssertEqual(PrometheusExporter.formatValue(.infinity), "+Inf")
        XCTAssertEqual(PrometheusExporter.formatValue(-.infinity), "-Inf")
        XCTAssertEqual(PrometheusExporter.formatValue(21.5), "21.5")
    }

    func testRenderMetricsIncludesLabelsAndSkipsBlocked() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SensorPlotTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = try SampleStore(directory: dir)
        try store.upsertSensor(
            SensorRecord(
                id: "live-1",
                homeName: "Home",
                roomName: "Office",
                accessoryName: #"Cayla's "Sensor""#,
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
        try store.upsertSensor(
            SensorRecord(
                id: "blocked-1",
                homeName: "Home",
                roomName: "Office",
                accessoryName: "Blocked",
                serviceName: "Temp",
                characteristicType: "HMCharacteristicTypeCurrentTemperature",
                metricName: "homekit_temperature_celsius",
                unit: "celsius",
                isHidden: false,
                isBlocked: true,
                autoDiscovered: true,
                lastValue: nil,
                lastUpdated: nil
            )
        )
        try store.insertSample(sensorID: "live-1", timestamp: Date(), value: 21.25)
        try store.insertSample(sensorID: "blocked-1", timestamp: Date(), value: 99)

        let text = try PrometheusExporter.renderMetrics(store: store)
        XCTAssertTrue(text.contains("homekit_temperature_celsius{"))
        XCTAssertTrue(text.contains(#"accessory="Cayla's \"Sensor\"""#))
        XCTAssertTrue(text.contains("21.25"))
        XCTAssertFalse(text.contains("Blocked"))
    }
}
