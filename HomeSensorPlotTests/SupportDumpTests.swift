import XCTest
@testable import HomeSensorPlot

final class SupportDumpTests: XCTestCase {
    func testDumpListsSensorsWithoutSampleHistory() throws {
        let sensor = SupportDumpSensor(
            id: "HOME:ACC:SVC:CHR",
            homeName: "Quirklandia",
            roomName: "Kitchen",
            accessoryName: "Hue",
            serviceName: "Temperature",
            characteristicType: "HMCharacteristicTypeCurrentTemperature",
            metricName: "homekit_temperature_celsius",
            unit: "celsius",
            isHidden: false,
            isBlocked: false,
            lastValue: 21.5,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let text = SupportDump.json(
            SupportDumpInput(
                generatedAt: Date(timeIntervalSince1970: 1_700_000_100),
                bundleID: "com.cayla.HomeSensorPlot",
                appVersion: "0.1.0",
                buildNumber: "9",
                osVersion: "test",
                channel: "testflight",
                databaseFileName: "homesensorplot-testflight.sqlite",
                legacyCopiedTo: ["testflight"],
                homeKitAuthorization: "authorized",
                homeCount: 1,
                accessoryCount: 30,
                candidateCount: 103,
                collectorStatus: "Collecting 103 sensors",
                continuity: "not needed",
                sensorCount: 1,
                sampleCount: 40,
                sensors: [sensor]
            )
        )
        let data = Data(text.utf8)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["channel"] as? String, "testflight")
        XCTAssertEqual(object["databaseFileName"] as? String, "homesensorplot-testflight.sqlite")
        XCTAssertEqual(object["sampleCount"] as? Int, 40)
        XCTAssertNil(object["samples"])
        let sensors = try XCTUnwrap(object["sensors"] as? [[String: Any]])
        XCTAssertEqual(sensors.first?["id"] as? String, sensor.id)
        let homes = try XCTUnwrap(object["homeIDCounts"] as? [String: Int])
        XCTAssertEqual(homes["HOME"], 1)
    }
}
