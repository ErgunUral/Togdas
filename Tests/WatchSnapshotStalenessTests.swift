import XCTest
@testable import ToqdasCore

final class WatchSnapshotStalenessTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testMissingTimestampIsStale() {
        XCTAssertTrue(WatchSnapshot.isStale(updatedAt: nil, now: now))
    }

    func testFreshSnapshotIsNotStale() {
        XCTAssertFalse(WatchSnapshot.isStale(updatedAt: now.timeIntervalSince1970 - 60, now: now))
    }

    func testOldSnapshotIsStale() {
        XCTAssertTrue(WatchSnapshot.isStale(
            updatedAt: now.timeIntervalSince1970 - WatchSnapshot.staleAfter - 1, now: now))
    }

    func testShorterThresholdForWatchRefresh() {
        let updatedAt = now.timeIntervalSince1970 - 40
        XCTAssertFalse(WatchSnapshot.isStale(updatedAt: updatedAt, now: now))
        XCTAssertTrue(WatchSnapshot.isStale(updatedAt: updatedAt, now: now, after: 30))
    }    /// Saat kanalındaki otomasyon eylemleri yalnız proximityOn/Off olarak
    /// çözümlenir; araç komut adları çözülmez.
    func testProximityAutomationActionParsing() {
        XCTAssertEqual(WatchProximityAutomationAction.parse("proximityOn"), .enable)
        XCTAssertEqual(WatchProximityAutomationAction.parse("proximityOff"), .disable)
        XCTAssertNil(WatchProximityAutomationAction.parse("lock"))
        XCTAssertNil(WatchProximityAutomationAction.parse("unlock"))
        XCTAssertNil(WatchProximityAutomationAction.parse("trunkOpen"))
        XCTAssertNil(WatchProximityAutomationAction.parse(""))
    }

    /// Metinler dürüst: "araç komutu gönderilmez" iddiasını taşır; VIN yok.
    func testProximityAutomationTextsAreHonestAndVINFree() {
        for action in [WatchProximityAutomationAction.enable, .disable] {
            XCTAssertTrue(action.confirmationText.contains("gönder"))
            XCTAssertTrue(action.resultText.contains("gönderilmedi"))
            XCTAssertFalse(action.confirmationText.lowercased().contains("vin"))
            XCTAssertFalse(action.resultText.lowercased().contains("vin"))
            XCTAssertEqual(WatchProximityAutomationAction.parse(action.action), action)
        }
    }
    /// Eski snapshot'ta yeni alanlar yok: kayıpsız çözümleme, alanlar nil.
    func testLegacySnapshotWithoutLastSeenFieldsDecodes() throws {
        let legacy = """
        {"vin":"VIN123","vehicleName":"T10X","locked":true,"doorCount":4,
         "openDoors":0,"ready":true,"bleState":"ready","updatedAt":100}
        """
        let snapshot = try JSONDecoder().decode(WatchSnapshot.self, from: Data(legacy.utf8))
        XCTAssertNil(snapshot.lastSeenText)
        XCTAssertNil(snapshot.sessionQualityText)
    }

    /// Yeni alanlar parmak izine girer: değişim yeni gönderim tetikler.
    func testLastSeenFieldsAffectDisplayFingerprint() {
        let base = WatchSnapshot(vin: "VIN123", vehicleName: "T10X", locked: true,
                                 doorCount: 4, openDoors: 0, trunkAjar: false,
                                 powerState: 1, ready: true, bleState: "ready",
                                 updatedAt: 100, telemetryAge: nil,
                                 batteryPercent: nil, rangeKM: nil,
                                 outsideTemperatureC: nil)
        let withLastSeen = WatchSnapshot(vin: "VIN123", vehicleName: "T10X", locked: true,
                                         doorCount: 4, openDoors: 0, trunkAjar: false,
                                         powerState: 1, ready: true, bleState: "ready",
                                         updatedAt: 100, telemetryAge: nil,
                                         batteryPercent: nil, rangeKM: nil,
                                         outsideTemperatureC: nil,
                                         lastSeenText: "3 dakika önce · BLE")
        XCTAssertNotEqual(base.displayFingerprint, withLastSeen.displayFingerprint)
    }

    /// Kilit durumu "bilinmiyor → biliniyor" geçişi ÖNEMLİ sayılır: aksi
    /// halde telemetri yokken giden snapshot saatte yapışır (30 sn
    /// darboğaz + sabit değerler parmak izini dondurur) ve saat
    /// "eski / süre bilinmiyor" gösterir; telefon bağlıyken bile.
    func testLockKnownTransitionIsImportant() {
        let unknown = WatchSnapshot(vin: "VIN123", vehicleName: "T10X", locked: nil,
                                    doorCount: 0, openDoors: 0, trunkAjar: nil,
                                    powerState: nil, ready: true, bleState: "ready",
                                    updatedAt: 100, telemetryAge: nil,
                                    batteryPercent: nil, rangeKM: nil,
                                    outsideTemperatureC: nil)
        let known = WatchSnapshot(vin: "VIN123", vehicleName: "T10X", locked: true,
                                  doorCount: 4, openDoors: 0, trunkAjar: false,
                                  powerState: 1, ready: true, bleState: "ready",
                                  updatedAt: 102, telemetryAge: 0.5,
                                  batteryPercent: nil, rangeKM: nil,
                                  outsideTemperatureC: nil)
        XCTAssertNotEqual(unknown.importantFingerprint, known.importantFingerprint)
        // Kilit değeri değişimi (true↔false) da önemli: kilit/açık sonucu
        // saatte anında görünmeli.
        let unlocked = WatchSnapshot(vin: "VIN123", vehicleName: "T10X", locked: false,
                                     doorCount: 4, openDoors: 4, trunkAjar: false,
                                     powerState: 1, ready: true, bleState: "ready",
                                     updatedAt: 104, telemetryAge: 0.5,
                                     batteryPercent: nil, rangeKM: nil,
                                     outsideTemperatureC: nil)
        XCTAssertNotEqual(known.importantFingerprint, unlocked.importantFingerprint)
    }

}
