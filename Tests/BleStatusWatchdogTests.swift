import XCTest
@testable import ToqdasCore

/// `BleStatusWatchdog`: Android .57 `j4` paritesi — 15 sn eşikleri,
/// oturum değişiminde sıfırlama, 3 deneme eşiği. Etiketler yalnız
/// gösterim/günlük amaçlıdır.
final class BleStatusWatchdogTests: XCTestCase {
    private var clock: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 12))!
    }
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Istanbul")!
        return calendar
    }()

    private func offset(_ seconds: Double) -> Date {
        clock.addingTimeInterval(seconds)
    }

    /// Sıfır gözcü; test amaçlı yardımcı.
    private func watchdog0() -> BleStatusWatchdog { BleStatusWatchdog() }

    func testStaleTelemetryLabel() {
        var watchdog = BleStatusWatchdog()
        // Telemetri yaşı 15 sn'yi aştı → stale etiketi.
        XCTAssertEqual(
            watchdog.reason(session: 1, now: offset(20), telemetryAge: 15.5),
            "stale_telemetry_reconnect"
        )
    }

    func testFreshTelemetryHasNoLabel() {
        var watchdog = BleStatusWatchdog()
        XCTAssertEqual(watchdog.reason(session: 1, now: offset(10), telemetryAge: 15.0), "")
        XCTAssertEqual(watchdog.reason(session: 1, now: offset(10), telemetryAge: 2), "")
    }

    func testFirstStatusTimeoutWithoutTelemetry() {
        var watchdog = watchdog0()
        // İlk çağrı oturumu başlatır (startedAt = offset(0)); henüz boş.
        XCTAssertEqual(watchdog.reason(session: 1, now: offset(0), telemetryAge: nil), "")
        // İlk durum 15 sn içinde gelmedi → timeout etiketi.
        XCTAssertEqual(
            watchdog.reason(session: 1, now: offset(15), telemetryAge: nil),
            "first_status_timeout"
        )
    }

    func testSessionChangeResetsTimers() {
        var watchdog = watchdog0()
        // Oturum 1'de bekleme başladı (offset(0)); 15 sn geçti → timeout...
        XCTAssertEqual(watchdog.reason(session: 1, now: offset(0), telemetryAge: nil), "")
        XCTAssertEqual(watchdog.reason(session: 1, now: offset(15), telemetryAge: nil), "first_status_timeout")
        // ...yeni oturum sayacı sıfırlar: hemen sonra yine boş.
        XCTAssertEqual(watchdog.reason(session: 2, now: offset(16), telemetryAge: nil), "")
    }

    func testSameSessionKeepsStart() {
        var watchdog = watchdog0()
        _ = watchdog.reason(session: 1, now: offset(14), telemetryAge: nil)
        // Aynı oturum, başlangıç korunur: toplam 15 sn'yi doldurunca etiket gelir.
        XCTAssertEqual(watchdog.reason(session: 1, now: offset(29.5), telemetryAge: nil), "first_status_timeout")
    }

    func testRecordAttemptThresholdMatchesAndroid() {
        var watchdog = BleStatusWatchdog()
        XCTAssertFalse(watchdog.recordAttempt())
        XCTAssertFalse(watchdog.recordAttempt())
        XCTAssertTrue(watchdog.recordAttempt())
        watchdog.reset()
        XCTAssertFalse(watchdog.recordAttempt())
    }
}
