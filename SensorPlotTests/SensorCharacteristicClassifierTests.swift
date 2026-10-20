import HomeKit
import XCTest
@testable import SensorPlot

final class SensorCharacteristicClassifierTests: XCTestCase {
    func testKnownTemperature() {
        let result = SensorCharacteristicClassifier.classify(
            characteristicType: HMCharacteristicTypeCurrentTemperature
        )
        XCTAssertEqual(result?.metricName, "homekit_temperature_celsius")
        XCTAssertEqual(result?.unit, "celsius")
    }

    func testKnownContactAndBattery() {
        XCTAssertEqual(
            SensorCharacteristicClassifier.classify(
                characteristicType: HMCharacteristicTypeContactState
            )?.metricName,
            "homekit_contact_open"
        )
        XCTAssertEqual(
            SensorCharacteristicClassifier.classify(
                characteristicType: HMCharacteristicTypeBatteryLevel
            )?.metricName,
            "homekit_battery_percent"
        )
        XCTAssertEqual(
            SensorCharacteristicClassifier.classify(
                characteristicType: HMCharacteristicTypeFilterLifeLevel
            )?.metricName,
            "homekit_filter_life_percent"
        )
    }

    func testUnknownTypeReturnsNil() {
        XCTAssertNil(SensorCharacteristicClassifier.classify(characteristicType: "not-a-real-type"))
    }
}
