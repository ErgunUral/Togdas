import XCTest
@testable import ToqdasCore

/// Senaryolar rehberi içerik modelinin testleri: 7 bölüm bütünlüğü,
/// senaryo şablonunun doluluğu, kritik senaryoların varlığı ve canlı
/// durum rozetlerinin türetimi (bilgi yok → nötr; asla 0/yanlış varsayılmaz).
final class ScenarioContentTests: XCTestCase {

    // MARK: - Katalog bütünlüğü

    func testEverySectionHasAGroup() {
        XCTAssertEqual(ScenarioSection.allCases.count, 8)
        XCTAssertEqual(ScenarioCatalog.groups.count, ScenarioSection.allCases.count)
        XCTAssertEqual(ScenarioCatalog.groups.first?.section, .setup, "Kurulum bölümü ilk sırada olmalı")
        for section in ScenarioSection.allCases {
            XCTAssertNotNil(ScenarioCatalog.group(for: section), "\(section) bölümü eksik")
        }
    }

    func testItemFieldsAreFilledAndIdsUnique() {
        var seen = Set<String>()
        for group in ScenarioCatalog.groups {
            XCTAssertFalse(group.items.isEmpty, "\(group.section) boş")
            for item in group.items {
                XCTAssertFalse(item.title.isEmpty)
                XCTAssertFalse(item.trigger.isEmpty)
                XCTAssertFalse(item.effect.isEmpty)
                XCTAssertFalse(item.requirement.isEmpty)
                XCTAssertFalse(item.onBreak.isEmpty)
                let unique = "\(group.section.rawValue)/\(item.id)"
                XCTAssertTrue(seen.insert(unique).inserted, "id tekrarı: \(unique)")
            }
        }
    }

    func testUnknownSectionHasNoItem() {
        XCTAssertNil(ScenarioCatalog.item(section: .link, id: "yok-öyle-bir-senaryo"))
    }

    // MARK: - Kurulum bölümü

    func testSetupCoversLoginPermissionsAndChannels() {
        let ids = Set((ScenarioCatalog.group(for: .setup)?.items ?? []).map(\.id))
        XCTAssertEqual(
            ids,
            [
                "setup-login", "setup-permissions", "setup-bluetooth",
                "setup-widget", "setup-watch", "setup-geofence",
            ]
        )
    }

    func testBluetoothSetupReferencesTheFiveStepGuide() {
        let item = ScenarioCatalog.item(section: .setup, id: "setup-bluetooth")
        XCTAssertNotNil(item)
        // Tetik metni BLESetupGuideSheet'i açan gerçek düğme adıyla uyumlu olmalı.
        XCTAssertTrue(item?.trigger.contains("Kurulumu adım adım dinle") == true)
        // 5 adım özeti son adımı (yeşil 'Komut hazır') içermeli.
        XCTAssertTrue(item?.effect.contains("Komut hazır") == true)
    }

    func testGeofenceSetupMatchesReadinessWording() {
        let item = ScenarioCatalog.item(section: .setup, id: "setup-geofence")
        XCTAssertNotNil(item)
        // `GeofenceReadiness.message` ile uyumlu: "Her zaman" izni şart.
        XCTAssertTrue(item?.requirement.contains("Her zaman") == true)
    }

    // MARK: - Kritik senaryolar

    func testProximityRulesAreDocumented() {
        // Android .57 paritesi: kalibrasyon şartı, tek bilet, 30 sn guard,
        // arka plan sınırı ve uzak taban şartı rehberde olmalı.
        let ids = Set((ScenarioCatalog.group(for: .proximity)?.items ?? []).map(\.id))
        XCTAssertEqual(
            ids,
            [
                "proximity-calibration", "proximity-near", "proximity-lock",
                "proximity-confirm", "proximity-ticket", "proximity-foreground",
                "proximity-autooff",
            ]
        )
    }

    func testCalibrationSeparationMatchesCore() {
        let item = ScenarioCatalog.item(section: .proximity, id: "proximity-calibration")
        XCTAssertNotNil(item)
        // Rehber metni `ProximityCalibration.minimumSeparation` ile uyumlu kalmalı.
        XCTAssertTrue(
            item?.requirement.contains("\(ProximityCalibration.minimumSeparation)") == true,
            "14 dB şartı metinde geçmiyor"
        )
    }

    func testTroubleshootingCoversKnownPairingStates() {
        let ids = Set((ScenarioCatalog.group(for: .troubleshooting)?.items ?? []).map(\.id))
        XCTAssertTrue(ids.contains("trouble-pairing-wait"), "vehicleKeyMissing senaryosu eksik")
        XCTAssertTrue(ids.contains("trouble-pairing-lost"), "pairing_lost senaryosu eksik")
        XCTAssertTrue(ids.contains("trouble-lock-verify"), "kilit teyidi senaryosu eksik")
    }

    func testWatchAndWidgetDeclareReadOnly() {
        let item = ScenarioCatalog.item(section: .watchWidget, id: "watch-readonly")
        XCTAssertNotNil(item)
    }

    // MARK: - Canlı durum rozetleri

    func testUnknownInputsProduceNeutralBadges() {
        let badges = ScenarioLiveStatus.unknown.badges
        XCTAssertEqual(badges.count, 4)
        XCTAssertEqual(badges.map(\.id), ["live-ble", "live-automation", "live-calibration", "live-telemetry"])
        for badge in badges {
            XCTAssertEqual(badge.tone, .neutral, "\(badge.id) nötr olmalı")
            XCTAssertEqual(badge.value, "bilgi yok", "\(badge.id) 'bilgi yok' demeli")
        }
    }

    func testPositiveAndNegativeDerivation() {
        var status = ScenarioLiveStatus.unknown
        status.bleReady = true
        status.calibrationValid = false
        status.telemetryFresh = false
        let badges = status.badges
        XCTAssertEqual(badges[0].tone, .positive)
        XCTAssertEqual(badges[0].value, "Komut hazır")
        XCTAssertEqual(badges[1].tone, .neutral) // otomasyon hâlâ bilinmiyor
        XCTAssertEqual(badges[2].tone, .warning)
        XCTAssertEqual(badges[2].value, "Yok")
        XCTAssertEqual(badges[3].tone, .warning)
        XCTAssertEqual(badges[3].value, "Eski")
    }

    func testAllPositiveDerivation() {
        let status = ScenarioLiveStatus(
            bleReady: true,
            automationEnabled: true,
            calibrationValid: true,
            telemetryFresh: true
        )
        for badge in status.badges {
            XCTAssertEqual(badge.tone, .positive, "\(badge.id) pozitif olmalı")
        }
    }
}
