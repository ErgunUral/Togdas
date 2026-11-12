import XCTest
@testable import ToqdasCore

/// `ProximitySettings`: VIN bazlı yakınlık kalıcılığı (byte-identical
/// anahtar biçimleri, nil yazımı = kaydı kaldırma).
final class ProximitySettingsTests: XCTestCase {
    private final class MemoryStore: KeyValueStore {
        var values: [String: Any] = [:]
        func string(forKey key: String) -> String? { values[key] as? String }
        func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
        func object(forKey key: String) -> Any? { values[key] }
        func integer(forKey key: String) -> Int { values[key] as? Int ?? 0 }
        func data(forKey key: String) -> Data? { values[key] as? Data }
        func set(_ value: Any?, forKey key: String) {
            if let value { values[key] = value } else { values.removeValue(forKey: key) }
        }
        func removeObject(forKey key: String) { values.removeValue(forKey: key) }
    }

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Istanbul")!
        return calendar
    }()

    private func date(_ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: hour))!
    }

    func testKeyFormatsMatchPreviousLiterals() {
        // Byte-identical garanti: literaller App'ten taşındı; değişirse
        // mevcut kullanıcı verisi kaybolur.
        XCTAssertEqual(ProximitySettings.profileKey("V1"), "toqdas.proximity.profile.V1")
        XCTAssertEqual(ProximitySettings.nearKey("V1"), "toqdas.proximity.near.V1")
        XCTAssertEqual(ProximitySettings.farKey("V1"), "toqdas.proximity.far.V1")
        XCTAssertEqual(ProximitySettings.autoOffEnabledKey("V1"), "toqdas.proximity.autoOff.enabled.V1")
        XCTAssertEqual(ProximitySettings.autoOffMinutesKey("V1"), "toqdas.proximity.autoOff.minutes.V1")
        XCTAssertEqual(ProximitySettings.autoOffCustomKey("V1"), "toqdas.proximity.autoOff.custom.V1")
        XCTAssertEqual(ProximitySettings.autoOffDeadlineKey("V1"), "toqdas.proximity.autoOff.deadline.V1")
    }

    func testProfileRoundTrip() {
        let settings = ProximitySettings(store: MemoryStore())
        XCTAssertNil(settings.profile(vin: "V1"))
        settings.setProfileRaw(ProximityProfile.allCases[0].rawValue, vin: "V1")
        XCTAssertEqual(settings.profile(vin: "V1"), ProximityProfile.allCases[0])
        // Bilinmeyen ham değer: nil (DashboardView restore davranışıyla aynı).
        settings.setProfileRaw("BILINMEYEN", vin: "V1")
        XCTAssertNil(settings.profile(vin: "V1"))
    }

    func testCalibrationSamplesAndClear() {
        let settings = ProximitySettings(store: MemoryStore())
        XCTAssertNil(settings.nearSample(vin: "V1"))
        settings.setNearSample(-52, vin: "V1")
        settings.setFarSample(-78, vin: "V1")
        XCTAssertEqual(settings.nearSample(vin: "V1"), -52)
        XCTAssertEqual(settings.farSample(vin: "V1"), -78)

        settings.clearCalibration(vin: "V1")
        XCTAssertNil(settings.nearSample(vin: "V1"))
        XCTAssertNil(settings.farSample(vin: "V1"))
    }

    func testAutoOffPersistence() {
        let settings = ProximitySettings(store: MemoryStore())
        XCTAssertFalse(settings.autoOffEnabled(vin: "V1"))
        XCTAssertNil(settings.autoOffMinutes(vin: "V1"))
        XCTAssertNil(settings.autoOffCustomMinutes(vin: "V1"))
        XCTAssertNil(settings.autoOffDeadline(vin: "V1"))

        settings.setAutoOffEnabled(true, vin: "V1")
        settings.setAutoOffMinutes(15, vin: "V1")
        settings.setAutoOffCustomMinutes(90, vin: "V1")
        settings.setAutoOffDeadline(date(13), vin: "V1")

        XCTAssertTrue(settings.autoOffEnabled(vin: "V1"))
        XCTAssertEqual(settings.autoOffMinutes(vin: "V1"), 15)
        XCTAssertEqual(settings.autoOffCustomMinutes(vin: "V1"), 90)
        XCTAssertEqual(settings.autoOffDeadline(vin: "V1"), date(13))

        // nil yazımı = kaydı kaldırma (removeObject semantiği).
        settings.setAutoOffDeadline(nil, vin: "V1")
        XCTAssertNil(settings.autoOffDeadline(vin: "V1"))
        settings.setAutoOffMinutes(nil, vin: "V1")
        XCTAssertNil(settings.autoOffMinutes(vin: "V1"))
    }

    func testVinsAreIsolated() {
        let settings = ProximitySettings(store: MemoryStore())
        settings.setNearSample(-50, vin: "V1")
        XCTAssertNil(settings.nearSample(vin: "V2"))
    }
}
