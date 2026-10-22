import XCTest
@testable import HomeSensorPlot

final class ChartInteractionTests: XCTestCase {
    func testNearestPicksCloserSample() {
        let samples = samples(minutes: [0, 60, 120])
        XCTAssertEqual(ChartInteraction.nearestIndex(in: samples, to: date(minutes: 20)), 0)
        XCTAssertEqual(ChartInteraction.nearestIndex(in: samples, to: date(minutes: 40)), 1)
        XCTAssertEqual(ChartInteraction.nearestIndex(in: samples, to: date(minutes: 200)), 2)
        XCTAssertNil(ChartInteraction.nearestIndex(in: [], to: date(minutes: 0)))
    }

    func testPaddedDomain() {
        XCTAssertEqual(ChartInteraction.paddedDomain([]), 0...1)
        XCTAssertEqual(ChartInteraction.paddedDomain([5, 5]), 4...6)
        let span = ChartInteraction.paddedDomain([10, 20])
        XCTAssertEqual(span.lowerBound, 8.8, accuracy: 0.0001)
        XCTAssertEqual(span.upperBound, 21.2, accuracy: 0.0001)
    }

    func testAxisDomains() {
        XCTAssertEqual(ChartAxisKind.of(.humidity), .percent)
        XCTAssertEqual(ChartAxisKind.of(.battery), .percent)
        XCTAssertEqual(ChartAxisKind.of(.filterLife), .percent)
        XCTAssertEqual(ChartAxisKind.of(.contact), .state)
        XCTAssertEqual(ChartAxisKind.of(.temperature), .continuous)
        XCTAssertEqual(ChartAxisKind.percent.domain(values: [40]), 0...100)
        XCTAssertEqual(ChartAxisKind.state.domain(values: [1]), -0.05...1.05)
    }

    func testCursorInAGapDoesNotMatch() {
        let timestamps = [0, 60, 120, 480].map { date(minutes: $0) }
        let layout = SeriesGaps.layout(timestamps: timestamps)
        let series = ChartInteraction.HoverSeries(
            id: "room",
            samples: timestamps.enumerated().map { offset, time in
                ChartInteraction.Sample(timestamp: time, value: Double(offset))
            },
            matchWindow: layout.matchWindow
        )
        // 300 min sits in the hole between 120 and 480. The match window is 75 min.
        let picks = ChartInteraction.picks(
            series: [series],
            time: date(minutes: 300),
            yValue: 1,
            stateCategory: false
        )
        XCTAssertTrue(picks.isEmpty)
    }

    func testCursorOnASegmentMatchesThatSample() {
        let timestamps = [0, 60, 120].map { date(minutes: $0) }
        let layout = SeriesGaps.layout(timestamps: timestamps)
        let series = ChartInteraction.HoverSeries(
            id: "room",
            samples: timestamps.map { ChartInteraction.Sample(timestamp: $0, value: 21) },
            matchWindow: layout.matchWindow
        )
        let picks = ChartInteraction.picks(
            series: [series],
            time: date(minutes: 30),
            yValue: 21,
            stateCategory: false
        )
        XCTAssertEqual(picks, [ChartInteraction.HoverPick(id: "room", index: 0)])
    }

    func testContinuousPicksKeepSeriesInsideTheYBand() {
        // Best distance is 10, so the band is 12.5. 12 stays, 30 does not.
        // Passing the far series first checks that order follows Y distance.
        let picks = ChartInteraction.picks(
            series: [
                pointSeries(id: "far", value: 30),
                pointSeries(id: "near", value: 10),
                pointSeries(id: "neighbor", value: 12),
            ],
            time: date(minutes: 0),
            yValue: 0,
            stateCategory: false
        )
        XCTAssertEqual(
            picks,
            [
                ChartInteraction.HoverPick(id: "near", index: 0),
                ChartInteraction.HoverPick(id: "neighbor", index: 0),
            ]
        )
    }

    func testStatePicksUseATighterYBand() {
        let picks = ChartInteraction.picks(
            series: [
                pointSeries(id: "other", value: 1),
                pointSeries(id: "here", value: 0),
                pointSeries(id: "close", value: 0.3),
            ],
            time: date(minutes: 0),
            yValue: 0,
            stateCategory: true
        )
        XCTAssertEqual(
            picks,
            [
                ChartInteraction.HoverPick(id: "here", index: 0),
                ChartInteraction.HoverPick(id: "close", index: 0),
            ]
        )
    }

