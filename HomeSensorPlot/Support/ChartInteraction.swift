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

    /// Low, high, and time-weighted average of a time-sorted series.
    struct WindowStats: Equatable {
        var minimum: Double
        var maximum: Double
        /// Nil when no drawn interval has duration, so a mean across gaps is not invented.
        var average: Double?
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

    /// Stats for the plotted series. Nil when fewer than two samples exist.
    ///
    /// The average follows the drawn line: trapezoids between samples, and no
    /// contribution across a gap where the line breaks. A burst of readings
    /// only counts for the time it spans. When no interval has duration, there
    /// is no average. `samples` must be sorted by time.
    static func windowStats(samples: [Sample]) -> WindowStats? {
        guard samples.count >= 2 else { return nil }

        var minimum = samples[0].value
        var maximum = samples[0].value
        for sample in samples.dropFirst() {
            minimum = min(minimum, sample.value)
            maximum = max(maximum, sample.value)
        }

        let segments = SeriesGaps.layout(timestamps: samples.map(\.timestamp)).segments
        var weighted = 0.0
        var duration = 0.0
        for index in 1..<samples.count {
            guard segments[index] == segments[index - 1] else { continue }
            let dt = samples[index].timestamp.timeIntervalSince(samples[index - 1].timestamp)
            guard dt > 0 else { continue }
            weighted += (samples[index - 1].value + samples[index].value) / 2 * dt
            duration += dt
        }

        let average = duration > 0 ? weighted / duration : nil
        return WindowStats(minimum: minimum, maximum: maximum, average: average)
    }

    /// `18.2–23.4° · avg 20.1°` for the window. Nil for state categories,
    /// a single sample, or a range that still matches at two decimals.
    /// One extra decimal is used when compact `k`/`M` rounding would hide a spread.
    static func statsText(
        category: SensorCategory,
        samples: [Sample],
        symbol: String? = nil
    ) -> String? {
        guard ChartAxisKind.of(category) != .state else { return nil }
        guard let stats = windowStats(samples: samples) else { return nil }
        guard let fractionLength = rangeFractionLength(minimum: stats.minimum, maximum: stats.maximum) else {
            return nil
        }
        let low = NumberFormatting.measurement(stats.minimum, fractionLength: fractionLength)
        let high = NumberFormatting.measurement(stats.maximum, fractionLength: fractionLength)
        let range = "\(low)–\(NumberFormatting.withUnit(high, symbol))"
        guard let average = stats.average else { return range }
        let averageText = NumberFormatting.measurement(average, fractionLength: fractionLength)
        return "\(range) · avg \(NumberFormatting.withUnit(averageText, symbol))"
    }

    /// One decimal, unless that draws the same number for both ends.
    /// Two decimals still matching means the spread is display noise.
    private static func rangeFractionLength(minimum: Double, maximum: Double) -> Int? {
        let coarseLow = NumberFormatting.measurement(minimum)
        let coarseHigh = NumberFormatting.measurement(maximum)
        if coarseLow != coarseHigh { return 1 }
        let fineLow = NumberFormatting.measurement(minimum, fractionLength: 2)
        let fineHigh = NumberFormatting.measurement(maximum, fractionLength: 2)
        return fineLow == fineHigh ? nil : 2
    }

    static func hoverText(category: SensorCategory, value: Double) -> String {
        if let state = stateText(category: category, value: value) {
            return state
        }
        return NumberFormatting.measurement(value)
    }

    struct SidebarReading: Equatable {
        var text: String
        /// A measurement sits large on the trailing edge. State words stay smaller.
        var prominent: Bool
    }

    /// Sidebar values are still in storage units. Hover text is already converted.
    static func sidebarReading(
        category: SensorCategory,
        value: Double,
        unit: String,
        temperatureUnit: TemperatureUnit
    ) -> SidebarReading {
        if stateText(category: category, value: value) != nil || unit == "bool" {
            return SidebarReading(
                text: sidebarText(
                    category: category,
                    value: value,
                    unit: unit,
                    temperatureUnit: temperatureUnit
                ),
                prominent: false
            )
        }
        let number: String
        if category == .temperature {
            number = NumberFormatting.measurement(temperatureUnit.display(fromCelsius: value))
        } else {
            number = NumberFormatting.measurement(value)
        }
        return SidebarReading(
            text: NumberFormatting.withUnit(number, category.measurementSymbol(unit: unit)),
            prominent: true
        )
    }

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

/// Which sidebar rows are drawn.
///
/// While All is in effect, the first tap keeps that row and clears the rest.
/// Every later tap toggles the row that was hit.
enum CategoryChartSelection {
    struct State: Equatable {
        var enabledIDs: Set<String>
        var outdoorEnabled: Bool
        var selectsAll: Bool
    }

    static func tap(_ id: String, outdoorID: String, state: State) -> State {
        if state.selectsAll {
            if id == outdoorID {
                return State(enabledIDs: [], outdoorEnabled: true, selectsAll: false)
            }
            return State(enabledIDs: [id], outdoorEnabled: false, selectsAll: false)
        }
        var next = state
        if id == outdoorID {
            next.outdoorEnabled.toggle()
        } else if next.enabledIDs.contains(id) {
            next.enabledIDs.remove(id)
        } else {
            next.enabledIDs.insert(id)
        }
        return next
    }
}

/// In-window samples, plus the visible piece of the segment that crosses the left edge.
///
/// The earlier sample is not plotted. A mark outside the scale makes Swift Charts
/// refit the axis around it, which blows up an hour-long domain.
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
        guard !inWindow.isEmpty else { return [] }
        var times = inWindow.map(timestamp)
        var values = inWindow.map(value)
        if let anchor {
            let anchorTime = timestamp(anchor)
            let anchorValue = value(anchor)
            if anchorTime < times[0] {
                if anchorTime >= windowStart {
                    times.insert(anchorTime, at: 0)
                    values.insert(anchorValue, at: 0)
                } else if connects(anchorTime: anchorTime, to: times) {
                    let edge = interpolated(
                        from: (anchorTime, anchorValue),
                        to: (times[0], values[0]),
                        at: windowStart
                    )
                    if windowStart < times[0] {
                        times.insert(windowStart, at: 0)
                        values.insert(edge, at: 0)
                    }
                }
            }
        }
        return zip(times, values).map { time, sampleValue in
            ChartSeriesPoint(
                sensorID: sensorID,
                label: label,
                timestamp: time,
                value: sampleValue,
                isAnchor: false
            )
        }
    }

    /// Chart points stay capped. The window samples do not, so a spike between
    /// stride picks still counts in the sidebar range.
    static func sensorSeries(
        sensorID: String,
        label: String,
        windowStart: Date,
        samples: [SamplePoint],
        anchor: SamplePoint?,
        maxPoints: Int,
        value: (SamplePoint) -> Double
    ) -> (plotted: [ChartSeriesPoint], window: [ChartInteraction.Sample]) {
        let windowPoints = seriesPoints(
            sensorID: sensorID,
            label: label,
            windowStart: windowStart,
            inWindow: samples,
            anchor: anchor,
            timestamp: { $0.timestamp },
            value: value
        )
        let plotted = seriesPoints(
            sensorID: sensorID,
            label: label,
            windowStart: windowStart,
            inWindow: SeriesDownsample.stride(samples, maxPoints: maxPoints),
            anchor: anchor,
            timestamp: { $0.timestamp },
            value: value
        )
        let window = windowPoints.map {
            ChartInteraction.Sample(timestamp: $0.timestamp, value: $0.value)
        }
        return (plotted, window)
    }

    /// Same rule as the drawn line: a gap wider than the series' usual spacing stays broken.
    private static func connects(anchorTime: Date, to times: [Date]) -> Bool {
        let layout = SeriesGaps.layout(timestamps: [anchorTime] + times)
        return layout.segments.count > 1 && layout.segments[0] == layout.segments[1]
    }

    private static func interpolated(
        from start: (Date, Double),
        to end: (Date, Double),
        at time: Date
    ) -> Double {
        let span = end.0.timeIntervalSince(start.0)
        guard span > 0 else { return end.1 }
        let fraction = min(max(time.timeIntervalSince(start.0) / span, 0), 1)
        return start.1 + fraction * (end.1 - start.1)
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
