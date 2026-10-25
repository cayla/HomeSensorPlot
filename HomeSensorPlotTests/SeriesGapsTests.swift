import XCTest
@testable import HomeSensorPlot

final class SeriesGapsTests: XCTestCase {
    func testEvenSeriesStaysOneSegment() {
        let layout = SeriesGaps.layout(timestamps: dates(minutes: [0, 60, 120, 180, 240]))
        XCTAssertEqual(layout.segments, [0, 0, 0, 0, 0])
        XCTAssertEqual(layout.matchWindow, 75 * 60, accuracy: 0.001)
    }

    func testHoleWiderThanUsualSpacingBreaks() {
        // Hourly samples, then a 6h jump. Median stays 1h; 6h is wider than 2.5h.
        let layout = SeriesGaps.layout(timestamps: dates(minutes: [0, 60, 120, 480, 540]))
        XCTAssertEqual(layout.segments, [0, 0, 0, 1, 1])
        XCTAssertEqual(layout.matchWindow, 75 * 60, accuracy: 0.001)
    }

    func testSingleMissedSampleStaysConnected() {
        // 2h between hourly points is one missed sample, under the 2.5h threshold.
        let layout = SeriesGaps.layout(timestamps: dates(minutes: [0, 60, 180, 240]))
        XCTAssertEqual(layout.segments, [0, 0, 0, 0])
    }

    func testGapEqualToThresholdStaysConnected() {
        let threshold = 2.5 * 60 * 60
        let layout = SeriesGaps.layout(timestamps: [
            Date(timeIntervalSince1970: 0),
            Date(timeIntervalSince1970: 60 * 60),
            Date(timeIntervalSince1970: 60 * 60 + threshold),
            Date(timeIntervalSince1970: 2 * 60 * 60 + threshold),
        ])
        XCTAssertEqual(layout.segments, [0, 0, 0, 0])
    }

    func testTwoPointSeriesDoesNotBreak() {
        // The only gap is the median, so it cannot be "wider than usual".
        let layout = SeriesGaps.layout(timestamps: dates(minutes: [0, 600]))
        XCTAssertEqual(layout.segments, [0, 0])
    }

    func testDownsampledEndsOfAHoleStayInDifferentSegments() {
        // Hourly samples with a 6h hole. A stride that keeps only the ends
        // must not treat those two points as one line.
        let full = dates(minutes: [0, 60, 120, 480, 540])
        let layout = SeriesGaps.layout(timestamps: full)
        XCTAssertEqual(SeriesGaps.segmentIndex(at: full[0], timestamps: full, segments: layout.segments), 0)
        XCTAssertEqual(SeriesGaps.segmentIndex(at: full[4], timestamps: full, segments: layout.segments), 1)
        let insideHole = Date(timeIntervalSince1970: 300 * 60)
        XCTAssertNil(SeriesGaps.segmentIndex(at: insideHole, timestamps: full, segments: layout.segments))
        let connected = Date(timeIntervalSince1970: 90 * 60)
        XCTAssertEqual(SeriesGaps.segmentIndex(at: connected, timestamps: full, segments: layout.segments), 0)
    }

    func testLonePointInASplitSegmentNeedsADot() {
        XCTAssertEqual(SeriesGaps.lonePointIndexes(segmentIDs: ["room#0", "room#0", "room#1"]), [2])
        XCTAssertEqual(SeriesGaps.lonePointIndexes(segmentIDs: ["room#0"]), [0])
        XCTAssertTrue(SeriesGaps.lonePointIndexes(segmentIDs: ["room#0", "room#0"]).isEmpty)
        XCTAssertEqual(SeriesGaps.lonePointIndexes(segmentIDs: ["room#off-0", "room#off-1"]), [0, 1])
    }

    func testSinglePointUsesFallbackWindow() {
        let layout = SeriesGaps.layout(timestamps: dates(minutes: [10]))
        XCTAssertEqual(layout.segments, [0])
        XCTAssertEqual(layout.matchWindow, SeriesGaps.fallbackMatchWindow)
    }

    private func dates(minutes: [Double]) -> [Date] {
        minutes.map { Date(timeIntervalSince1970: $0 * 60) }
    }
}
