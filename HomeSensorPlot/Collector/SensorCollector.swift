import Foundation
import HomeKit

@MainActor
final class SensorCollector: NSObject, ObservableObject {
    @Published private(set) var status: CollectorStatus = .starting

    private let store: SampleStore
    private let homeKit: HomeKitSensorProvider
    private let settings: AppSettings
    private var scrapeTask: Task<Void, Never>?
    private var pruneTask: Task<Void, Never>?
    private var characteristicToSensorID: [UUID: String] = [:]
    private var acceptance = SampleAcceptanceDebouncer()
    private var sensorCache: [String: SensorRecord] = [:]
    private var collectInFlight = false

    /// True while a scrape/notification collect pass is running.
    var isCollecting: Bool { collectInFlight }

    /// Latest whole-home rebind outcome, for the support dump.
    private(set) var continuitySummary = "not run yet"
    private var pendingRebindMap: [String: String] = [:]

    /// Old sensor id → replacement id from the most recent successful rebind. Consumed by the UI refresh.
    func consumeRebindMap() -> [String: String] {
        let map = pendingRebindMap
        pendingRebindMap = [:]
        return map
    }

    init(store: SampleStore, homeKit: HomeKitSensorProvider, settings: AppSettings) {
        self.store = store
        self.homeKit = homeKit
        self.settings = settings
        super.init()
        homeKit.onHomeKitChanged = { [weak self] in
            Task { @MainActor in
                await self?.forceCollectOnce()
            }
        }
    }

    func start() {
        scrapeTask?.cancel()
        pruneTask?.cancel()

        scrapeTask = Task { [weak self] in
            await self?.runLoop()
        }
        pruneTask = Task { [weak self] in
            await self?.runPruneLoop()
        }
    }

    func stop() {
        scrapeTask?.cancel()
        pruneTask?.cancel()
        scrapeTask = nil
        pruneTask = nil
    }

    /// Returns `false` when a collect is already in flight (caller can surface feedback).
    @discardableResult
    func forceCollectOnce() async -> Bool {
        guard !collectInFlight else { return false }
        await collect()
        return true
    }

    private func runLoop() async {
        await homeKit.waitUntilHomesUpdate()
        while !Task.isCancelled {
            await collect()
            let seconds = max(15, settings.scrapeIntervalSeconds)
            try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
        }
    }

    private func runPruneLoop() async {
        while !Task.isCancelled {
            do {
                _ = try store.prune(retentionDays: settings.retentionDays)
            } catch {
                status = .error(error.localizedDescription)
            }
            try? await Task.sleep(nanoseconds: 24 * 60 * 60 * 1_000_000_000)
        }
    }

    private func collect() async {
        collectInFlight = true
        defer { collectInFlight = false }

        if settings.useMockData {
            do {
                try MockSensorSeeder.seedIfNeeded(store: store)
                let count = try store.sensors(mockOnly: true).count
                status = .mockMode(sensorCount: count)
            } catch {
                status = .error(error.localizedDescription)
            }
            return
        }

        // Live mode: drop leftover demo rows so UI/exporter aren't polluted.
        do {
            try store.deleteMockSensors()
            if !settings.collectUnknownCharacteristics {
                try store.deleteAutoMetricSensors()
            }
        } catch {
            status = .error(error.localizedDescription)
            return
        }

        homeKit.refreshAuthorizationState()
        switch homeKit.authorizationState {
        case .denied, .restricted:
            status = .unauthorized
            return
        case .unknown:
            status = .waitingForHomeKit
            return
        case .authorized:
            break
        }

        let readings = await homeKit.discoverReadings(
            includeUnknown: settings.collectUnknownCharacteristics
        )

        if readings.isEmpty {
            status = .homeKitIdle(
                homeKit.snapshot(candidateCount: homeKit.lastCandidateCount, readableCount: 0)
            )
            return
        }

        do {
            refreshSensorCache()
            let decision = SensorContinuity.decide(
                stored: Array(sensorCache.values),
                discovered: readings.map(\.sensor)
            )
            continuitySummary = decision.summary
            if case .rebound(let pairs, _, _) = decision {
                try store.rebind(pairs)
                pendingRebindMap = Dictionary(uniqueKeysWithValues: pairs.map {
                    ($0.existing.id, $0.discovered.id)
                })
                refreshSensorCache()
            }
            var batch: [(sensorID: String, timestamp: Date, value: Double)] = []
            var notify: [HMCharacteristic] = []
            let now = Date()

            for reading in readings {
                if let existing = sensorCache[reading.sensor.id], existing.isBlocked {
                    continue
                }

                var sensor = reading.sensor
                if let existing = sensorCache[sensor.id] {
                    sensor.isHidden = existing.isHidden
                    sensor.isBlocked = existing.isBlocked
                }
                try store.upsertSensor(sensor)
                sensorCache[sensor.id] = sensor

                if acceptance.shouldAccept(sensorID: sensor.id, at: now) {
                    batch.append((sensor.id, now, reading.value))
                }

                if let characteristic = reading.characteristic {
                    characteristicToSensorID[characteristic.uniqueIdentifier] = sensor.id
                    if let accessory = characteristic.service?.accessory {
                        accessory.delegate = self
                    }
                    notify.append(characteristic)
                }
            }

            try store.insertSamples(batch)
            homeKit.enableNotifications(for: notify)
            let count = try store.sensors(mockOnly: false).filter { !$0.isBlocked }.count
            status = .collecting(sensorCount: count)
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    private func refreshSensorCache() {
        do {
            let all = try store.sensors(mockOnly: false)
            sensorCache = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        } catch {
            // Keep prior cache on read failure.
        }
    }

    private func handleCharacteristicUpdate(_ characteristic: HMCharacteristic) {
        guard let value = SensorCharacteristicClassifier.doubleValue(from: characteristic) else { return }
        guard let sensorID = characteristicToSensorID[characteristic.uniqueIdentifier] else { return }

        do {
            if sensorCache[sensorID]?.isBlocked == true { return }
            let now = Date()
            guard acceptance.shouldAccept(sensorID: sensorID, at: now) else { return }
            try store.insertSample(sensorID: sensorID, timestamp: now, value: value)
        } catch {
            status = .error(error.localizedDescription)
        }
    }
}

extension SensorCollector: HMAccessoryDelegate {
    nonisolated func accessory(
        _ accessory: HMAccessory,
        service: HMService,
        didUpdateValueFor characteristic: HMCharacteristic
    ) {
        Task { @MainActor in
            self.handleCharacteristicUpdate(characteristic)
        }
    }
}
