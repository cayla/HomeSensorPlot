import XCTest
@testable import HomeSensorPlot

final class SensorContinuityTests: XCTestCase {
    func testExactHomeReplacementRebinds() {
        let oldHome = "3054F2B3-13FD-5A1C-A7B6-DA0085477202"
        let newHome = "695B006C-EFDD-5CEE-AC57-4B210AFA8A55"
        let stored = [
            sensor(home: oldHome, accessory: "Hue", service: "Temperature", characteristic: "temp"),
            sensor(home: oldHome, accessory: "Hue", service: "Battery", characteristic: "battery"),
        ]
        let discovered = [
            sensor(home: newHome, accessory: "Hue", service: "Battery", characteristic: "battery"),
            sensor(home: newHome, accessory: "Hue", service: "Temperature", characteristic: "temp"),
        ]

        guard case .rebound(let pairs, let retired, let replacement) = SensorContinuity.decide(
            stored: stored,
            discovered: discovered
        ) else {
            return XCTFail("expected rebound")
        }
        XCTAssertEqual(retired, oldHome)
        XCTAssertEqual(replacement, newHome)
        XCTAssertEqual(pairs.count, 2)
        XCTAssertEqual(pairs.map(\.existing.serviceName), ["Battery", "Temperature"])
        XCTAssertTrue(pairs.allSatisfy { $0.discovered.id.hasPrefix(newHome) })
    }

    func testDistinctServicesStaySeparate() {
        let oldHome = "OLDHOME"
        let newHome = "NEWHOME"
        let stored = [
            sensor(home: oldHome, accessory: "Bedroom Ecobee Sensor", service: "Temperature", characteristic: "battery-low"),
            sensor(home: oldHome, accessory: "Bedroom Ecobee Sensor", service: "Occupancy", characteristic: "battery-low"),
        ]
        let discovered = stored.map { record in
            var copy = record
            copy.id = record.id.replacingOccurrences(of: oldHome, with: newHome)
            return copy
        }
        guard case .rebound(let pairs, _, _) = SensorContinuity.decide(stored: stored, discovered: discovered) else {
            return XCTFail("expected rebound")
        }
        XCTAssertEqual(Set(pairs.map(\.existing.serviceName)), ["Temperature", "Occupancy"])
    }

    func testDuplicateIdentityRefuses() {
        let stored = [
            sensor(home: "OLD", accessory: "Ecobee", service: "Battery", characteristic: "battery-low", tag: "a"),
            sensor(home: "OLD", accessory: "Ecobee", service: "Battery", characteristic: "battery-low", tag: "b"),
        ]
        let discovered = [
            sensor(home: "NEW", accessory: "Ecobee", service: "Battery", characteristic: "battery-low", tag: "c"),
            sensor(home: "NEW", accessory: "Ecobee", service: "Battery", characteristic: "battery-low", tag: "d"),
        ]
        guard case .refused(let reason) = SensorContinuity.decide(stored: stored, discovered: discovered) else {
            return XCTFail("expected refusal")
        }
        XCTAssertTrue(reason.contains("duplicate"))
    }

    func testExtraSensorRefuses() {
        let stored = [sensor(home: "OLD", accessory: "Hue", service: "Temperature", characteristic: "temp")]
        let discovered = [
            sensor(home: "NEW", accessory: "Hue", service: "Temperature", characteristic: "temp"),
            sensor(home: "NEW", accessory: "Other", service: "Temperature", characteristic: "temp"),
        ]
        guard case .refused(let reason) = SensorContinuity.decide(stored: stored, discovered: discovered) else {
            return XCTFail("expected refusal")
        }
        XCTAssertTrue(reason.contains("1:1"))
    }

    func testSecondLiveHomeIsLeftAlone() {
        let stored = [sensor(home: "KEEP", accessory: "Hue", service: "Temperature", characteristic: "temp")]
        let discovered = stored + [sensor(home: "ADDED", accessory: "Hue", service: "Temperature", characteristic: "temp")]
        XCTAssertEqual(SensorContinuity.decide(stored: stored, discovered: discovered), .notNeeded)
    }

    func testEmptyDiscoveryDoesNotRetire() {
        let stored = [sensor(home: "OLD", accessory: "Hue", service: "Temperature", characteristic: "temp")]
        XCTAssertEqual(SensorContinuity.decide(stored: stored, discovered: []), .notNeeded)
    }

    func testTwoReplacedHomesAreRefused() {
        let stored = [
            sensor(home: "A", accessory: "One", service: "Temperature", characteristic: "temp"),
            sensor(home: "B", accessory: "Two", service: "Temperature", characteristic: "temp"),
        ]
        let discovered = [
            sensor(home: "C", accessory: "One", service: "Temperature", characteristic: "temp"),
        ]
        guard case .refused = SensorContinuity.decide(stored: stored, discovered: discovered) else {
            return XCTFail("expected refusal")
        }
    }

    private func sensor(
        home: String,
        accessory: String,
        service: String,
        characteristic: String,
        tag: String = "only"
    ) -> SensorRecord {
        SensorRecord(
            id: "\(home):ACC:SVC-\(service)-\(tag):CHR-\(characteristic)",
            homeName: "Quirklandia",
            roomName: "Basement Storage",
            accessoryName: accessory,
            serviceName: service,
            characteristicType: characteristic,
            metricName: "homekit_temperature_celsius",
            unit: "celsius",
            isHidden: false,
            isBlocked: false,
            autoDiscovered: true,
            lastValue: nil,
            lastUpdated: nil
        )
    }
}
