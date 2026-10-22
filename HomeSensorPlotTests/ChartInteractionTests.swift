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

    private func date(minutes: Double) -> Date {
        Date(timeIntervalSince1970: minutes * 60)
    }

    private func samples(minutes: [Double]) -> [ChartInteraction.Sample] {
        minutes.map { ChartInteraction.Sample(timestamp: date(minutes: $0), value: $0) }
    }

    private func pointSeries(id: String, value: Double) -> ChartInteraction.HoverSeries {
        ChartInteraction.HoverSeries(
            id: id,
            samples: [ChartInteraction.Sample(timestamp: date(minutes: 0), value: value)],
            matchWindow: 60
        )
    }
}
