import Foundation
import SwiftUI

/// High-level sensor buckets for the Charts landing grid.
enum SensorCategory: String, CaseIterable, Identifiable, Hashable, Sendable {
    case temperature
    case humidity
    case light
    case contact
    case lock
    case motion
    case occupancy
    case air
    case filterLife
    case battery
    case leak
    case smoke

    var id: String { rawValue }

    var title: String {
        switch self {
        case .temperature: return "Temperature"
        case .humidity: return "Humidity"
        case .light: return "Light"
        case .contact: return "Open / Closed"
        case .lock: return "Locked / Unlocked"
        case .motion: return "Motion"
        case .occupancy: return "Occupancy"
        case .air: return "Air Quality"
        case .filterLife: return "Filter life"
        case .battery: return "Battery"
        case .leak: return "Leak"
        case .smoke: return "Smoke"
        }
    }

    var systemImage: String {
        switch self {
        case .temperature: return "thermometer"
        case .humidity: return "humidity"
        case .light: return "sun.max"
        case .contact: return "door.left.hand.open"
        case .lock: return "lock.fill"
        case .motion: return "figure.walk"
        case .occupancy: return "person.fill"
        case .air: return "wind"
        case .filterLife: return "air.purifier"
        case .battery: return "battery.100"
        case .leak: return "drop.fill"
        case .smoke: return "flame"
        }
    }

    /// Categories whose values are binary/enum states (natural-language display).
    var isStateCategory: Bool {
        switch self {
        case .contact, .lock, .motion, .occupancy, .leak, .smoke:
            return true
        default:
            return false
        }
    }

    func unitHint(temperatureUnit: TemperatureUnit = .celsius) -> String {
        switch self {
        case .temperature: return temperatureUnit.shortSymbol
        case .humidity, .battery, .filterLife: return "%"
        case .light: return "lux"
        case .contact, .lock, .motion, .occupancy, .leak, .smoke: return "state"
        case .air: return "µg/m³ · ppm"
        }
    }

    /// Metrics charted in this category (excludes flat enums / bool flags that drown useful series).
    var metricNames: Set<String> {
        switch self {
        case .temperature:
            return ["homekit_temperature_celsius"]
        case .humidity:
            return ["homekit_humidity_percent"]
        case .light:
            return ["homekit_light_level_lux"]
        case .contact:
            return ["homekit_contact_open"]
        case .lock:
            return ["homekit_lock_secured"]
        case .motion:
            return ["homekit_motion_detected"]
        case .occupancy:
            return ["homekit_occupancy_detected"]
        case .air:
            // Densities / ppm only. Filter remaining life is a separate category (different scale).
            // Skip homekit_air_quality enum and co*_detected bools.
            return [
                "homekit_co2_ppm",
                "homekit_co_ppm",
                "homekit_no2_density",
                "homekit_ozone_density",
                "homekit_pm25_density",
                "homekit_pm10_density",
                "homekit_so2_density",
                "homekit_voc_density",
            ]
        case .filterLife:
            // HAP FilterLifeLevel — remaining filter life, not particulate density.
            return ["homekit_filter_life_percent"]
        case .battery:
            // Skip battery_low bool — percent alone charts cleanly.
            return ["homekit_battery_percent"]
        case .leak:
            return ["homekit_leak_detected"]
        case .smoke:
            return ["homekit_smoke_detected"]
        }
    }

    /// Collected and exported, left off the chart grid on purpose.
    /// Air-quality enum, battery-low, tamper, and the CO/CO2 detected flags.
    static let inventoryOnlyMetricNames: Set<String> = [
        "homekit_air_quality",
        "homekit_battery_low",
        "homekit_tampered",
        "homekit_co2_detected",
        "homekit_co_detected",
    ]

    static func category(forMetric metricName: String) -> SensorCategory? {
        allCases.first { $0.metricNames.contains(metricName) }
    }

    static func categoriesPresent(in sensors: [SensorRecord]) -> [SensorCategory] {
        let visible = sensors.filter { !$0.isHidden && !$0.isBlocked }
        return allCases.filter { category in
            visible.contains { category.metricNames.contains($0.metricName) }
        }
    }

    func sensors(from all: [SensorRecord]) -> [SensorRecord] {
        all.filter { !$0.isHidden && !$0.isBlocked && metricNames.contains($0.metricName) }
            .sorted {
                if $0.roomName == $1.roomName {
                    return $0.accessoryName < $1.accessoryName
                }
                return $0.roomName < $1.roomName
            }
    }
}

struct ChartSeriesPoint: Identifiable, Hashable, Sendable {
    var id: String
    var sensorID: String
    var label: String
    var timestamp: Date
    var value: Double

    init(sensorID: String, label: String, timestamp: Date, value: Double) {
        self.id = "\(sensorID)|\(timestamp.timeIntervalSince1970)"
        self.sensorID = sensorID
        self.label = label
        self.timestamp = timestamp
        self.value = value
    }
}
