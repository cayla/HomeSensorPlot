import Foundation

struct SensorContinuityPair: Equatable {
    var existing: SensorRecord
    var discovered: SensorRecord
}

enum SensorContinuityDecision: Equatable {
    case notNeeded
    case rebound(pairs: [SensorContinuityPair], retiredHomeID: String, replacementHomeID: String)
    case refused(String)

    var summary: String {
        switch self {
        case .notNeeded:
            return "not needed"
        case .rebound(let pairs, let retired, let replacement):
            return "rebound \(pairs.count) sensors from \(retired) to \(replacement)"
        case .refused(let reason):
            return "refused: \(reason)"
        }
    }
}

/// Whole-home identity repair. A new HomeKit client id is adopted only when one
/// stored home id is entirely absent, one discovered home id is entirely new, and
/// every sensor pairs 1:1 on home, room, accessory, service, and characteristic type.
enum SensorContinuity {
    struct MatchKey: Hashable {
        var homeName: String
        var roomName: String
        var accessoryName: String
        var serviceName: String
        var characteristicType: String

        init(_ sensor: SensorRecord) {
            homeName = sensor.homeName
            roomName = sensor.roomName
            accessoryName = sensor.accessoryName
            serviceName = sensor.serviceName
            characteristicType = sensor.characteristicType
        }
    }

    static func homeID(from sensorID: String) -> String? {
        let parts = sensorID.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 4, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        return String(parts[0])
    }

    static func decide(stored: [SensorRecord], discovered: [SensorRecord]) -> SensorContinuityDecision {
        let storedLive = stored.filter { !$0.isMock }
        let discoveredLive = discovered.filter { !$0.isMock }

        let storedByHome = Dictionary(grouping: storedLive.compactMap { sensor -> (String, SensorRecord)? in
            guard let homeID = homeID(from: sensor.id) else { return nil }
            return (homeID, sensor)
        }, by: \.0).mapValues { $0.map(\.1) }

        let discoveredByHome = Dictionary(grouping: discoveredLive.compactMap { sensor -> (String, SensorRecord)? in
            guard let homeID = homeID(from: sensor.id) else { return nil }
            return (homeID, sensor)
        }, by: \.0).mapValues { $0.map(\.1) }

        let storedHomes = Set(storedByHome.keys)
        let discoveredHomes = Set(discoveredByHome.keys)
        let retired = storedHomes.subtracting(discoveredHomes)
        let appeared = discoveredHomes.subtracting(storedHomes)

        if retired.isEmpty || appeared.isEmpty {
            return .notNeeded
        }
        guard retired.count == 1, appeared.count == 1,
              let retiredHomeID = retired.first,
              let replacementHomeID = appeared.first,
              let oldSensors = storedByHome[retiredHomeID],
              let newSensors = discoveredByHome[replacementHomeID] else {
            return .refused(
                "expected one retired home id and one replacement, found \(retired.count) retired and \(appeared.count) new"
            )
        }

        let oldKeys = Dictionary(grouping: oldSensors, by: MatchKey.init)
        let newKeys = Dictionary(grouping: newSensors, by: MatchKey.init)
        if oldKeys.contains(where: { $0.value.count != 1 }) || newKeys.contains(where: { $0.value.count != 1 }) {
            return .refused(
                "duplicate sensor identity within a home (same room, accessory, service, and characteristic)"
            )
        }
        guard Set(oldKeys.keys) == Set(newKeys.keys) else {
            return .refused("sensor keys are not a 1:1 match")
        }

        let pairs = oldKeys.keys.sorted { lhs, rhs in
            (lhs.roomName, lhs.accessoryName, lhs.serviceName, lhs.characteristicType)
                < (rhs.roomName, rhs.accessoryName, rhs.serviceName, rhs.characteristicType)
        }.compactMap { key -> SensorContinuityPair? in
            guard let existing = oldKeys[key]?.first, let discovered = newKeys[key]?.first else { return nil }
            return SensorContinuityPair(existing: existing, discovered: discovered)
        }
        guard pairs.count == oldSensors.count, pairs.count == newSensors.count else {
            return .refused("sensor keys are not a 1:1 match")
        }
        return .rebound(pairs: pairs, retiredHomeID: retiredHomeID, replacementHomeID: replacementHomeID)
    }
}
