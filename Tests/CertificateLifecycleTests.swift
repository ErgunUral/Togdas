import XCTest
@testable import ToqdasCore

final class CertificateLifecycleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testValidCertificateDoesNotNeedRefresh() {
        let lifecycle = CertificateLifecycle(
            expiresAt: now.addingTimeInterval(30 * 86_400),
            now: now
        )
        XCTAssertEqual(lifecycle.state, .valid)
        XCTAssertEqual(lifecycle.daysRemaining, 30)
        XCTAssertFalse(lifecycle.needsRefresh)
        XCTAssertTrue(lifecycle.isUsable)
    }

    func testCertificateWithinRefreshWindowIsStillUsable() {
        let lifecycle = CertificateLifecycle(
            expiresAt: now.addingTimeInterval(12 * 3_600),
            now: now
        )
        XCTAssertEqual(lifecycle.state, .expiringSoon)
        XCTAssertEqual(lifecycle.daysRemaining, 1)
        XCTAssertTrue(lifecycle.needsRefresh)
        XCTAssertTrue(lifecycle.isUsable)
    }

    func testExpiredCertificateIsNotUsable() {
        let lifecycle = CertificateLifecycle(
            expiresAt: now.addingTimeInterval(-1),
            now: now
        )
        XCTAssertEqual(lifecycle.state, .expired)
        XCTAssertEqual(lifecycle.daysRemaining, 0)
        XCTAssertTrue(lifecycle.needsRefresh)
        XCTAssertFalse(lifecycle.isUsable)
    }

    func testLifecycleParsesCertificateEndDate() {
        var data = Data(repeating: 0, count: 46)
        data[40] = 30   // minute
        data[41] = 10   // hour
        data[42] = 15   // day
        data[43] = 1    // month
        data[44] = 0xeb // year low
        data[45] = 0x07 // year high => 2027
        let lifecycle = CertificateLifecycle(
            certificateBase64: data.base64EncodedString(),
            now: Date(timeIntervalSince1970: 1_800_000_000)
        )
        XCTAssertNotNil(lifecycle)
        XCTAssertEqual(lifecycle?.expiresAt, BLEProtocol.certificateEndDate(data))
    }

    func testMalformedBase64ReturnsNil() {
        XCTAssertNil(CertificateLifecycle(certificateBase64: "not base64"))
    }
}
