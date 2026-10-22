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
