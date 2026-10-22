import XCTest
@testable import HomeSensorPlot

final class DistributionChannelTests: XCTestCase {
    func testCertificateSummaryMapping() {
        XCTAssertEqual(
            DistributionChannel.matching(certificateSummary: "Apple Development: cayla@cay.la (3HNJPJC52C)"),
            .development
        )
        XCTAssertEqual(
            DistributionChannel.matching(certificateSummary: "TestFlight Beta Distribution"),
            .testflight
        )
        XCTAssertEqual(
            DistributionChannel.matching(certificateSummary: "Apple Distribution: Cayla (QR3XWABHT6)"),
            .appStore
        )
        XCTAssertEqual(
            DistributionChannel.matching(certificateSummary: "3rd Party Mac Developer Application: Cayla (QR3XWABHT6)"),
            .appStore
        )
        XCTAssertEqual(
            DistributionChannel.matching(certificateSummary: "Developer ID Application: Cayla (QR3XWABHT6)"),
            .developerID
        )
        XCTAssertEqual(DistributionChannel.matching(certificateSummary: "Something Else"), .unknown)
    }

    func testDatabaseFileNamesStayDistinct() {
        let channels: [DistributionChannel] = [.development, .testflight, .appStore, .developerID, .unknown]
        let names = channels.map(\.databaseFileName)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertFalse(names.contains(SampleStore.legacyDatabaseFileName))
    }
}
