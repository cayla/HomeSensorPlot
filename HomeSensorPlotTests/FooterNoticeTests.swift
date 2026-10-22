import XCTest
@testable import HomeSensorPlot

final class FooterNoticeTests: XCTestCase {
    func testClearingExporterLeavesUnrelatedError() {
        let store = FooterNotice.other("Exporter database is locked")
        XCTAssertEqual(store.withoutExporterFailure, store)

        let exporter = FooterNotice.exporter("Exporter failed: bind")
        XCTAssertNil(exporter.withoutExporterFailure)
    }
}
