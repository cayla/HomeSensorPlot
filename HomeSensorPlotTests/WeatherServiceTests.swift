import CoreLocation
import XCTest
@testable import HomeSensorPlot

@MainActor
final class WeatherServiceTests: XCTestCase {
    func testHistoryTruncationThreshold() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertFalse(
            WeatherService.isHistoryTruncated(
                from: now.addingTimeInterval(-30 * 86_400),
                now: now
            )
        )
        XCTAssertTrue(
            WeatherService.isHistoryTruncated(
                from: now.addingTimeInterval(-100 * 86_400),
                now: now
            )
        )
        XCTAssertEqual(
            WeatherService.requestedHistoryDays(from: now.addingTimeInterval(-86_400), now: now),
            2
        )
    }

    func testStoredHistoryCoversARecentFullSpan() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let start = now.addingTimeInterval(-30 * 86_400)
        let points = [
            OutdoorTemperaturePoint(timestamp: start, celsius: 1),
            OutdoorTemperaturePoint(timestamp: now.addingTimeInterval(-3600), celsius: 2),
        ]
        XCTAssertTrue(WeatherService.storedHistoryCovers(points, from: start, to: now, now: now))
    }

    func testStoredHistoryDoesNotCoverAShortPrefix() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let start = now.addingTimeInterval(-30 * 86_400)
        let points = [
            OutdoorTemperaturePoint(timestamp: now.addingTimeInterval(-6 * 86_400), celsius: 1),
            OutdoorTemperaturePoint(timestamp: now.addingTimeInterval(-3600), celsius: 2),
        ]
        XCTAssertFalse(WeatherService.storedHistoryCovers(points, from: start, to: now, now: now))
    }

    func testStoredHistoryTreatsTheApiLimitAsCovered() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let start = now.addingTimeInterval(-200 * 86_400)
        let oldestAvailable = now.addingTimeInterval(-Double(WeatherService.maxHistoryDays) * 86_400)
        let points = [
            OutdoorTemperaturePoint(timestamp: oldestAvailable, celsius: 1),
            OutdoorTemperaturePoint(timestamp: now.addingTimeInterval(-3600), celsius: 2),
        ]
        XCTAssertTrue(WeatherService.storedHistoryCovers(points, from: start, to: now, now: now))
    }

    func testIPFallbackDisabledThrowsWithoutNetwork() async {
        let weather = WeatherService()
        weather.configure(allowIPGeolocationFallback: false)
        weather.coordinateResolutionOverride = .failure(WeatherServiceError.locationDenied)

        do {
            _ = try await weather.fetchHourlyTemperatures(from: Date().addingTimeInterval(-3_600))
            XCTFail("Expected ipFallbackDisabled")
        } catch let error as WeatherServiceError {
            XCTAssertEqual(error, .ipFallbackDisabled)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testIPFallbackDisabledErrorCopy() {
        XCTAssertTrue(
            WeatherServiceError.ipFallbackDisabled.errorDescription?
                .localizedCaseInsensitiveContains("IP geolocation") == true
        )
    }
}

extension WeatherServiceError: Equatable {
    public static func == (lhs: WeatherServiceError, rhs: WeatherServiceError) -> Bool {
        switch (lhs, rhs) {
        case (.locationDenied, .locationDenied),
             (.locationUnavailable, .locationUnavailable),
             (.ipFallbackDisabled, .ipFallbackDisabled),
             (.badResponse, .badResponse):
            return true
        case (.http(let a), .http(let b)):
            return a == b
        default:
            return false
        }
    }
}
