import Foundation

enum ChartAxisKind: Equatable {
    case percent
    case state
    case continuous

    static func of(_ category: SensorCategory) -> ChartAxisKind {
        if category.isStateCategory { return .state }
        switch category {
        case .humidity, .battery, .filterLife:
            return .percent
        default:
            return .continuous
        }
    }

    func domain(values: [Double]) -> ClosedRange<Double> {
        switch self {
        case .percent:
            return 0...100
        case .state:
            return -0.05...1.05
        case .continuous:
            return ChartInteraction.paddedDomain(values)
        }
    }
}

/// Chart hit-testing and value wording. Kept out of the SwiftUI view so the
/// hover window and state labels can be tested without rendering a chart.
enum ChartInteraction {
    struct Sample: Equatable {
        var timestamp: Date
        var value: Double
    }

    struct HoverSeries {
        var id: String
        var samples: [Sample]
        var matchWindow: TimeInterval
    }

    struct HoverPick: Equatable {
        var id: String
        var index: Int
    }

    static func paddedDomain(_ values: [Double]) -> ClosedRange<Double> {
        guard let minV = values.min(), let maxV = values.max() else {
            return 0...1
        }
        if minV == maxV {
            let pad = max(abs(minV) * 0.08, 1)
            return (minV - pad)...(maxV + pad)
        }
        let pad = (maxV - minV) * 0.12
        return (minV - pad)...(maxV + pad)
    }

    /// Index of the sample nearest `time`. `samples` must be sorted by timestamp.
    static func nearestIndex(in samples: [Sample], to time: Date) -> Int? {
        guard !samples.isEmpty else { return nil }
        var low = 0
        var high = samples.count - 1
        let target = time.timeIntervalSince1970
        while low < high {
            let mid = (low + high) / 2
            if samples[mid].timestamp.timeIntervalSince1970 < target {
                low = mid + 1
            } else {
                high = mid
            }
        }
        let index = low
        if index == 0 { return 0 }
        let previousDelta = abs(samples[index - 1].timestamp.timeIntervalSince1970 - target)
        let currentDelta = abs(samples[index].timestamp.timeIntervalSince1970 - target)
        return previousDelta <= currentDelta ? index - 1 : index
    }

    /// Series whose nearest sample is inside that series' match window, nearest in Y first.
    /// A cursor in a hole (farther than the window) produces no pick for that series.
    static func picks(
        series: [HoverSeries],
        time: Date,
        yValue: Double,
        stateCategory: Bool
    ) -> [HoverPick] {
        struct Candidate {
            var id: String
            var index: Int
            var distance: Double
        }

        var candidates: [Candidate] = []
        for item in series {
            guard let index = nearestIndex(in: item.samples, to: time) else { continue }
            let sample = item.samples[index]
            guard abs(sample.timestamp.timeIntervalSince(time)) <= item.matchWindow else { continue }
            candidates.append(
                Candidate(id: item.id, index: index, distance: abs(sample.value - yValue))
            )
        }
        candidates.sort { $0.distance < $1.distance }
        guard let best = candidates.first else { return [] }

        let threshold = max(best.distance * 1.25, yThreshold(yValue, stateCategory: stateCategory))
        return candidates.filter { $0.distance <= threshold }.map {
            HoverPick(id: $0.id, index: $0.index)
        }
    }

    static func yThreshold(_ y: Double, stateCategory: Bool) -> Double {
        if stateCategory { return 0.35 }
        return max(abs(y) * 0.04, 0.75)
    }

    static func hoverText(category: SensorCategory, value: Double) -> String {
        if let state = stateText(category: category, value: value) {
            return state
        }
        return NumberFormatting.measurement(value)
    }

    /// Sidebar values are still in storage units. Hover text is already converted.
    static func sidebarText(
        category: SensorCategory,
        value: Double,
        unit: String,
        temperatureUnit: TemperatureUnit
    ) -> String {
        if let state = stateText(category: category, value: value) {
            return state
        }
        switch category {
        case .temperature:
            return NumberFormatting.measurement(temperatureUnit.display(fromCelsius: value))
        default:
            if unit == "bool" {
                return value >= 0.5 ? "on" : "off"
            }
            return "\(NumberFormatting.measurement(value)) \(unit)"
        }
    }

