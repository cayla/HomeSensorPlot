import XCTest
@testable import SensorPlot

final class SensorCategoryTests: XCTestCase {
    func testMetricNamesAreUniqueAcrossCategories() {
        var seen: [String: SensorCategory] = [:]
        for category in SensorCategory.allCases {
            for metric in category.metricNames {
                if let owner = seen[metric] {
                    XCTFail("\(metric) claimed by both \(owner) and \(category)")
                }
                seen[metric] = category
            }
        }
    }

    func testCategoryForMetric() {
        XCTAssertEqual(SensorCategory.category(forMetric: "homekit_temperature_celsius"), .temperature)
        XCTAssertEqual(SensorCategory.category(forMetric: "homekit_filter_life_percent"), .filterLife)
        XCTAssertEqual(SensorCategory.category(forMetric: "homekit_battery_percent"), .battery)
        XCTAssertNil(SensorCategory.category(forMetric: "homekit_air_quality"))
        XCTAssertNil(SensorCategory.category(forMetric: "homekit_auto_whatever"))
    }

    func testSensorsFiltersHiddenBlockedAndSorts() {
        let sensors = [
            makeSensor(id: "b", room: "Kitchen", accessory: "B", metric: "homekit_temperature_celsius"),
            makeSensor(id: "a", room: "Kitchen", accessory: "A", metric: "homekit_temperature_celsius"),
            makeSensor(id: "h", room: "Hall", accessory: "H", metric: "homekit_temperature_celsius", hidden: true),
            makeSensor(id: "x", room: "Hall", accessory: "X", metric: "homekit_temperature_celsius", blocked: true),
            makeSensor(id: "hum", room: "Kitchen", accessory: "Hum", metric: "homekit_humidity_percent"),
        ]

        let temps = SensorCategory.temperature.sensors(from: sensors)
        XCTAssertEqual(temps.map(\.id), ["a", "b"])
    }

    func testCategoriesPresentSkipsEmpty() {
        let sensors = [
            makeSensor(id: "t", room: "R", accessory: "T", metric: "homekit_temperature_celsius"),
            makeSensor(id: "b", room: "R", accessory: "B", metric: "homekit_battery_percent", hidden: true),
        ]
        XCTAssertEqual(SensorCategory.categoriesPresent(in: sensors), [.temperature])
    }

    func testUnitHintRespectsTemperatureSetting() {
        XCTAssertEqual(SensorCategory.temperature.unitHint(temperatureUnit: .fahrenheit), "°F")
        XCTAssertEqual(SensorCategory.battery.unitHint(), "%")
        XCTAssertEqual(SensorCategory.contact.unitHint(), "state")
    }

    private func makeSensor(
        id: String,
        room: String,
        accessory: String,
        metric: String,
        hidden: Bool = false,
        blocked: Bool = false
    ) -> SensorRecord {
        SensorRecord(
            id: id,
            homeName: "Home",
            roomName: room,
            accessoryName: accessory,
            serviceName: "Service",
            characteristicType: "HMCharacteristicTypeCurrentTemperature",
            metricName: metric,
            unit: "celsius",
            isHidden: hidden,
            isBlocked: blocked,
            autoDiscovered: true,
            lastValue: nil,
            lastUpdated: nil
        )
    }
}
