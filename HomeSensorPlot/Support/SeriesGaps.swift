import Foundation

/// Split a time-sorted series where a hole is wider than that series' usual spacing.
///
/// The break threshold is `factor` times the median gap. One missed sample stays
/// connected; a run of misses opens a gap in the line. The match window is half
/// that threshold, so a cursor on a drawn segment still finds a real sample and
/// a cursor in the hole does not.
enum SeriesGaps {
    static let breakFactor: Double = 2.5
    /// Used when a series has no spacing to measure (a single sample, or none).
    static let fallbackMatchWindow: TimeInterval = 45 * 60

    struct Layout: Equatable {
        var segments: [Int]
        var matchWindow: TimeInterval
    }

    static func layout(timestamps: [Date], factor: Double = breakFactor) -> Layout {
        let count = timestamps.count
        guard count > 1 else {
            return Layout(
                segments: Array(repeating: 0, count: count),
                matchWindow: fallbackMatchWindow
            )
        }

        var deltas: [TimeInterval] = []
        deltas.reserveCapacity(count - 1)
        for index in 1..<count {
            let delta = timestamps[index].timeIntervalSince(timestamps[index - 1])
            if delta > 0 {
                deltas.append(delta)
            }
        }
        guard !deltas.isEmpty else {
            return Layout(
                segments: Array(repeating: 0, count: count),
                matchWindow: fallbackMatchWindow
            )
        }

        let threshold = median(deltas) * factor
        var segments: [Int] = []
        segments.reserveCapacity(count)
        var segment = 0
        segments.append(0)
        for index in 1..<count {
            if timestamps[index].timeIntervalSince(timestamps[index - 1]) > threshold {
                segment += 1
            }
            segments.append(segment)
        }
        return Layout(segments: segments, matchWindow: threshold / 2)
    }

    private static func median(_ values: [TimeInterval]) -> TimeInterval {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }
}
