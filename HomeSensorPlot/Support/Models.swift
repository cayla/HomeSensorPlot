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

/// Logical range for a preset. Calendar windows still end on the upcoming boundary.
struct ChartTimeWindow: Equatable, Sendable {
    var start: Date
    var end: Date

    /// Stored samples stop at now.
    func sampleEnd(now: Date) -> Date {
        min(now, end)
    }

    /// Axis domain. The right edge is now, so a short calendar window is not a strip of data beside an empty future.
    func plottedDomain(now: Date = .now) -> ClosedRange<Date> {
        let visibleEnd = max(sampleEnd(now: now), start.addingTimeInterval(1))
        return start...visibleEnd
    }
}

enum TimeBox: String, CaseIterable, Identifiable, Sendable {
    case lastHour = "Last hour"
    case thisHour = "This hour"
    case lastDay = "Last 24 hours"
    case today = "Today"
    case lastWeek = "Last 7 days"
    case thisWeek = "This week"
    case lastMonth = "Last 30 days"
    case thisMonth = "This month"
    case custom = "Custom"

    var id: String { rawValue }

    /// Trailing cases end at `now`. Calendar cases are the local unit that contains `now`.
    func window(
        relativeTo now: Date = .now,
        calendar: Calendar = .current,
        customStart: Date? = nil
    ) -> ChartTimeWindow {
        switch self {
        case .lastHour:
            return trailing(now, seconds: 3600)
        case .thisHour:
            return calendarWindow(.hour, now: now, calendar: calendar) ?? trailing(now, seconds: 3600)
        case .lastDay:
            return trailing(now, seconds: 86_400)
        case .today:
            return calendarWindow(.day, now: now, calendar: calendar) ?? trailing(now, seconds: 86_400)
        case .lastWeek:
            return trailing(now, seconds: 7 * 86_400)
        case .thisWeek:
            return calendarWindow(.weekOfYear, now: now, calendar: calendar) ?? trailing(now, seconds: 7 * 86_400)
        case .lastMonth:
            return trailing(now, seconds: 30 * 86_400)
        case .thisMonth:
            return calendarWindow(.month, now: now, calendar: calendar) ?? trailing(now, seconds: 30 * 86_400)
        case .custom:
            let start = customStart ?? now.addingTimeInterval(-86_400)
            if start < now {
                return ChartTimeWindow(start: start, end: now)
            }
            return ChartTimeWindow(start: now, end: now.addingTimeInterval(60))
        }
    }

    private func trailing(_ now: Date, seconds: TimeInterval) -> ChartTimeWindow {
        ChartTimeWindow(start: now.addingTimeInterval(-seconds), end: now)
    }

    private func calendarWindow(
        _ component: Calendar.Component,
        now: Date,
        calendar: Calendar
    ) -> ChartTimeWindow? {
        guard let interval = calendar.dateInterval(of: component, for: now) else { return nil }
        return ChartTimeWindow(start: interval.start, end: interval.end)
    }
}
