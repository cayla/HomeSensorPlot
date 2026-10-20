import XCTest
@testable import SensorPlot

final class SeriesDownsampleTests: XCTestCase {
    func testShortSeriesUnchanged() {
        let samples = (0..<5).map { sample(id: Int64($0), index: $0) }
        XCTAssertEqual(SeriesDownsample.stride(samples, maxPoints: 10).map(\.id), samples.map(\.id))
    }

    func testKeepsFirstAndLast() {
        let samples = (0..<100).map { sample(id: Int64($0), index: $0) }
        let out = SeriesDownsample.stride(samples, maxPoints: 10)
        XCTAssertEqual(out.count, 10)
        XCTAssertEqual(out.first?.id, 0)
        XCTAssertEqual(out.last?.id, 99)
    }

    private func sample(id: Int64, index: Int) -> SamplePoint {
        SamplePoint(
            id: id,
            sensorID: "s",
            timestamp: Date(timeIntervalSince1970: Double(index)),
            value: Double(index)
        )
    }
}
