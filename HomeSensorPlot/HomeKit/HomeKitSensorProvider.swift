import Foundation
import HomeKit

struct DiscoveredSensorReading: Sendable {
    var sensor: SensorRecord
    var value: Double
    var characteristic: HMCharacteristic?
}

@MainActor
final class HomeKitSensorProvider: NSObject, ObservableObject {
    enum AuthorizationState: Equatable {
        case unknown
        case authorized
        case denied
        case restricted
    }

    @Published private(set) var authorizationState: AuthorizationState = .unknown
    @Published private(set) var homesLoaded = false
    @Published private(set) var lastError: String?
    @Published private(set) var homeCount = 0
    @Published private(set) var accessoryCount = 0
    @Published private(set) var lastCandidateCount = 0

    /// Fired when homes or authorization change so the collector can re-run immediately.
    var onHomeKitChanged: (() -> Void)?

    private let manager = HMHomeManager()
    private var homesUpdateWaiters: [CheckedContinuation<Void, Never>] = []

    override init() {
        super.init()
        manager.delegate = self
        refreshAuthorizationState()
    }

    /// Waits until HomeKit reports homes (or `timeout` elapses). Supports multiple waiters.
    func waitUntilHomesUpdate(timeoutSeconds: TimeInterval = 30) async {
        if homesLoaded { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let scheduleTimeout = homesUpdateWaiters.isEmpty
            homesUpdateWaiters.append(continuation)
            if scheduleTimeout {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                    if !self.homesLoaded {
                        self.resumeHomesUpdateWaiters()
                    }
                }
            }
        }
    }

    private func resumeHomesUpdateWaiters() {
        let waiters = homesUpdateWaiters
        homesUpdateWaiters = []
        for waiter in waiters {
            waiter.resume()
        }
    }

    func refreshAuthorizationState() {
        let status = manager.authorizationStatus
        if status.contains(.authorized) {
            authorizationState = .authorized
        } else if status.contains(.restricted) {
            authorizationState = .restricted
        } else if status.contains(.determined) {
            // Determined without authorized/restricted bits ⇒ denied.
            // Exception: if homes already loaded with content, treat as authorized
            // (Catalyst sometimes lags the option-set bits after Allow).
            if homesLoaded, !manager.homes.isEmpty {
                authorizationState = .authorized
            } else {
                authorizationState = .denied
            }
        } else if homesLoaded, !manager.homes.isEmpty {
            authorizationState = .authorized
        } else {
            authorizationState = .unknown
        }
        homeCount = manager.homes.count
        accessoryCount = manager.homes.reduce(0) { $0 + $1.accessories.count }
        NSLog(
            "HomeSensorPlot HomeKit: auth=%@ raw=%lu homesLoaded=%d homes=%d accessories=%d",
            authorizationLabel,
            UInt(status.rawValue),
            homesLoaded ? 1 : 0,
            homeCount,
            accessoryCount
        )
    }

    var authorizationLabel: String {
        switch authorizationState {
        case .unknown: return "not determined"
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        }
    }

    func snapshot(candidateCount: Int, readableCount: Int) -> HomeKitSnapshot {
        HomeKitSnapshot(
            authorizationLabel: authorizationLabel,
            homeCount: homeCount,
            accessoryCount: accessoryCount,
            candidateCount: candidateCount,
            readableCount: readableCount
        )
    }

    /// Find sensor-like characteristics (may have nil values until read).
    func discoverCandidates(includeUnknown: Bool = false) -> [(sensor: SensorRecord, characteristic: HMCharacteristic)] {
        refreshAuthorizationState()
        guard authorizationState == .authorized || (!manager.homes.isEmpty && homesLoaded) else {
            return []
        }

        var candidates: [(SensorRecord, HMCharacteristic)] = []

        for home in manager.homes {
            for accessory in home.accessories {
                let roomName = accessory.room?.name ?? ""
                for service in accessory.services {
                    for characteristic in service.characteristics {
                        guard let classified = SensorCharacteristicClassifier.classify(
                            characteristic: characteristic,
                            includeUnknown: includeUnknown
                        ) else { continue }

                        let sensorID = [
                            home.uniqueIdentifier.uuidString,
                            accessory.uniqueIdentifier.uuidString,
                            service.uniqueIdentifier.uuidString,
                            characteristic.uniqueIdentifier.uuidString,
                        ].joined(separator: ":")

                        let sensor = SensorRecord(
                            id: sensorID,
                            homeName: home.name,
                            roomName: roomName,
                            accessoryName: accessory.name,
                            serviceName: service.name,
                            characteristicType: characteristic.characteristicType,
                            metricName: classified.metricName,
                            unit: classified.unit,
                            isHidden: false,
                            isBlocked: false,
                            autoDiscovered: classified.autoDiscovered,
                            lastValue: SensorCharacteristicClassifier.doubleValue(from: characteristic),
                            lastUpdated: .now
                        )
                        candidates.append((sensor, characteristic))
                    }
                }
            }
        }

        return candidates
    }

    /// Read current values, then return samples that have numeric/bool values.
    func discoverReadings(includeUnknown: Bool = false) async -> [DiscoveredSensorReading] {
        let candidates = discoverCandidates(includeUnknown: includeUnknown)
        lastCandidateCount = candidates.count
        guard !candidates.isEmpty else { return [] }

        // Prefer cached values; only read when readable and still nil.
        for (_, characteristic) in candidates {
            if SensorCharacteristicClassifier.doubleValue(from: characteristic) != nil { continue }
            guard characteristic.properties.contains(HMCharacteristicPropertyReadable) else { continue }
            await readValue(characteristic)
        }

        var readings: [DiscoveredSensorReading] = []
        for (sensor, characteristic) in candidates {
            guard let value = SensorCharacteristicClassifier.doubleValue(from: characteristic) else {
                continue
            }
            var updated = sensor
            updated.lastValue = value
            updated.lastUpdated = .now
            readings.append(
                DiscoveredSensorReading(sensor: updated, value: value, characteristic: characteristic)
            )
        }
        return readings
    }

    func enableNotifications(for characteristics: [HMCharacteristic]) {
        for characteristic in characteristics {
            // Many sensor chars reject notifications; only ask when HomeKit says events are supported.
            guard characteristic.properties.contains(HMCharacteristicPropertySupportsEventNotification) else {
                continue
            }
            guard characteristic.isNotificationEnabled == false else { continue }
            characteristic.enableNotification(true) { error in
                if let error {
                    NSLog("HomeSensorPlot: notification enable failed for %@: %@",
                          characteristic.characteristicType, error.localizedDescription)
                }
            }
        }
    }

    private func readValue(_ characteristic: HMCharacteristic) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            characteristic.readValue { error in
                if let error {
                    let message = error.localizedDescription
                    // HAP often rejects reads on write-only / notify-only / media chars — ignore.
                    if !message.localizedCaseInsensitiveContains("not supported") {
                        NSLog("HomeSensorPlot: read failed for %@: %@",
                              characteristic.characteristicType, message)
                    }
                }
                continuation.resume()
            }
        }
    }

    private func notifyChanged() {
        onHomeKitChanged?()
    }
}

extension HomeKitSensorProvider: HMHomeManagerDelegate {
    nonisolated func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        Task { @MainActor in
            self.homesLoaded = true
            self.refreshAuthorizationState()
            self.resumeHomesUpdateWaiters()
            self.notifyChanged()
        }
    }

    nonisolated func homeManager(_ manager: HMHomeManager, didUpdate status: HMHomeManagerAuthorizationStatus) {
        Task { @MainActor in
            self.refreshAuthorizationState()
            self.notifyChanged()
        }
    }
}
