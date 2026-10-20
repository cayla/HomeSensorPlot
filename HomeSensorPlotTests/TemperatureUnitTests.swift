import XCTest
@testable import HomeSensorPlot

final class TemperatureUnitTests: XCTestCase {
    func testCelsiusPassthrough() {
        XCTAssertEqual(TemperatureUnit.celsius.display(fromCelsius: 21.5), 21.5)
    }

    func testFahrenheitConversion() {
        XCTAssertEqual(TemperatureUnit.fahrenheit.display(fromCelsius: 0), 32, accuracy: 0.0001)
        XCTAssertEqual(TemperatureUnit.fahrenheit.display(fromCelsius: 100), 212, accuracy: 0.0001)
        XCTAssertEqual(TemperatureUnit.fahrenheit.display(fromCelsius: 20), 68, accuracy: 0.0001)
    }

    func testSymbols() {
        XCTAssertEqual(TemperatureUnit.celsius.shortSymbol, "°C")
        XCTAssertEqual(TemperatureUnit.fahrenheit.shortSymbol, "°F")
    }
}
