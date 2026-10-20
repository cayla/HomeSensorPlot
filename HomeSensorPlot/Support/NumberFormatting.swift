import Foundation

enum NumberFormatting {
    /// Measurement values for UI — respects system decimal / grouping separators.
    static func measurement(_ value: Double, fractionLength: Int = 2) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(0...fractionLength))
        )
    }

    /// Port / host:port — never group digits (9,105 breaks URLs and Slack paste).
    static func port(_ value: Int) -> String {
        value.formatted(.number.grouping(.never))
    }
}