    func testStateWordingIsShared() {
        XCTAssertEqual(ChartInteraction.hoverText(category: .contact, value: 1), "open")
        XCTAssertEqual(
            ChartInteraction.sidebarText(category: .contact, value: 0, unit: "bool", temperatureUnit: .celsius),
            "closed"
        )
        XCTAssertEqual(ChartInteraction.hoverText(category: .lock, value: 1), "secured")
        XCTAssertEqual(ChartInteraction.hoverText(category: .lock, value: 0), "unsecured")
        XCTAssertEqual(ChartInteraction.hoverText(category: .motion, value: 1), "detected")
        XCTAssertEqual(ChartInteraction.hoverText(category: .leak, value: 0), "clear")
        let display = TemperatureUnit.fahrenheit.display(fromCelsius: 0)
        XCTAssertEqual(
            ChartInteraction.sidebarText(
                category: .temperature,
                value: 0,
                unit: "celsius",
                temperatureUnit: .fahrenheit
            ),
            NumberFormatting.measurement(display)
        )
        XCTAssertEqual(
            ChartInteraction.sidebarText(category: .humidity, value: 1, unit: "bool", temperatureUnit: .celsius),
            "on"
        )
    }

    func testLeadingAnchorIsPlacedOnTheWindowEdge() {
        let points = ChartSeriesAssembly.seriesPoints(
            sensorID: "outdoor",
            label: "Outdoor · weather",
            windowStart: date(minutes: 40),
            inWindow: [reading(minutes: 100, value: 100)],
            anchor: reading(minutes: 0, value: 0),
            timestamp: { $0.timestamp },
            value: { $0.value }
        )
        XCTAssertEqual(points.map(\.timestamp), [date(minutes: 40), date(minutes: 100)])
        XCTAssertEqual(points.map(\.value), [40, 100])
        XCTAssertFalse(points.contains(where: \.isAnchor))
    }

    func testEmptyWindowDropsTheAnchor() {
        let points = ChartSeriesAssembly.seriesPoints(
            sensorID: "outdoor",
            label: "Outdoor · weather",
            windowStart: date(minutes: 60),
            inWindow: [ChartInteraction.Sample](),
            anchor: reading(minutes: 0, value: 10),
            timestamp: { $0.timestamp },
            value: { $0.value }
        )
        XCTAssertTrue(points.isEmpty)
    }

    func testAnchorAcrossARealGapIsDropped() {
        let points = ChartSeriesAssembly.seriesPoints(
            sensorID: "room",
            label: "Kitchen",
            windowStart: date(minutes: 99),
            inWindow: [
                reading(minutes: 100, value: 1),
                reading(minutes: 101, value: 2),
                reading(minutes: 102, value: 3),
            ],
            anchor: reading(minutes: 0, value: 0),
            timestamp: { $0.timestamp },
            value: { $0.value }
        )
        XCTAssertEqual(points.map(\.timestamp), [100, 101, 102].map { date(minutes: $0) })
    }

    func testAnchorInsideTheWindowIsARealSample() {
        let points = ChartSeriesAssembly.seriesPoints(
            sensorID: "outdoor",
            label: "Outdoor · weather",
            windowStart: date(minutes: 0),
            inWindow: [reading(minutes: 120, value: 12)],
            anchor: reading(minutes: 60, value: 11),
            timestamp: { $0.timestamp },
            value: { $0.value }
        )
        XCTAssertEqual(points.map(\.isAnchor), [false, false])
    }

    func testPaletteRepeatsFromTheStart() {
        let count = ChartPalette.ordered.count
        XCTAssertEqual(ChartPalette.color(atAlphabeticalPosition: 0), ChartPalette.ordered[0])
        XCTAssertEqual(ChartPalette.color(atAlphabeticalPosition: 1), ChartPalette.ordered[1])
        XCTAssertEqual(ChartPalette.color(atAlphabeticalPosition: count), ChartPalette.ordered[0])
        XCTAssertEqual(ChartPalette.color(atAlphabeticalPosition: count + 2), ChartPalette.ordered[2])
    }

    func testPaletteNeighborsStayApart() {
        let colors = ChartPalette.ordered
        XCTAssertGreaterThan(colors.count, 1)
        for index in colors.indices {
            let next = colors[(index + 1) % colors.count]
            XCTAssertGreaterThan(ChartPalette.separation(colors[index], next), 0.20)
        }
        for left in colors.indices {
            for right in colors.indices where right > left {
                XCTAssertGreaterThan(ChartPalette.separation(colors[left], colors[right]), 0.15)
            }
        }
        // Locks the OKLab helper to the blue → yellow step.
        XCTAssertEqual(
            ChartPalette.separation(colors[0], colors[1]),
            0.416,
            accuracy: 0.01
        )
    }

    private func date(minutes: Double) -> Date {
        Date(timeIntervalSince1970: minutes * 60)
    }

    private func samples(minutes: [Double]) -> [ChartInteraction.Sample] {
        minutes.map { ChartInteraction.Sample(timestamp: date(minutes: $0), value: $0) }
    }

    private func reading(minutes: Double, value: Double) -> ChartInteraction.Sample {
        ChartInteraction.Sample(timestamp: date(minutes: minutes), value: value)
    }

    private func pointSeries(id: String, value: Double) -> ChartInteraction.HoverSeries {
        ChartInteraction.HoverSeries(
            id: id,
            samples: [ChartInteraction.Sample(timestamp: date(minutes: 0), value: value)],
            matchWindow: 60
        )
    }
}
