import CoreLocation
import Foundation

struct OutdoorTemperaturePoint: Identifiable, Hashable, Sendable {
    var id: Date { timestamp }
    var timestamp: Date
    var celsius: Double
}

enum WeatherServiceError: Error, LocalizedError {
    case locationDenied
    case locationUnavailable
    case ipFallbackDisabled
    case badResponse
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .locationDenied:
            return "Location access denied — enable it in System Settings, or turn on IP geolocation fallback in Settings."
        case .locationUnavailable:
            return "Could not determine location for weather."
        case .ipFallbackDisabled:
            return "Location unavailable and IP geolocation fallback is off (Settings)."
        case .badResponse:
            return "Weather service returned invalid data."
        case .http(let code):
            return "Weather service HTTP \(code)."
        }
    }
}

/// Free Open-Meteo forecast/history (no API key). Values are Celsius.
@MainActor
final class WeatherService: NSObject, ObservableObject {
    /// Open-Meteo forecast `past_days` max. Older than this needs the archive API.
    static let maxHistoryDays = 92

    @Published private(set) var lastError: String?
    @Published private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var coordinateSource: String?
    /// True when the requested chart range exceeds Open-Meteo history we can fetch.
    @Published private(set) var historyTruncated = false

    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D, Error>?
    private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    private var cachedPoints: [OutdoorTemperaturePoint] = []
    private var cachedRangeStart: Date?
    private var cacheFetchedAt: Date?
    private var allowIPGeolocationFallback = false

    /// Test seam: short-circuits Core Location (and skips IP unless fallback is enabled).
    var coordinateResolutionOverride: Result<CLLocationCoordinate2D, Error>?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func configure(allowIPGeolocationFallback: Bool) {
        self.allowIPGeolocationFallback = allowIPGeolocationFallback
    }

    static func requestedHistoryDays(from start: Date, now: Date = Date()) -> Int {
        max(1, Int(ceil(now.timeIntervalSince(start) / 86_400)) + 1)
    }

    static func isHistoryTruncated(from start: Date, now: Date = Date()) -> Bool {
        requestedHistoryDays(from: start, now: now) > maxHistoryDays
    }

    /// `points` must be time-sorted. A full refetch is unnecessary when the stored hours
    /// already reach the start we can actually get, and a recent hour.
    static func storedHistoryCovers(
        _ points: [OutdoorTemperaturePoint],
        from start: Date,
        to end: Date,
        now: Date = .now
    ) -> Bool {
        guard let oldest = points.first?.timestamp, let newest = points.last?.timestamp else {
            return false
        }
        let neededNewest = min(end, now).addingTimeInterval(-2 * 3600)
        guard newest >= neededNewest else { return false }
        let earliestAvailable = now.addingTimeInterval(-Double(maxHistoryDays) * 86_400)
        let neededOldest = max(start, earliestAvailable)
        return oldest <= neededOldest.addingTimeInterval(3600)
    }

