import Foundation

enum NumberFormatting {
    /// Measurement values for UI. Always the same number of decimals, so 64 and 64.2 line up.
    static func measurement(_ value: Double, fractionLength: Int = 1) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(fractionLength))
        )
    }

    /// `67.6°` and `46%` sit against the number. `lux` and `ppm` take a space.
    static func withUnit(_ number: String, _ symbol: String?) -> String {
        guard let symbol else { return number }
        if symbol == "°" || symbol == "%" {
            return number + symbol
        }
        return number + " " + symbol
    }

    /// Port / host:port — never group digits (9,105 breaks URLs and Slack paste).
    static func port(_ value: Int) -> String {
        value.formatted(.number.grouping(.never))
    }
}
