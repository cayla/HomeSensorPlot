import Foundation
import HomeKit

struct ClassifiedCharacteristic: Sendable {
    var metricName: String
    var unit: String
    var autoDiscovered: Bool
}

struct KnownHomeKitMetric: Equatable {
    var characteristicType: String
    var metricName: String
    var unit: String
}

enum SensorCharacteristicClassifier {
    /// Lock state is 0 unsecured, 1 secured, 2 jammed, 3 unknown.
    /// Air quality (0…5) is inventory-only: a flat “Excellent” line clutters the chart.
    static let knownMetrics: [KnownHomeKitMetric] = [
        .init(characteristicType: HMCharacteristicTypeCurrentTemperature, metricName: "homekit_temperature_celsius", unit: "celsius"),
        .init(characteristicType: HMCharacteristicTypeCurrentRelativeHumidity, metricName: "homekit_humidity_percent", unit: "percent"),
        .init(characteristicType: HMCharacteristicTypeCurrentLightLevel, metricName: "homekit_light_level_lux", unit: "lux"),
        .init(characteristicType: HMCharacteristicTypeContactState, metricName: "homekit_contact_open", unit: "bool"),
        .init(characteristicType: HMCharacteristicTypeCurrentLockMechanismState, metricName: "homekit_lock_secured", unit: "enum"),
        .init(characteristicType: HMCharacteristicTypeMotionDetected, metricName: "homekit_motion_detected", unit: "bool"),
        .init(characteristicType: HMCharacteristicTypeOccupancyDetected, metricName: "homekit_occupancy_detected", unit: "bool"),
        .init(characteristicType: HMCharacteristicTypeAirQuality, metricName: "homekit_air_quality", unit: "enum"),
        .init(characteristicType: HMCharacteristicTypeFilterLifeLevel, metricName: "homekit_filter_life_percent", unit: "percent"),
        .init(characteristicType: HMCharacteristicTypeCarbonDioxideLevel, metricName: "homekit_co2_ppm", unit: "ppm"),
        .init(characteristicType: HMCharacteristicTypeCarbonMonoxideLevel, metricName: "homekit_co_ppm", unit: "ppm"),
        .init(characteristicType: HMCharacteristicTypeNitrogenDioxideDensity, metricName: "homekit_no2_density", unit: "ug_m3"),
        .init(characteristicType: HMCharacteristicTypeOzoneDensity, metricName: "homekit_ozone_density", unit: "ug_m3"),
        .init(characteristicType: HMCharacteristicTypePM2_5Density, metricName: "homekit_pm25_density", unit: "ug_m3"),
        .init(characteristicType: HMCharacteristicTypePM10Density, metricName: "homekit_pm10_density", unit: "ug_m3"),
        .init(characteristicType: HMCharacteristicTypeSulphurDioxideDensity, metricName: "homekit_so2_density", unit: "ug_m3"),
        .init(characteristicType: HMCharacteristicTypeVolatileOrganicCompoundDensity, metricName: "homekit_voc_density", unit: "ug_m3"),
        .init(characteristicType: HMCharacteristicTypeBatteryLevel, metricName: "homekit_battery_percent", unit: "percent"),
        .init(characteristicType: HMCharacteristicTypeStatusLowBattery, metricName: "homekit_battery_low", unit: "bool"),
        .init(characteristicType: HMCharacteristicTypeStatusTampered, metricName: "homekit_tampered", unit: "bool"),
        .init(characteristicType: HMCharacteristicTypeLeakDetected, metricName: "homekit_leak_detected", unit: "bool"),
        .init(characteristicType: HMCharacteristicTypeSmokeDetected, metricName: "homekit_smoke_detected", unit: "bool"),
        .init(characteristicType: HMCharacteristicTypeCarbonDioxideDetected, metricName: "homekit_co2_detected", unit: "bool"),
        .init(characteristicType: HMCharacteristicTypeCarbonMonoxideDetected, metricName: "homekit_co_detected", unit: "bool"),
    ]

    private static let knownByType: [String: KnownHomeKitMetric] = {
        Dictionary(uniqueKeysWithValues: knownMetrics.map { ($0.characteristicType, $0) })
    }()

    static func classify(characteristicType: String) -> ClassifiedCharacteristic? {
        guard let known = knownByType[characteristicType] else { return nil }
        return .init(metricName: known.metricName, unit: known.unit, autoDiscovered: true)
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