    func fetchHourlyTemperatures(from start: Date, to end: Date = .now) async throws -> [OutdoorTemperaturePoint] {
        let requestedDays = Self.requestedHistoryDays(from: start)
        historyTruncated = requestedDays > Self.maxHistoryDays

        if let cachedRangeStart,
           let cacheFetchedAt,
           abs(cachedRangeStart.timeIntervalSince(start)) < 120,
           Date().timeIntervalSince(cacheFetchedAt) < 300,
           !cachedPoints.isEmpty
        {
            return cachedPoints.filter { $0.timestamp >= start && $0.timestamp <= end }
        }

        let coord = try await resolveCoordinate()
        let pastDays = max(1, min(Self.maxHistoryDays, requestedDays))

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(coord.latitude)),
            URLQueryItem(name: "longitude", value: String(coord.longitude)),
            URLQueryItem(name: "hourly", value: "temperature_2m"),
            URLQueryItem(name: "temperature_unit", value: "celsius"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "past_days", value: String(pastDays)),
            URLQueryItem(name: "forecast_days", value: "1"),
        ]

        guard let url = components.url else { throw WeatherServiceError.badResponse }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw WeatherServiceError.http(http.statusCode)
        }

        let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)

        var points: [OutdoorTemperaturePoint] = []
        for (index, timeString) in decoded.hourly.time.enumerated() {
            guard index < decoded.hourly.temperature_2m.count else { break }
            guard let ts = Self.parseHour(timeString) else { continue }
            guard ts >= start, ts <= end else { continue }
            points.append(
                OutdoorTemperaturePoint(timestamp: ts, celsius: decoded.hourly.temperature_2m[index])
            )
        }

        cachedPoints = points
        cachedRangeStart = start
        cacheFetchedAt = .now
        lastError = nil
        return points
    }

    /// Prefer Core Location; optional IP geolocation only when the user enabled the Settings toggle.
    private func resolveCoordinate() async throws -> CLLocationCoordinate2D {
        if let coordinate { return coordinate }

        if let override = coordinateResolutionOverride {
            switch override {
            case .success(let coord):
                coordinate = coord
                coordinateSource = "override"
                return coord
            case .failure:
                guard allowIPGeolocationFallback else {
                    throw WeatherServiceError.ipFallbackDisabled
                }
                let fromIP = try await locateViaIP()
                coordinate = fromIP
                coordinateSource = "ip"
                return fromIP
            }
        }

        do {
            let fromDevice = try await locateViaCoreLocation()
            coordinate = fromDevice
            coordinateSource = "device"
            return fromDevice
        } catch {
            NSLog("HomeSensorPlot weather: Core Location failed (%@)", error.localizedDescription)
            guard allowIPGeolocationFallback else {
                throw WeatherServiceError.ipFallbackDisabled
            }
            NSLog("HomeSensorPlot weather: using IP geolocation fallback")
        }

        let fromIP = try await locateViaIP()
        coordinate = fromIP
        coordinateSource = "ip"
        return fromIP
    }

    private func locateViaCoreLocation() async throws -> CLLocationCoordinate2D {
        var status = locationManager.authorizationStatus
        if status == .notDetermined {
            status = await requestAuthorization(timeoutSeconds: 10)
        }

        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            break
        case .denied, .restricted:
            throw WeatherServiceError.locationDenied
        case .notDetermined:
            throw WeatherServiceError.locationUnavailable
        @unknown default:
            throw WeatherServiceError.locationUnavailable
        }

        return try await requestCoordinate(timeoutSeconds: 12)
    }

    private func requestAuthorization(timeoutSeconds: TimeInterval) async -> CLAuthorizationStatus {
        let current = locationManager.authorizationStatus
        if current != .notDetermined { return current }

        return await withCheckedContinuation { continuation in
            // Only one waiter; resume any prior to avoid SWIFT TASK CONTINUATION MISUSE.
            if let prior = self.authorizationContinuation {
                prior.resume(returning: self.locationManager.authorizationStatus)
            }
            self.authorizationContinuation = continuation
            locationManager.requestWhenInUseAuthorization()

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                if let waiter = self.authorizationContinuation {
                    self.authorizationContinuation = nil
                    waiter.resume(returning: self.locationManager.authorizationStatus)
                }
            }
        }
    }

    private func requestCoordinate(timeoutSeconds: TimeInterval) async throws -> CLLocationCoordinate2D {
        if let coordinate { return coordinate }

        return try await withCheckedThrowingContinuation { continuation in
            if let prior = self.locationContinuation {
                prior.resume(throwing: CancellationError())
            }
            self.locationContinuation = continuation
            self.locationManager.requestLocation()

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                if let waiter = self.locationContinuation {
                    self.locationContinuation = nil
                    waiter.resume(throwing: WeatherServiceError.locationUnavailable)
                }
            }
        }
    }

    private func locateViaIP() async throws -> CLLocationCoordinate2D {
        // Free HTTPS geo IP — no API key, good enough for outdoor weather.
        guard let url = URL(string: "https://get.geojs.io/v1/ip/geo.json") else {
            throw WeatherServiceError.locationUnavailable
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw WeatherServiceError.http(http.statusCode)
        }
        let geo = try JSONDecoder().decode(GeoJSResponse.self, from: data)
        guard let lat = Double(geo.latitude), let lon = Double(geo.longitude) else {
            throw WeatherServiceError.badResponse
        }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private static func parseHour(_ value: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withColonSeparatorInTime]
        if let date = iso.date(from: value) { return date }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        formatter.timeZone = .current
        return formatter.date(from: value)
    }

    private struct OpenMeteoResponse: Decodable {
        struct Hourly: Decodable {
            var time: [String]
            var temperature_2m: [Double]
        }

        var hourly: Hourly
    }

    private struct GeoJSResponse: Decodable {
        var latitude: String
        var longitude: String
    }
}

extension WeatherService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard status != .notDetermined else { return }
            guard let waiter = self.authorizationContinuation else { return }
            self.authorizationContinuation = nil
            waiter.resume(returning: status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else {
                self.finishLocation(with: .failure(WeatherServiceError.locationUnavailable))
                return
            }
            self.finishLocation(with: .success(location.coordinate))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.lastError = error.localizedDescription
            self.finishLocation(with: .failure(error))
        }
    }

    private func finishLocation(with result: Result<CLLocationCoordinate2D, Error>) {
        guard let waiter = locationContinuation else { return }
        locationContinuation = nil
        switch result {
        case .success(let coordinate):
            self.coordinate = coordinate
            waiter.resume(returning: coordinate)
        case .failure(let error):
            waiter.resume(throwing: error)
        }
    }
}
