import Foundation

enum TemperatureUnit: String, CaseIterable, Identifiable, Sendable {
    case celsius
    case fahrenheit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .celsius: return "Celsius (°C)"
        case .fahrenheit: return "Fahrenheit (°F)"
        }
    }

    var shortSymbol: String {
        switch self {
        case .celsius: return "°C"
        case .fahrenheit: return "°F"
        }
    }

    /// Storage / HomeKit / Prometheus stay in Celsius.
    func display(fromCelsius celsius: Double) -> Double {
        switch self {
        case .celsius: return celsius
        case .fahrenheit: return celsius * 9.0 / 5.0 + 32.0
        }
    }
}