    /// Shared wording for state categories. Nil means format the number.
    static func stateText(category: SensorCategory, value: Double) -> String? {
        switch category {
        case .contact:
            return value >= 0.5 ? "open" : "closed"
        case .lock:
            if value >= 0.5, value < 1.5 { return "secured" }
            if value < 0.5 { return "unsecured" }
            return nil
        case .motion, .occupancy, .leak, .smoke:
            return value >= 0.5 ? "detected" : "clear"
        default:
            return nil
        }
    }
}

/// In-window samples plus the one sample before the left edge, so a line can enter the plot.
enum ChartSeriesAssembly {
    static func seriesPoints<S>(
        sensorID: String,
        label: String,
        windowStart: Date,
        inWindow: [S],
        anchor: S?,
        timestamp: (S) -> Date,
        value: (S) -> Double
    ) -> [ChartSeriesPoint] {
        guard let first = inWindow.first else { return [] }
        var rows: [(sample: S, isAnchor: Bool)] = []
        if let anchor {
            let anchorTime = timestamp(anchor)
            if anchorTime < timestamp(first) {
                rows.append((anchor, anchorTime < windowStart))
            }
        }
        for sample in inWindow {
            rows.append((sample, false))
        }
        return rows.map { row in
            ChartSeriesPoint(
                sensorID: sensorID,
                label: label,
                timestamp: timestamp(row.sample),
                value: value(row.sample),
                isAnchor: row.isAnchor
            )
        }
    }
}

/// Categorical chart colors, ordered so successive entries stay easy to tell apart.
///
/// Six is the set where every pair is still a different named color. Another hue
/// lands on blue, green, or orange, so later series repeat from the start.
enum ChartPalette {
    struct RGB: Equatable, Sendable {
        var red: Double
        var green: Double
        var blue: Double
    }

    static let ordered: [RGB] = [
        RGB(red: 0x4C / 255, green: 0x8D / 255, blue: 0xFF / 255),
        RGB(red: 0xFF / 255, green: 0xE6 / 255, blue: 0x6D / 255),
        RGB(red: 0xC7 / 255, green: 0x7D / 255, blue: 0xFF / 255),
        RGB(red: 0x3D / 255, green: 0xDC / 255, blue: 0x57 / 255),
        RGB(red: 0xFF / 255, green: 0x5D / 255, blue: 0x8F / 255),
        RGB(red: 0xFF / 255, green: 0x9F / 255, blue: 0x1C / 255),
    ]

    static func color(atAlphabeticalPosition position: Int) -> RGB {
        let count = ordered.count
        let index = ((position % count) + count) % count
        return ordered[index]
    }

    /// OKLab distance. Adjacent entries are above 0.20; every pair is above 0.15.
    static func separation(_ lhs: RGB, _ rhs: RGB) -> Double {
        let left = oklab(lhs)
        let right = oklab(rhs)
        let dL = left.l - right.l
        let dA = left.a - right.a
        let dB = left.b - right.b
        return (dL * dL + dA * dA + dB * dB).squareRoot()
    }

    private static func oklab(_ color: RGB) -> (l: Double, a: Double, b: Double) {
        func linear(_ channel: Double) -> Double {
            if channel <= 0.04045 {
                return channel / 12.92
            }
            return pow((channel + 0.055) / 1.055, 2.4)
        }
        let red = linear(color.red)
        let green = linear(color.green)
        let blue = linear(color.blue)
        let l = 0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue
        let m = 0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue
        let s = 0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue
        let lRoot = pow(l, 1.0 / 3.0)
        let mRoot = pow(m, 1.0 / 3.0)
        let sRoot = pow(s, 1.0 / 3.0)
        return (
            l: 0.2104542553 * lRoot + 0.7936177850 * mRoot - 0.0040720468 * sRoot,
            a: 1.9779984951 * lRoot - 2.4285922050 * mRoot + 0.4505937099 * sRoot,
            b: 0.0259040371 * lRoot + 0.7827717662 * mRoot - 0.8086757660 * sRoot
        )
    }
}
