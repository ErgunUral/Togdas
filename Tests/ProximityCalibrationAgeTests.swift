import XCTest
@testable import ToqdasCore

/// `ProximityCalibrationAge`: kalibrasyon eskime uyarısı. Uyarı
/// bilgilendirmedir; otomasyonu kapatmaz ve komut göndermez.
final class ProximityCalibrationAgeTests: XCTestCase {
    private var calendar: Calendar!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    }

    func testNilSavedAtNeverWarns() {
        // Hiç kalibre edilmemiş ≠ eski: kart zaten ölçüm ister.
        XCTAssertFalse(ProximityCalibrationAge.needsRefresh(nil, now: now, calendar: calendar))
    }

    func testFreshCalibrationDoesNotWarn() {
        let saved = calendar.date(byAdding: .day, value: -29, to: now)!
        XCTAssertFalse(ProximityCalibrationAge.needsRefresh(saved, now: now, calendar: calendar))
    }

    func testThirtyDaysTriggersWarning() {
        let saved = calendar.date(byAdding: .day, value: -30, to: now)!
        XCTAssertTrue(ProximityCalibrationAge.needsRefresh(saved, now: now, calendar: calendar))
        XCTAssertEqual(ProximityCalibrationAge.daysSince(saved, now: now, calendar: calendar), 30)
    }

    func testFutureDateIsClampedToZero() {
        let future = calendar.date(byAdding: .day, value: 3, to: now)!
        XCTAssertEqual(ProximityCalibrationAge.daysSince(future, now: now, calendar: calendar), 0)
        XCTAssertFalse(ProximityCalibrationAge.needsRefresh(future, now: now, calendar: calendar))
    }

    func testMessageStatesItIsAdvisory() {
        let text = ProximityCalibrationAge.message(days: 45)
        XCTAssertTrue(text.contains("45 gün"))
        XCTAssertTrue(text.lowercased().contains("yenile"))
    }

    // MARK: Kalıcılık

    func testSavedAtRoundTripAndClear() {
        let defaults = UserDefaults(suiteName: "test.proximityCalibrationAge")!
        defaults.removePersistentDomain(forName: "test.proximityCalibrationAge")
        let settings = ProximitySettings(store: defaults)
        XCTAssertNil(settings.calibrationSavedAt(vin: "V"))

        settings.setCalibrationSavedAt(now, vin: "V")
        XCTAssertEqual(settings.calibrationSavedAt(vin: "V"), now)

        settings.clearCalibration(vin: "V")
        XCTAssertNil(settings.calibrationSavedAt(vin: "V"))
    }
}
