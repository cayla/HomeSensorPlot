import Foundation

struct SensorRecord: Identifiable, Hashable, Sendable {
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
    var autoDiscovered: Bool
    var lastValue: Double?
    var lastUpdated: Date?

    var isMock: Bool { id.hasPrefix("mock:") }

    var displayName: String {
        "\(accessoryName) · \(friendlyCharacteristic)"
    }

    var friendlyCharacteristic: String {
        characteristicType
            .replacingOccurrences(of: "HMCharacteristicType", with: "")
            .replacingOccurrences(of: "CharacteristicType", with: "")
    }

    var locationLabel: String {
        let room = roomName.isEmpty ? "No Room" : roomName
        return "\(homeName) / \(room)"
    }
}

struct SamplePoint: Identifiable, Hashable, Sendable {
    var id: Int64
    var sensorID: String
    var timestamp: Date
    var value: Double
}

struct LatestSample: Hashable, Sendable {
    var sensorID: String
    var metricName: String
    var value: Double
    var timestamp: Date
    var homeName: String
    var roomName: String
    var accessoryName: String
    var characteristicType: String
    var unit: String
}

struct HomeKitSnapshot: Equatable, Sendable {
    var authorizationLabel: String
    var homeCount: Int
    var accessoryCount: Int
    var candidateCount: Int
    var readableCount: Int
}

enum CollectorStatus: Equatable, Sendable {
    case starting
    case waitingForHomeKit
    case unauthorized
    /// Authorized (or homes visible) but nothing readable yet.
    case homeKitIdle(HomeKitSnapshot)
    case collecting(sensorCount: Int)
    case mockMode(sensorCount: Int)
    case error(String)

    var menuBarSymbol: String {
        switch self {
        case .starting, .waitingForHomeKit:
            return "waveform.path.ecg"
        case .unauthorized:
            return "lock.homekit"
        case .homeKitIdle:
            return "house.fill"
        case .collecting:
            return "sensor.tag.radiowaves.forward.fill"
        case .mockMode:
            return "chart.xyaxis.line"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    var shortLabel: String {
        switch self {
        case .starting:
            return "Starting…"
        case .waitingForHomeKit:
            return "Waiting for HomeKit"
        case .unauthorized:
            return "HomeKit access denied"
        case .homeKitIdle(let snap):
            if snap.homeCount == 0 {
                return "HomeKit OK · 0 homes"
            }
            if snap.candidateCount == 0 {
                return "HomeKit · \(snap.accessoryCount) accessories, 0 sensor chars"
            }
            if snap.readableCount == 0 {
                return "HomeKit · \(snap.candidateCount) sensors, read pending"
            }
            return "HomeKit · \(snap.readableCount) readable"
        case .collecting(let count):
            return "Collecting \(count) sensors"
        case .mockMode(let count):
            return "Mock data (\(count) sensors)"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}

enum TimeBox: String, CaseIterable, Identifiable, Sendable {
    case oneHour = "1h"
    case twentyFourHours = "24h"
    case sevenDays = "7d"
    case thirtyDays = "30d"
    case custom = "Custom"

    var id: String { rawValue }

    func startDate(relativeTo now: Date = .now, customStart: Date? = nil) -> Date {
        switch self {
        case .oneHour:
            return now.addingTimeInterval(-3600)
        case .twentyFourHours:
            return now.addingTimeInterval(-86_400)
        case .sevenDays:
            return now.addingTimeInterval(-7 * 86_400)
        case .thirtyDays:
            return now.addingTimeInterval(-30 * 86_400)
        case .custom:
            return customStart ?? now.addingTimeInterval(-86_400)
        }
    }
}
