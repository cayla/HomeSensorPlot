import Combine
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let outdoorWeatherSeriesID = "__outdoor_weather__"

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
    @Published var outdoorChartEnabled = true
    @Published var outdoorWeatherError: String?
    @Published var timeBox: TimeBox = .twentyFourHours
    @Published var customStart: Date = Date().addingTimeInterval(-86_400)
    @Published var openAtLogin: Bool = LoginItemManager.isEnabled
    @Published var lastRefreshError: String?
    /// Non-fatal store path warning (temp DB fallback).
    @Published var storeBootstrapWarning: String?
    /// Menu / settings label: `off` or `127.0.0.1:port`.
    @Published var exporterAddress: String = "off"
    /// True when the category sidebar is in “all selected” mode (new sensors auto-enable).
    @Published private(set) var categorySelectAllMode = true

    private var refreshTask: Task<Void, Never>?
    private var didStart = false
    private var cancellables = Set<AnyCancellable>()

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
    func syncExporter() {
        guard settings.exporterEnabled else {
            exporter.stop()
            exporterAddress = "off"
            if lastRefreshError?.localizedCaseInsensitiveContains("Exporter") == true {
                lastRefreshError = nil
            }
            pushStatusToMacBridge()
            return
        }

        do {
            try exporter.restart(port: settings.exporterPort)
            exporterAddress = "127.0.0.1:\(NumberFormatting.port(settings.exporterPort))"
            if lastRefreshError?.localizedCaseInsensitiveContains("Exporter") == true {
                lastRefreshError = nil
            }
        } catch {
            // Keep the toggle on so the user can retry; never advertise a fake scrape URL.
            exporterAddress = "off"
            lastRefreshError = "Exporter failed: \(error.localizedDescription)"
        }
        pushStatusToMacBridge()
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
            let all = try store.sensors(mockOnly: settings.useMockData)
            sensors = all
            if let category = selectedCategory {
                syncEnabledSensors(for: category)
                await reloadCategoryChart()
            }
            // Don't surface HomeKit per-characteristic "not supported" noise in the footer.
            if lastRefreshError?.localizedCaseInsensitiveContains("not supported") == true {
                lastRefreshError = nil
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
        categoryEnabledSensorIDs = []
        outdoorWeatherError = nil
    }

    /// Top-level nav targets always return to the root of that section.
    func resetToSectionRoot() {
        closeCategory()
    }

    func setCategorySensor(_ id: String, enabled: Bool) {
        categorySelectAllMode = false
        if enabled {
            categoryEnabledSensorIDs.insert(id)
        } else {
            categoryEnabledSensorIDs.remove(id)
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
            return
        }

        let start = timeBox.startDate(customStart: customStart)
        let members = category.sensors(from: sensors)
        var points: [ChartSeriesPoint] = []
        let tempUnit = settings.temperatureUnit

        do {
            for sensor in members {
                let samples = try store.samples(sensorID: sensor.id, from: start)
                // Keep per-series points modest — large multi-series charts beachball on hover otherwise.
                let perSeriesCap = max(80, 600 / max(members.count, 1))
                let downsampled = SeriesDownsample.stride(samples, maxPoints: perSeriesCap)
                let room = sensor.roomName.isEmpty ? sensor.homeName : sensor.roomName
                // Temperature: unit shown once on the page title — keep series labels short.
                let label: String
                if category == .temperature {
                    label = "\(room) · \(sensor.accessoryName)"
                } else {
                    label = "\(room) · \(sensor.accessoryName) · \(sensor.unit)"
                }
                for sample in downsampled {
                    let value: Double
                    if category == .temperature {
                        value = tempUnit.display(fromCelsius: sample.value)
                    } else {
                        value = sample.value
                    }
                    points.append(
                        ChartSeriesPoint(
                            sensorID: sensor.id,
                            label: label,
                            timestamp: sample.timestamp,
                            value: value
                        )
                    )
                }
            }

            // Publish HomeKit series immediately — never block the chart on weather/location.
            let indoorOnly = points.filter { $0.sensorID != Self.outdoorWeatherSeriesID }
            categoryChartPoints = indoorOnly

            if category == .temperature, settings.showOutdoorWeather, outdoorChartEnabled {
                weather.configure(allowIPGeolocationFallback: settings.allowIPGeolocationFallback)
                await loadOutdoorWeatherOverlay(start: start, temperatureUnit: tempUnit)
            } else {
                outdoorWeatherError = nil
            }
        } catch {
            lastRefreshError = error.localizedDescription
            categoryChartPoints = []
        }
    }

    private func loadOutdoorWeatherOverlay(start: Date, temperatureUnit: TemperatureUnit) async {
        do {
            let outdoor = try await weather.fetchHourlyTemperatures(from: start)
            let trimmed = Array(outdoor.suffix(max(48, 200)))
            var outdoorPoints: [ChartSeriesPoint] = []
            outdoorPoints.reserveCapacity(trimmed.count)
            for point in trimmed {
                outdoorPoints.append(
                    ChartSeriesPoint(
                        sensorID: Self.outdoorWeatherSeriesID,
                        label: "Outdoor · weather",
                        timestamp: point.timestamp,
                        value: temperatureUnit.display(fromCelsius: point.celsius)
                    )
                )
            }
            // Keep whatever indoor series is current; swap outdoor series only.
            var merged = categoryChartPoints.filter { $0.sensorID != Self.outdoorWeatherSeriesID }
            merged.append(contentsOf: outdoorPoints)
            categoryChartPoints = merged
            if weather.historyTruncated {
                outdoorWeatherError =
                    "Outdoor history limited to \(WeatherService.maxHistoryDays) days (Open-Meteo)."
            } else {
                outdoorWeatherError = nil
            }
        } catch {
            outdoorWeatherError = error.localizedDescription
            categoryChartPoints = categoryChartPoints.filter { $0.sensorID != Self.outdoorWeatherSeriesID }
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
