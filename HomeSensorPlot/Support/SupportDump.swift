import Foundation

struct SupportDumpSensor: Equatable {
    var id: String
    var homeName: String
    var roomName: String
    var accessoryName: String
    var serviceName: String
    var characteristicType: String
    var metricName: String
    var unit: String
    var isHidden: Bool
    var isBlocked: Bool
    var lastValue: Double?
    var lastUpdated: Date?
}

struct SupportDumpInput: Equatable {
    var generatedAt: Date
    var bundleID: String
    var appVersion: String
    var buildNumber: String
    var osVersion: String
    var channel: String
    var databaseFileName: String
    var legacyCopiedTo: [String]
    var homeKitAuthorization: String
    var homeCount: Int
    var accessoryCount: Int
    var candidateCount: Int
    var collectorStatus: String
    var continuity: String
    var sensorCount: Int
    var sampleCount: Int
    var sensors: [SupportDumpSensor]
}

enum SupportDump {
    static func json(_ input: SupportDumpInput) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let payload = Payload(input)
        let data = (try? encoder.encode(payload)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private struct Payload: Encodable {
        var generatedAt: Date
        var bundleID: String
        var appVersion: String
        var buildNumber: String
        var osVersion: String
        var channel: String
        var databaseFileName: String
        var legacyCopiedTo: [String]
        var homeKitAuthorization: String
        var homeCount: Int
        var accessoryCount: Int
        var candidateCount: Int
        var collectorStatus: String
        var continuity: String
        var sensorCount: Int
        var sampleCount: Int
        var homeIDCounts: [String: Int]
        var sensors: [SensorPayload]

        init(_ input: SupportDumpInput) {
            generatedAt = input.generatedAt
            bundleID = input.bundleID
            appVersion = input.appVersion
            buildNumber = input.buildNumber
            osVersion = input.osVersion
            channel = input.channel
            databaseFileName = input.databaseFileName
            legacyCopiedTo = input.legacyCopiedTo
            homeKitAuthorization = input.homeKitAuthorization
            homeCount = input.homeCount
            accessoryCount = input.accessoryCount
            candidateCount = input.candidateCount
            collectorStatus = input.collectorStatus
            continuity = input.continuity
            sensorCount = input.sensorCount
            sampleCount = input.sampleCount
            var counts: [String: Int] = [:]
            for sensor in input.sensors {
                let homeID = SensorContinuity.homeID(from: sensor.id) ?? "unscoped"
                counts[homeID, default: 0] += 1
            }
            homeIDCounts = counts
            sensors = input.sensors.map(SensorPayload.init)
        }
    }

    private struct SensorPayload: Encodable {
        var id: String
        var homeName: String
        var roomName: String
        var accessoryName: String
        var serviceName: String
        var characteristicType: String
        var metricName: String
        var unit: String
        var isHidden: Bool
        var isBlocked: Bool
        var lastValue: Double?
        var lastUpdated: Date?

        init(_ sensor: SupportDumpSensor) {
            id = sensor.id
            homeName = sensor.homeName
            roomName = sensor.roomName
            accessoryName = sensor.accessoryName
            serviceName = sensor.serviceName
            characteristicType = sensor.characteristicType
            metricName = sensor.metricName
            unit = sensor.unit
            isHidden = sensor.isHidden
            isBlocked = sensor.isBlocked
            lastValue = sensor.lastValue
            lastUpdated = sensor.lastUpdated
        }
    }
}
