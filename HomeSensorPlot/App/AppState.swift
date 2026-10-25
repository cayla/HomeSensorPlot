import Combine
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let outdoorWeatherSeriesID = "__outdoor_weather__"
    static let outdoorWeatherSeriesLabel = "Outdoor · weather"

    let settings: AppSettings
    let store: SampleStore
    let homeKit: HomeKitSensorProvider
    let collector: SensorCollector
    let exporter: PrometheusExporter
    let weather: WeatherService

    @Published var sensors: [SensorRecord] = []
    @Published var selectedCategory: SensorCategory?
    @Published var categoryEnabledSensorIDs: Set<String> = []
    @Published var categoryChartPoints: [ChartSeriesPoint] = []
    /// Full-window samples behind each sidebar range. The chart series is downsampled separately.
    @Published var categoryWindowSamples: [String: [ChartInteraction.Sample]] = [:]
    @Published var outdoorChartEnabled = true
    @Published var outdoorWeatherError: String?
    @Published var timeBox: TimeBox = .lastDay
    @Published var customStart: Date = Date().addingTimeInterval(-86_400)
    @Published var openAtLogin: Bool = LoginItemManager.isEnabled
    @Published var lastRefreshError: String? {
        didSet {
            guard !suppressFooterSync else { return }
            if let lastRefreshError {
                footerNotice = .other(lastRefreshError)
            } else {
                footerNotice = nil
            }
        }
    }
    /// Non-fatal store path warning (temp DB fallback).
    @Published var storeBootstrapWarning: String?
    /// Menu / settings label: `off` or `127.0.0.1:port`.
    @Published var exporterAddress: String = "off"
    /// True when the category sidebar is in “all selected” mode (new sensors auto-enable).
    @Published private(set) var categorySelectAllMode = true

    private var refreshTask: Task<Void, Never>?
    private var didStart = false
    private var cancellables = Set<AnyCancellable>()
    private var footerNotice: FooterNotice?
    private var suppressFooterSync = false

    init() {
        let settings = AppSettings()
        self.settings = settings
        self.weather = WeatherService()
        weather.configure(allowIPGeolocationFallback: settings.allowIPGeolocationFallback)

        let store: SampleStore
        do {
            store = try SampleStore()
        } catch {
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("HomeSensorPlot-tmp-\(UUID().uuidString)", isDirectory: true)
            do {
                store = try SampleStore(directory: tmp)
                storeBootstrapWarning =
                    "Could not open Application Support database (\(error.localizedDescription)). Using a temporary store — data will not persist."
            } catch {
                // Temp also failed — nothing useful we can do.
                fatalError("Failed to open HomeSensorPlot store: \(error)")
            }
        }

        self.store = store
        let homeKit = HomeKitSensorProvider()
        self.homeKit = homeKit
        self.collector = SensorCollector(store: store, homeKit: homeKit, settings: settings)
        self.exporter = PrometheusExporter(store: store)
        self.exporter.onListenStateChanged = { [weak self] result in
            Task { @MainActor in
                self?.handleExporterListenState(result)
            }
        }

        collector.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        homeKit.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.weather.configure(allowIPGeolocationFallback: settings.allowIPGeolocationFallback)
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        weather.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var status: CollectorStatus {
        collector.status
    }

    func start() {
        guard !didStart else { return }
        didStart = true

        syncExporter()

        collector.start()
        refreshTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.refreshUI()
                self.pushStatusToMacBridge()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    /// Start or stop the localhost Prometheus listener to match Settings.
    /// Address stays `off` until the listener reports `.ready` (avoids a fake scrape URL).
    func syncExporter() {
        guard settings.exporterEnabled else {
            exporter.stop()
            exporterAddress = "off"
            clearExporterFailure()
            pushStatusToMacBridge()
            return
        }

        do {
            exporterAddress = "off"
            try exporter.restart(port: settings.exporterPort)
            // `handleExporterListenState` sets the address when Network.framework reports ready.
        } catch {
            // Keep the toggle on so the user can retry; never advertise a fake scrape URL.
            exporterAddress = "off"
            setExporterFailure(error)
            pushStatusToMacBridge()
        }
    }

    private func handleExporterListenState(_ result: Result<UInt16, Error>) {
        guard settings.exporterEnabled else {
            exporterAddress = "off"
            pushStatusToMacBridge()
            return
        }
        switch result {
        case .success(let port):
            exporterAddress = "127.0.0.1:\(NumberFormatting.port(Int(port)))"
            clearExporterFailure()
        case .failure(let error):
            exporterAddress = "off"
            setExporterFailure(error)
        }
        pushStatusToMacBridge()
    }

    private func setExporterFailure(_ error: Error) {
        applyFooter(.exporter("Exporter failed: \(error.localizedDescription)"))
    }

    private func clearExporterFailure() {
        applyFooter(footerNotice?.withoutExporterFailure)
    }

    private func applyFooter(_ notice: FooterNotice?) {
        footerNotice = notice
        suppressFooterSync = true
        lastRefreshError = notice?.message
        suppressFooterSync = false
    }

    func setExporterEnabled(_ enabled: Bool) {
        settings.exporterEnabled = enabled
        syncExporter()
    }

    /// Update port and rebind immediately when the exporter is enabled.
    func setExporterPort(_ port: Int) {
        settings.exporterPort = max(1, min(port, 65535))
        if settings.exporterEnabled {
            syncExporter()
        }
    }

    @discardableResult
    func collectNow() async -> Bool {
        let ran = await collector.forceCollectOnce()
        if !ran {
            lastRefreshError = "Collection already in progress — try again in a moment."
        }
        await refreshUI()
        return ran
    }

    func pushStatusToMacBridge() {
        #if targetEnvironment(macCatalyst)
        MacOSPluginBootstrap.controller?.macBridgeUpdateStatus(
            status.shortLabel,
            symbolName: status.menuBarSymbol
        )
        MacOSPluginBootstrap.controller?.macBridgeUpdateExporter(exporterAddress)
        #endif
    }

    func stop() {
        refreshTask?.cancel()
        collector.stop()
        exporter.stop()
    }

    func refreshUI() async {
        do {
            let rebindMap = collector.consumeRebindMap()
            if !rebindMap.isEmpty {
                categoryEnabledSensorIDs = Set(categoryEnabledSensorIDs.map { rebindMap[$0] ?? $0 })
            }
            let all = try store.sensors(mockOnly: settings.useMockData)
            sensors = all
            if let category = selectedCategory {
                syncEnabledSensors(for: category)
                await reloadCategoryChart()
            }
        } catch {
            lastRefreshError = error.localizedDescription
        }
    }

    func openCategory(_ category: SensorCategory) {
        selectedCategory = category
        let ids = Set(category.sensors(from: sensors).map(\.id))
        categoryEnabledSensorIDs = ids
        categorySelectAllMode = true
        outdoorChartEnabled = true
        Task { await reloadCategoryChart() }
    }

    func closeCategory() {
        selectedCategory = nil
        categoryChartPoints = []
        categoryWindowSamples = [:]
        categoryEnabledSensorIDs = []
        outdoorWeatherError = nil
    }

    /// Top-level nav targets always return to the root of that section.
    func resetToSectionRoot() {
        closeCategory()
    }

    func tapCategoryChartRow(_ id: String) {
        let wasOutdoor = outdoorChartEnabled
        let next = CategoryChartSelection.tap(
            id,
            outdoorID: Self.outdoorWeatherSeriesID,
            state: CategoryChartSelection.State(
                enabledIDs: categoryEnabledSensorIDs,
                outdoorEnabled: outdoorChartEnabled,
                selectsAll: categorySelectAllMode
            )
        )
        categoryEnabledSensorIDs = next.enabledIDs
        outdoorChartEnabled = next.outdoorEnabled
        categorySelectAllMode = next.selectsAll
        // A failed outdoor fetch can be retried by showing the line again.
        // Hiding it must not drop the samples — the sidebar still shows them.
        if !wasOutdoor, next.outdoorEnabled {
            Task { await reloadCategoryChart() }
        }
    }

    func setAllCategorySensors(enabled: Bool) {
        guard let category = selectedCategory else { return }
        categorySelectAllMode = enabled
        if enabled {
            categoryEnabledSensorIDs = Set(category.sensors(from: sensors).map(\.id))
            outdoorChartEnabled = true
        } else {
            categoryEnabledSensorIDs = []
            outdoorChartEnabled = false
        }
    }

    func reloadCategoryChart() async {
        guard let category = selectedCategory else {
            categoryChartPoints = []
            categoryWindowSamples = [:]
            return
        }

        let window = timeBox.window(customStart: customStart)
        let sampleEnd = window.sampleEnd(now: .now)
        let members = category.sensors(from: sensors)
        var points: [ChartSeriesPoint] = []
        var windowSamples: [String: [ChartInteraction.Sample]] = [:]
        let tempUnit = settings.temperatureUnit

        do {
            for sensor in members {
                let samples = try store.samples(sensorID: sensor.id, from: window.start, to: sampleEnd)
                // Keep per-series points modest — large multi-series charts beachball on hover otherwise.
                let perSeriesCap = max(80, 600 / max(members.count, 1))
                let anchor = try store.latestSample(sensorID: sensor.id, before: window.start)
                let series = ChartSeriesAssembly.sensorSeries(
                    sensorID: sensor.id,
                    label: category.chartSeriesLabel(for: sensor),
                    windowStart: window.start,
                    samples: samples,
                    anchor: anchor,
                    maxPoints: perSeriesCap,
                    value: { sample in
                        if category == .temperature {
                            return tempUnit.display(fromCelsius: sample.value)
                        }
                        return sample.value
                    }
                )
                points.append(contentsOf: series.plotted)
                windowSamples[sensor.id] = series.window
            }

            // Publish HomeKit series immediately — never block the chart on weather/location.
            let indoorOnly = points.filter { $0.sensorID != Self.outdoorWeatherSeriesID }
            categoryChartPoints = indoorOnly
            categoryWindowSamples = windowSamples

            // Load outdoor even when the line is hidden. The chart filters it;
            // the sidebar still shows the current reading and the window.
            if category == .temperature, settings.showOutdoorWeather {
                weather.configure(allowIPGeolocationFallback: settings.allowIPGeolocationFallback)
                await loadOutdoorWeatherOverlay(
                    window: window,
                    sampleEnd: sampleEnd,
                    temperatureUnit: tempUnit
                )
            } else {
                outdoorWeatherError = nil
            }
        } catch {
            lastRefreshError = error.localizedDescription
            categoryChartPoints = []
            categoryWindowSamples = [:]
        }
    }

    private func loadOutdoorWeatherOverlay(
        window: ChartTimeWindow,
        sampleEnd: Date,
        temperatureUnit: TemperatureUnit
    ) async {
        let fetchStart = window.start.addingTimeInterval(-3600)
        do {
            var stored = try store.outdoorTemperatures(from: fetchStart, to: sampleEnd)
            if !WeatherService.storedHistoryCovers(stored, from: fetchStart, to: sampleEnd) {
                do {
                    // One extra hour so the segment that crosses the left edge is available.
                    let fresh = try await weather.fetchHourlyTemperatures(from: fetchStart, to: sampleEnd)
                    try store.upsertOutdoorTemperatures(fresh)
                    stored = try store.outdoorTemperatures(from: fetchStart, to: sampleEnd)
                } catch {
                    guard !stored.isEmpty else {
                        outdoorWeatherError = error.localizedDescription
                        categoryChartPoints = categoryChartPoints.filter {
                            $0.sensorID != Self.outdoorWeatherSeriesID
                        }
                        var samples = categoryWindowSamples
                        samples.removeValue(forKey: Self.outdoorWeatherSeriesID)
                        categoryWindowSamples = samples
                        return
                    }
                    publishOutdoor(stored, window: window, temperatureUnit: temperatureUnit)
                    outdoorWeatherError = error.localizedDescription
                    return
                }
            }
            publishOutdoor(stored, window: window, temperatureUnit: temperatureUnit)
            if WeatherService.isHistoryTruncated(from: window.start) {
                outdoorWeatherError =
                    "Outdoor history limited to \(WeatherService.maxHistoryDays) days (Open-Meteo)."
            } else {
                outdoorWeatherError = nil
            }
        } catch {
            outdoorWeatherError = error.localizedDescription
            categoryChartPoints = categoryChartPoints.filter { $0.sensorID != Self.outdoorWeatherSeriesID }
            var samples = categoryWindowSamples
            samples.removeValue(forKey: Self.outdoorWeatherSeriesID)
            categoryWindowSamples = samples
        }
    }

    private func publishOutdoor(
        _ outdoor: [OutdoorTemperaturePoint],
        window: ChartTimeWindow,
        temperatureUnit: TemperatureUnit
    ) {
        let inWindow = outdoor.filter { $0.timestamp >= window.start && $0.timestamp <= window.end }
        let anchor = inWindow.first.flatMap { first in
            outdoor.last { $0.timestamp < first.timestamp }
        }
        let outdoorPoints = ChartSeriesAssembly.seriesPoints(
            sensorID: Self.outdoorWeatherSeriesID,
            label: Self.outdoorWeatherSeriesLabel,
            windowStart: window.start,
            inWindow: inWindow,
            anchor: anchor,
            timestamp: { $0.timestamp },
            value: { temperatureUnit.display(fromCelsius: $0.celsius) }
        )
        var merged = categoryChartPoints.filter { $0.sensorID != Self.outdoorWeatherSeriesID }
        merged.append(contentsOf: outdoorPoints)
        categoryChartPoints = merged
        categoryWindowSamples[Self.outdoorWeatherSeriesID] = outdoorPoints.map {
            ChartInteraction.Sample(timestamp: $0.timestamp, value: $0.value)
        }
    }

    func setHidden(sensorID: String, hidden: Bool) {
        do {
            try store.setHidden(sensorID: sensorID, hidden: hidden)
            Task { await refreshUI() }
        } catch {
            lastRefreshError = error.localizedDescription
        }
    }

    func setBlocked(sensorID: String, blocked: Bool) {
        do {
            try store.setBlocked(sensorID: sensorID, blocked: blocked)
            Task { await refreshUI() }
        } catch {
            lastRefreshError = error.localizedDescription
        }
    }

    func applyExporterPort() {
        guard settings.exporterEnabled else {
            exporterAddress = "off"
            return
        }
        syncExporter()
    }

    func toggleOpenAtLogin(_ enabled: Bool) {
        do {
            openAtLogin = try LoginItemManager.setEnabled(enabled)
        } catch {
            lastRefreshError = error.localizedDescription
            openAtLogin = LoginItemManager.isEnabled
        }
    }

    func enableMockDataAndReseed() {
        settings.useMockData = true
        Task { await collectNow() }
    }

    func useLiveHomeKit() {
        settings.useMockData = false
        Task { await collectNow() }
    }

    func resetCollectedData() {
        do {
            try store.deleteAllCollectedData()
            sensors = []
            categoryChartPoints = []
            categoryWindowSamples = [:]
            categoryEnabledSensorIDs = []
            lastRefreshError = nil
            Task {
                await refreshUI()
                await collectNow()
            }
        } catch {
            lastRefreshError = error.localizedDescription
        }
    }

    func makeSupportDump() -> String {
        let records = (try? store.allSensors()) ?? sensors
        let input = SupportDumpInput(
            generatedAt: Date(),
            bundleID: Bundle.main.bundleIdentifier ?? "unknown",
            appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            buildNumber: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            channel: store.channel.rawValue,
            databaseFileName: store.databaseURL.lastPathComponent,
            legacyCopiedTo: SampleStore.legacyCopiedChannels(in: store.databaseURL.deletingLastPathComponent()),
            homeKitAuthorization: homeKit.authorizationLabel,
            homeCount: homeKit.homeCount,
            accessoryCount: homeKit.accessoryCount,
            candidateCount: homeKit.lastCandidateCount,
            collectorStatus: status.shortLabel,
            continuity: collector.continuitySummary,
            sensorCount: records.count,
            sampleCount: (try? store.sampleCount()) ?? -1,
            sensors: records.map { sensor in
                SupportDumpSensor(
                    id: sensor.id,
                    homeName: sensor.homeName,
                    roomName: sensor.roomName,
                    accessoryName: sensor.accessoryName,
                    serviceName: sensor.serviceName,
                    characteristicType: sensor.characteristicType,
                    metricName: sensor.metricName,
                    unit: sensor.unit,
                    isHidden: sensor.isHidden,
                    isBlocked: sensor.isBlocked,
                    lastValue: sensor.lastValue,
                    lastUpdated: sensor.lastUpdated
                )
            }
        )
        return SupportDump.json(input)
    }

    /// When “All” is active, pick up newly discovered sensors; after None/manual, only drop stale IDs.
    private func syncEnabledSensors(for category: SensorCategory) {
        let valid = Set(category.sensors(from: sensors).map(\.id))
        if categorySelectAllMode {
            categoryEnabledSensorIDs = valid
        } else {
            categoryEnabledSensorIDs = categoryEnabledSensorIDs.intersection(valid)
        }
    }

}
