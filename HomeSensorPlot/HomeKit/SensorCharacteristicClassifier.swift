import Foundation
import HomeKit

struct ClassifiedCharacteristic: Sendable {
    var metricName: String
    var unit: String
    var autoDiscovered: Bool
}

enum SensorCharacteristicClassifier {
    static func classify(characteristicType: String) -> ClassifiedCharacteristic? {
        switch characteristicType {
        case HMCharacteristicTypeCurrentTemperature:
            return .init(metricName: "homekit_temperature_celsius", unit: "celsius", autoDiscovered: true)
        case HMCharacteristicTypeCurrentRelativeHumidity:
            return .init(metricName: "homekit_humidity_percent", unit: "percent", autoDiscovered: true)
        case HMCharacteristicTypeCurrentLightLevel:
            return .init(metricName: "homekit_light_level_lux", unit: "lux", autoDiscovered: true)
        case HMCharacteristicTypeContactState:
            return .init(metricName: "homekit_contact_open", unit: "bool", autoDiscovered: true)
        case HMCharacteristicTypeCurrentLockMechanismState:
            // HomeKit: 0 unsecured, 1 secured, 2 jammed, 3 unknown.
            return .init(metricName: "homekit_lock_secured", unit: "enum", autoDiscovered: true)
        case HMCharacteristicTypeMotionDetected:
            return .init(metricName: "homekit_motion_detected", unit: "bool", autoDiscovered: true)
        case HMCharacteristicTypeOccupancyDetected:
            return .init(metricName: "homekit_occupancy_detected", unit: "bool", autoDiscovered: true)
        case HMCharacteristicTypeAirQuality:
            // HAP Air Quality: 0 Unknown … 5 Poor. Flat “Excellent” (1) lines clutter charts —
            // still collected for /metrics + Inventory; excluded from Air chart metrics.
            return .init(metricName: "homekit_air_quality", unit: "enum", autoDiscovered: true)
        case HMCharacteristicTypeFilterLifeLevel:
            return .init(metricName: "homekit_filter_life_percent", unit: "percent", autoDiscovered: true)
        case HMCharacteristicTypeCarbonDioxideLevel:
            return .init(metricName: "homekit_co2_ppm", unit: "ppm", autoDiscovered: true)
        case HMCharacteristicTypeCarbonMonoxideLevel:
            return .init(metricName: "homekit_co_ppm", unit: "ppm", autoDiscovered: true)
        case HMCharacteristicTypeNitrogenDioxideDensity:
            return .init(metricName: "homekit_no2_density", unit: "ug_m3", autoDiscovered: true)
        case HMCharacteristicTypeOzoneDensity:
            return .init(metricName: "homekit_ozone_density", unit: "ug_m3", autoDiscovered: true)
        case HMCharacteristicTypePM2_5Density:
            return .init(metricName: "homekit_pm25_density", unit: "ug_m3", autoDiscovered: true)
        case HMCharacteristicTypePM10Density:
            return .init(metricName: "homekit_pm10_density", unit: "ug_m3", autoDiscovered: true)
        case HMCharacteristicTypeSulphurDioxideDensity:
            return .init(metricName: "homekit_so2_density", unit: "ug_m3", autoDiscovered: true)
        case HMCharacteristicTypeVolatileOrganicCompoundDensity:
            return .init(metricName: "homekit_voc_density", unit: "ug_m3", autoDiscovered: true)
        case HMCharacteristicTypeBatteryLevel:
            return .init(metricName: "homekit_battery_percent", unit: "percent", autoDiscovered: true)
        case HMCharacteristicTypeStatusLowBattery:
            return .init(metricName: "homekit_battery_low", unit: "bool", autoDiscovered: true)
        case HMCharacteristicTypeStatusTampered:
            return .init(metricName: "homekit_tampered", unit: "bool", autoDiscovered: true)
        case HMCharacteristicTypeLeakDetected:
            return .init(metricName: "homekit_leak_detected", unit: "bool", autoDiscovered: true)
        case HMCharacteristicTypeSmokeDetected:
            return .init(metricName: "homekit_smoke_detected", unit: "bool", autoDiscovered: true)
        case HMCharacteristicTypeCarbonDioxideDetected:
            return .init(metricName: "homekit_co2_detected", unit: "bool", autoDiscovered: true)
        case HMCharacteristicTypeCarbonMonoxideDetected:
            return .init(metricName: "homekit_co_detected", unit: "bool", autoDiscovered: true)
        default:
            return nil
        }
    }

    /// Known types always; unknown numeric/bool HAP chars only when `includeUnknown` is true
    /// (otherwise we get hundreds of camera/lock `homekit_auto_*` gauges).
    static func classify(
        characteristic: HMCharacteristic,
        includeUnknown: Bool
    ) -> ClassifiedCharacteristic? {
        if let known = classify(characteristicType: characteristic.characteristicType) {
            return known
        }
        guard includeUnknown else { return nil }
        return classifyUnknown(characteristic)
    }

    static func classifyUnknown(_ characteristic: HMCharacteristic) -> ClassifiedCharacteristic? {
        let metadata = characteristic.metadata
        let format = metadata?.format
        let isNumeric =
            format == HMCharacteristicMetadataFormatFloat
            || format == HMCharacteristicMetadataFormatInt
            || format == HMCharacteristicMetadataFormatUInt8
            || format == HMCharacteristicMetadataFormatUInt16
            || format == HMCharacteristicMetadataFormatUInt32
            || format == HMCharacteristicMetadataFormatUInt64
        let isBool = format == HMCharacteristicMetadataFormatBool

        guard isNumeric || isBool else { return nil }

        let type = characteristic.characteristicType
        let actuators: Set<String> = [
            HMCharacteristicTypeTargetTemperature,
            HMCharacteristicTypeTargetRelativeHumidity,
            HMCharacteristicTypeTargetDoorState,
            HMCharacteristicTypeTargetHeatingCooling,
            HMCharacteristicTypeTargetLockMechanismState,
            HMCharacteristicTypeTargetSecuritySystemState,
            HMCharacteristicTypeBrightness,
            HMCharacteristicTypeHue,
            HMCharacteristicTypeSaturation,
            HMCharacteristicTypeColorTemperature,
            HMCharacteristicTypePowerState,
        ]
        if actuators.contains(type) { return nil }

        let slug = type
            .replacingOccurrences(of: "HMCharacteristicType", with: "")
            .replacingOccurrences(of: "CharacteristicType", with: "")
            .replacingOccurrences(of: "[^a-zA-Z0-9]+", with: "_", options: .regularExpression)
            .lowercased()
        return ClassifiedCharacteristic(
            metricName: "homekit_auto_\(slug)",
            unit: isBool ? "bool" : (metadata?.units ?? "value"),
            autoDiscovered: true
        )
    }

    static func doubleValue(from characteristic: HMCharacteristic) -> Double? {
        guard let value = characteristic.value else { return nil }
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let bool = value as? Bool {
            return bool ? 1 : 0
        }
        return nil
    }
}
