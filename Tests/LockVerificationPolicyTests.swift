import XCTest
@testable import ToqdasCore

/// `LockVerificationPolicy`: kilit doğrulama penceresi telemetri kadansının
/// üstünde olmalı. Ölçüm (2026-11-17): aralıklar 1–180 sn, medyan ~60 sn.
final class LockVerificationPolicyTests: XCTestCase {
    func testWindowExceedsMeasuredMedianCadence() {
        XCTAssertGreaterThan(LockVerificationPolicy.window,
                             LockVerificationPolicy.telemetryCadenceMedian)
    }

    func testWindowCoversTypicalUpperBound() {
        // Yaygın üst sınır ~90 sn; pencere en az bunu kapsar.
        XCTAssertGreaterThanOrEqual(LockVerificationPolicy.window, 90)
    }

    func testTimeoutDetailStatesWindowHonestly() {
        let text = LockVerificationPolicy.timeoutDetail()
        XCTAssertTrue(text.contains("90 sn"))
        XCTAssertTrue(text.contains("doğrulanamadı"))
    }

    func testTimeoutDetailFollowsCustomWindow() {
        XCTAssertTrue(LockVerificationPolicy.timeoutDetail(window: 120).contains("120 sn"))
    }
}
