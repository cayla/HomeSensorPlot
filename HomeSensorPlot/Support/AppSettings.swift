import Foundation

@MainActor
final class AppSettings: ObservableObject {
    private enum Keys {
        static let exporterEnabled = "exporterEnabled"
        static let exporterPort = "exporterPort"
        static let retentionDays = "retentionDays"
        static let useMockData = "useMockData"
        static let scrapeIntervalSeconds = "scrapeIntervalSeconds"
        static let temperatureUnit = "temperatureUnit"
        static let collectUnknownCharacteristics = "collectUnknownCharacteristics"
        static let showOutdoorWeather = "showOutdoorWeather"
        static let allowIPGeolocationFallback = "allowIPGeolocationFallback"
    }

    private let defaults: UserDefaults

    /// Off by default — localhost Prometheus scrape is opt-in (App Store / review-friendly).
    @Published var exporterEnabled: Bool {
        didSet { defaults.set(exporterEnabled, forKey: Keys.exporterEnabled) }
    }

    @Published var exporterPort: Int {
        didSet { defaults.set(exporterPort, forKey: Keys.exporterPort) }
    }

    @Published var retentionDays: Int {
        didSet { defaults.set(retentionDays, forKey: Keys.retentionDays) }
    }

    /// When true (default until HomeKit works), seed and refresh mock sensors.
    @Published var useMockData: Bool {
        didSet { defaults.set(useMockData, forKey: Keys.useMockData) }
    }

    @Published var scrapeIntervalSeconds: Int {
        didSet { defaults.set(scrapeIntervalSeconds, forKey: Keys.scrapeIntervalSeconds) }
    }

    /// Display preference only — storage and /metrics stay in Celsius.
    @Published var temperatureUnit: TemperatureUnit {
        didSet { defaults.set(temperatureUnit.rawValue, forKey: Keys.temperatureUnit) }
    }

    /// When false (default), skip HAP `homekit_auto_*` noise and keep only known sensor types.
    @Published var collectUnknownCharacteristics: Bool {
        didSet { defaults.set(collectUnknownCharacteristics, forKey: Keys.collectUnknownCharacteristics) }
    }

    /// Overlay local outdoor temperature (Open-Meteo) on the Temperature chart.
    @Published var showOutdoorWeather: Bool {
        didSet { defaults.set(showOutdoorWeather, forKey: Keys.showOutdoorWeather) }
    }

    /// When outdoor weather is on and Core Location fails, optionally resolve coords via IP (third party).
    /// Off by default — must be an explicit choice.
    @Published var allowIPGeolocationFallback: Bool {
        didSet { defaults.set(allowIPGeolocationFallback, forKey: Keys.allowIPGeolocationFallback) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Keys.exporterEnabled) == nil {
            exporterEnabled = false
        } else {
            exporterEnabled = defaults.bool(forKey: Keys.exporterEnabled)
        }
        exporterPort = defaults.object(forKey: Keys.exporterPort) as? Int ?? 9105
        retentionDays = defaults.object(forKey: Keys.retentionDays) as? Int ?? 60
        // Prefer live HomeKit; mock is a fallback / explicit override.
        if defaults.object(forKey: Keys.useMockData) == nil {
            useMockData = false
        } else {
            useMockData = defaults.bool(forKey: Keys.useMockData)
        }
        scrapeIntervalSeconds = defaults.object(forKey: Keys.scrapeIntervalSeconds) as? Int ?? 60

        if let raw = defaults.string(forKey: Keys.temperatureUnit),
           let unit = TemperatureUnit(rawValue: raw)
        {
            temperatureUnit = unit
        } else {
            // US locale → Fahrenheit; everyone else Celsius.
            let usesF = Locale.current.measurementSystem == .us
            temperatureUnit = usesF ? .fahrenheit : .celsius
        }

        if defaults.object(forKey: Keys.collectUnknownCharacteristics) == nil {
            collectUnknownCharacteristics = false
        } else {
            collectUnknownCharacteristics = defaults.bool(forKey: Keys.collectUnknownCharacteristics)
        }

        if defaults.object(forKey: Keys.showOutdoorWeather) == nil {
            showOutdoorWeather = true
        } else {
            showOutdoorWeather = defaults.bool(forKey: Keys.showOutdoorWeather)
        }

        if defaults.object(forKey: Keys.allowIPGeolocationFallback) == nil {
            allowIPGeolocationFallback = false
        } else {
            allowIPGeolocationFallback = defaults.bool(forKey: Keys.allowIPGeolocationFallback)
        }
    }
}
