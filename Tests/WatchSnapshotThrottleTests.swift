import XCTest
@testable import ToqdasCore

/// Saat snapshot darboğazı: değişmemiş değer gönderilmez; gösterim
/// değişimi minimum aralığa sıkıştırılır; önemli alan (bağlantı/komut)
/// değişimi her zaman anında geçer.
final class WatchSnapshotThrottleTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_000_000)

    func testFirstCallAlwaysSends() {
        var throttle = WatchSnapshotThrottle()
        XCTAssertTrue(throttle.shouldSend(now: base, fingerprint: "a", importantFingerprint: "A"))
    }

    func testUnchangedValueIsSkipped() {
        var throttle = WatchSnapshotThrottle()
        throttle.shouldSend(now: base, fingerprint: "a", importantFingerprint: "A")
        XCTAssertFalse(throttle.shouldSend(now: base.addingTimeInterval(120), fingerprint: "a", importantFingerprint: "A"))
    }

    func testDisplayChangeInsideIntervalIsHeld() {
        var throttle = WatchSnapshotThrottle()
        throttle.shouldSend(now: base, fingerprint: "a", importantFingerprint: "A")
        // 10 sn sonra gösterim değeri değişti: minimum aralık dolmadan gitmez.
        XCTAssertFalse(throttle.shouldSend(now: base.addingTimeInterval(10), fingerprint: "b", importantFingerprint: "A"))
        // 31 sn sonra aynı değişim gider.
        XCTAssertTrue(throttle.shouldSend(now: base.addingTimeInterval(31), fingerprint: "b", importantFingerprint: "A"))
    }

    func testImportantChangeBypassesInterval() {
        var throttle = WatchSnapshotThrottle()
        throttle.shouldSend(now: base, fingerprint: "a", importantFingerprint: "A")
        // 1 sn sonra komut sonucu değişti: darboğaza takılmadan gider.
        XCTAssertTrue(throttle.shouldSend(now: base.addingTimeInterval(1), fingerprint: "b", importantFingerprint: "B"))
        // Gönderim sonrası aynı değer tekrar gitmez.
        XCTAssertFalse(throttle.shouldSend(now: base.addingTimeInterval(2), fingerprint: "b", importantFingerprint: "B"))
    }

    /// Önemli alan değişmediğinde önemli parmak izi kaydı sabit kalır;
    /// gösterim gönderimi yine aralık kurallarına tabidir.
    func testImportantStabilityKeepsDisplayRules() {
        var throttle = WatchSnapshotThrottle()
        throttle.shouldSend(now: base, fingerprint: "a", importantFingerprint: "A")
        XCTAssertFalse(throttle.shouldSend(now: base.addingTimeInterval(5), fingerprint: "b", importantFingerprint: "A"))
        XCTAssertTrue(throttle.shouldSend(now: base.addingTimeInterval(35), fingerprint: "c", importantFingerprint: "A"))
    }
}
