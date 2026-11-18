import XCTest
@testable import ToqdasCore

/// Pano öncelik motoru: sıralama, üst sınır ve dürüst metinler.
final class DashboardPriorityEngineTests: XCTestCase {

    func testQuietInputsProduceNoCards() {
        XCTAssertTrue(DashboardPriorities.make(.init()).isEmpty)
    }

    func testCriticalAuxiliaryComesFirst() {
        var inputs = DashboardPriorities.Inputs()
        inputs.auxiliaryPercent = 18
        inputs.telemetryAge = 20
        inputs.powerState = 4
        let items = DashboardPriorities.make(inputs)
        XCTAssertEqual(items.first?.kind, .auxiliaryCritical)
        XCTAssertEqual(items.first?.severity, .critical)
        XCTAssertTrue(items.first?.title.contains("%18") == true)
    }

    func testAuxiliaryWarningBandIsSeparateFromCritical() {
        var inputs = DashboardPriorities.Inputs()
        inputs.auxiliaryPercent = 34
        let item = DashboardPriorities.make(inputs).first
        XCTAssertEqual(item?.severity, .warning)
        XCTAssertTrue(item?.detail.contains("%40") == true)
    }

    func testMissingAuxiliaryValueProducesNoCard() {
        // Eksik veri 0'a sıkıştırılmaz → uyarı da uydurulmaz.
        var inputs = DashboardPriorities.Inputs()
        inputs.auxiliaryPercent = nil
        XCTAssertFalse(DashboardPriorities.make(inputs).contains { $0.kind == .auxiliaryCritical })
    }

    func testMaximumThreeCardsAndStableOrder() {
        var inputs = DashboardPriorities.Inputs()
        inputs.linkReady = false
        inputs.auxiliaryPercent = 10
        inputs.commandUnverifiedDetail = "Bağlantı komuttan önce kapandı."
        inputs.openDoorCount = 1
        inputs.telemetryAge = 400
        inputs.weakSignal = true
        inputs.chargingActive = true
        inputs.chargingTargetRemaining = 20
        inputs.powerState = 4
        let items = DashboardPriorities.make(inputs)
        XCTAssertEqual(items.count, DashboardPriorities.maximumItems)
        // Kritik önce; eşit ciddiyette sabit sıra (bağlantı → doğrulanamadı → kapı).
        XCTAssertEqual(items.map(\.kind), [.auxiliaryCritical, .connectionLost, .lockUnverified])
    }

    func testConnectionLostTextIsHonestAndNeverClaimsReason() {
        var inputs = DashboardPriorities.Inputs()
        inputs.linkReady = false
        inputs.lastSeenText = "4 dk önce"
        let item = DashboardPriorities.make(inputs).first
        XCTAssertEqual(item?.kind, .connectionLost)
        XCTAssertTrue(item?.detail.contains("4 dk önce") == true)
        XCTAssertTrue(item?.detail.contains("otomatik yeniden deneme yok") == true)
        XCTAssertFalse(item?.detail.contains("reddetti") == true)
    }

    func testNoDataYetDoesNotInventLastSeen() {
        var inputs = DashboardPriorities.Inputs()
        inputs.linkReady = false
        let item = DashboardPriorities.make(inputs).first
        XCTAssertTrue(item?.detail.contains("Henüz araç verisi alınmadı") == true)
    }

    func testReadyOnlyFromPowerStateFour() {
        var inputs = DashboardPriorities.Inputs()
        inputs.powerState = 3
        XCTAssertFalse(DashboardPriorities.make(inputs).contains { $0.kind == .readyToDrive })
        inputs.powerState = 4
        let item = DashboardPriorities.make(inputs).first
        XCTAssertEqual(item?.kind, .readyToDrive)
        XCTAssertTrue(item?.detail.contains("imzalı telemetriden") == true)
    }

    func testChargingTargetNeedsActiveSessionAndKnownRemaining() {
        var inputs = DashboardPriorities.Inputs()
        inputs.chargingActive = false
        inputs.chargingTargetRemaining = 15
        XCTAssertFalse(DashboardPriorities.make(inputs).contains { $0.kind == .chargingTarget })

        inputs.chargingActive = true
        inputs.chargingEtaText = "42 dk"
        let item = DashboardPriorities.make(inputs).first
        XCTAssertEqual(item?.kind, .chargingTarget)
        XCTAssertTrue(item?.detail.contains("42 dk") == true)
    }

    func testChargingTargetWithoutEtaSaysDataIsMissing() {
        var inputs = DashboardPriorities.Inputs()
        inputs.chargingActive = true
        inputs.chargingTargetRemaining = 9
        let item = DashboardPriorities.make(inputs).first
        XCTAssertTrue(item?.detail.contains("yeterli veri yok") == true)
    }

    func testTelemetryFreshnessBands() {
        var inputs = DashboardPriorities.Inputs()
        inputs.telemetryAge = 30
        XCTAssertFalse(DashboardPriorities.make(inputs).contains { $0.kind == .telemetryStale },
                       "15–45 sn normal dönem arası, kart üretmemeli")
        inputs.telemetryAge = 60
        XCTAssertEqual(DashboardPriorities.make(inputs).first?.severity, .info)
        inputs.telemetryAge = 600
        XCTAssertEqual(DashboardPriorities.make(inputs).first?.severity, .warning)
    }

    func testUnverifiedCommandUsesMeasuredDetailOnly() {
        var inputs = DashboardPriorities.Inputs()
        inputs.commandUnverifiedDetail = "Bağlantı kapandı; kilitleme doğrulanamadı."
        let item = DashboardPriorities.make(inputs).first
        XCTAssertEqual(item?.kind, .lockUnverified)
        XCTAssertEqual(item?.detail, "Bağlantı kapandı; kilitleme doğrulanamadı.")
    }

    func testDoorContextExplainsLockBehaviourWithoutBlamingVehicle() {
        var inputs = DashboardPriorities.Inputs()
        inputs.trunkAjar = true
        let item = DashboardPriorities.make(inputs).first
        XCTAssertEqual(item?.title, "Bagaj açık")
        XCTAssertTrue(item?.detail.contains("uygulamayabilir") == true)
        XCTAssertFalse(item?.detail.contains("reddetti") == true)
    }
}
