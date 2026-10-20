import Foundation

enum MockSensorSeeder {
    static func seedIfNeeded(store: SampleStore) throws {
        let existing = try store.allSensors()
        if existing.contains(where: { $0.id.hasPrefix("mock:") }) {
            try refreshValues(store: store)
            return
        }

        let now = Date()
        let fixtures: [(SensorRecord, Double)] = [
            (
                SensorRecord(
                    id: "mock:temp-office",
                    homeName: "Demo Home",
                    roomName: "Office",
                    accessoryName: "Office Eve Degree",
                    serviceName: "Temperature Sensor",
                    characteristicType: "CurrentTemperature",
                    metricName: "homekit_temperature_celsius",
                    unit: "celsius",
                    isHidden: false,
                    isBlocked: false,
                    autoDiscovered: true,
                    lastValue: nil,
                    lastUpdated: nil
                ),
                21.4
            ),
            (
                SensorRecord(
                    id: "mock:humidity-office",
                    homeName: "Demo Home",
                    roomName: "Office",
                    accessoryName: "Office Eve Degree",
                    serviceName: "Humidity Sensor",
                    characteristicType: "CurrentRelativeHumidity",
                    metricName: "homekit_humidity_percent",
                    unit: "percent",
                    isHidden: false,
                    isBlocked: false,
                    autoDiscovered: true,
                    lastValue: nil,
                    lastUpdated: nil
                ),
                43
            ),
            (
                SensorRecord(
                    id: "mock:light-kitchen",
                    homeName: "Demo Home",
                    roomName: "Kitchen",
                    accessoryName: "Kitchen Lux",
                    serviceName: "Light Sensor",
                    characteristicType: "LightLevelSensor",
                    metricName: "homekit_light_level_lux",
                    unit: "lux",
                    isHidden: false,
                    isBlocked: false,
                    autoDiscovered: true,
                    lastValue: nil,
                    lastUpdated: nil
                ),
                280
            ),
            (
                SensorRecord(
                    id: "mock:contact-front",
                    homeName: "Demo Home",
                    roomName: "Entry",
                    accessoryName: "Front Door",
                    serviceName: "Contact Sensor",
                    characteristicType: "ContactSensorState",
                    metricName: "homekit_contact_open",
                    unit: "bool",
                    isHidden: false,
                    isBlocked: false,
                    autoDiscovered: true,
                    lastValue: nil,
                    lastUpdated: nil
                ),
                0
            ),
            (
                SensorRecord(
                    id: "mock:motion-hall",
                    homeName: "Demo Home",
                    roomName: "Hall",
                    accessoryName: "Hall Motion",
                    serviceName: "Motion Sensor",
                    characteristicType: "MotionDetected",
                    metricName: "homekit_motion_detected",
                    unit: "bool",
                    isHidden: false,
                    isBlocked: false,
                    autoDiscovered: true,
                    lastValue: nil,
                    lastUpdated: nil
                ),
                1
            ),
            (
                SensorRecord(
                    id: "mock:aqi-living",
                    homeName: "Demo Home",
                    roomName: "Living Room",
                    accessoryName: "Living Air Quality",
                    serviceName: "Air Quality Sensor",
                    characteristicType: "AirQuality",
                    metricName: "homekit_air_quality",
                    unit: "enum",
                    isHidden: false,
                    isBlocked: false,
                    autoDiscovered: true,
                    lastValue: nil,
                    lastUpdated: nil
                ),
                2
            ),
        ]

        for (sensor, base) in fixtures {
            try store.upsertSensor(sensor)
            try writeHistory(store: store, sensorID: sensor.id, base: base, end: now)
        }
    }

    static func refreshValues(store: SampleStore) throws {
        let sensors = try store.allSensors().filter { $0.id.hasPrefix("mock:") && !$0.isBlocked }
        let now = Date()
        var batch: [(sensorID: String, timestamp: Date, value: Double)] = []
        for sensor in sensors {
            let base = sensor.lastValue ?? 20
            let jitter: Double
            switch sensor.unit {
            case "bool":
                jitter = Double.random(in: 0...1) > 0.85 ? (base == 0 ? 1 : 0) : base
            case "enum":
                jitter = max(1, min(5, (base + Double.random(in: -0.4...0.4)).rounded()))
            default:
                jitter = base + Double.random(in: -0.8...0.8)
            }
            batch.append((sensor.id, now, jitter))
        }
        try store.insertSamples(batch)
    }

    private static func writeHistory(store: SampleStore, sensorID: String, base: Double, end: Date) throws {
        var batch: [(sensorID: String, timestamp: Date, value: Double)] = []
        // 48 hours of 10-minute points for charts to look alive.
        for minutesAgo in stride(from: 48 * 60, through: 0, by: -10) {
            let ts = end.addingTimeInterval(-Double(minutesAgo) * 60)
            let wave = sin(Double(minutesAgo) / 180.0) * (base * 0.03)
            let noise = Double.random(in: -0.2...0.2)
            let value: Double
            if sensorID.contains("contact") || sensorID.contains("motion") {
                value = (minutesAgo / 40) % 7 == 0 ? 1 : 0
            } else {
                value = base + wave + noise
            }
            batch.append((sensorID, ts, value))
        }
        try store.insertSamples(batch)
    }
}
