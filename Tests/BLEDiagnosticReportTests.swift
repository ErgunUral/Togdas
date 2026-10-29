import XCTest
@testable import ToqdasCore

final class BLEDiagnosticReportTests: XCTestCase {
    private func event(_ message: String, secondsAgo: TimeInterval, now: Date) -> BLEDiagnosticEvent {
        BLEDiagnosticEvent(id: UUID(), timestamp: now.addingTimeInterval(-secondsAgo), message: message)
    }

    func testSummarizesRecentScanConnectionAndFailureEvents() {
        let now = Date(timeIntervalSince1970: 20_000)
        let events = [
            event("gatt_scan_start · hızlı tarama 12 sn", secondsAgo: 20, now: now),
            event("scan_rotate · hızlı tarama sonuçsuz", secondsAgo: 10, now: now),
            event("BLE bağlantısı kuruldu; servisler keşfediliyor", secondsAgo: 9, now: now),
            event("Bağlantı durumu: Komut hazır", secondsAgo: 8, now: now),
            event("BLEDisconnected · araç bağlantıyı kapattı", secondsAgo: 5, now: now),
            event("failure_kind · connection_timeout · sinyal zayıf", secondsAgo: 4, now: now),
            event("vehicleKeyMissing · araç doğrulama anahtarı gönderilmedi", secondsAgo: 3, now: now),
            event("telemetry_verify_failed · imza/biçim doğrulaması başarısız", secondsAgo: 2, now: now),
            event("gatt_rssi_stale · proximity geçişi iptal edildi", secondsAgo: 1, now: now),
            event("proximity_fresh_cycle · BLE oturumu değişti", secondsAgo: 0, now: now)
        ]

        let report = BLEDiagnosticReport(events: events, now: now)
        XCTAssertEqual(report.events.count, events.count)
        XCTAssertEqual(report.scanStarts, 1)
        XCTAssertEqual(report.scanRotations, 1)
        XCTAssertEqual(report.successfulConnections, 1)
        XCTAssertEqual(report.readyTransitions, 1)
        XCTAssertEqual(report.disconnects, 1)
        XCTAssertEqual(report.failureCounts[.signal], 1)
        XCTAssertEqual(report.missingVehicleKeys, 1)
        XCTAssertEqual(report.telemetryVerificationFailures, 1)
        XCTAssertEqual(report.staleGATTRSSISamples, 1)
        XCTAssertEqual(report.proximityFreshCycleResets, 1)
    }

    func testRSSIStatisticsParseOnlyDatedRSSIValues() {
        let now = Date()
        let events = [
            event("Araç bulundu; RSSI -93 dBm", secondsAgo: 30, now: now),
            event("Bağlı RSSI: -89 dBm", secondsAgo: 20, now: now),
            event("BLEDisconnected · son RSSI -91 dBm", secondsAgo: 10, now: now),
            event("Bluetooth hazır", secondsAgo: 5, now: now)
        ]
        let report = BLEDiagnosticReport(events: events, now: now)
        XCTAssertEqual(report.rssiSamples, [-93, -89, -91])
        XCTAssertEqual(report.minimumRSSI, -93)
        XCTAssertEqual(report.maximumRSSI, -89)
        XCTAssertEqual(report.averageRSSI ?? 0, -91, accuracy: 0.01)
        XCTAssertEqual(report.latestRSSI, -91)
    }

    func testWindowExcludesEventsOlderThanOneHourAndFutureEvents() {
        let now = Date(timeIntervalSince1970: 50_000)
        let events = [
            event("gatt_scan_start · hızlı", secondsAgo: 100, now: now),
            event("gatt_scan_start · eski", secondsAgo: 3_601, now: now),
            BLEDiagnosticEvent(id: UUID(), timestamp: now.addingTimeInterval(1), message: "gelecek")
        ]
        let report = BLEDiagnosticReport(events: events, now: now)
        XCTAssertEqual(report.events.count, 1)
        XCTAssertEqual(report.scanStarts, 1)
    }

    func testLegacyDisconnectsAreClassifiedOnce() {
        let now = Date()
        let report = BLEDiagnosticReport(events: [
            event("BLEDisconnected · bağlantı zaman aşımı (sinyal zayıf)", secondsAgo: 1, now: now),
            event("BLEDisconnected · araç bağlantıyı kapattı", secondsAgo: 0, now: now)
        ], now: now)
        XCTAssertEqual(report.disconnects, 2)
        XCTAssertEqual(report.failureCounts[.signal], 1)
        XCTAssertEqual(report.failureCounts[.peerClosed], 1)
        XCTAssertEqual(report.totalFailures, 2)
    }

    func testShareTextContainsOnlyAggregateReport() {
        let now = Date()
        let report = BLEDiagnosticReport(events: [
            event("Bağlı RSSI: -90 dBm", secondsAgo: 1, now: now)
        ], now: now)
        XCTAssertTrue(report.shareText.contains("son 60 dk"))
        XCTAssertTrue(report.shareText.contains("RSSI örnek: 1"))
        XCTAssertFalse(report.shareText.contains("NL1CSU0P60G064536"))
    }
}
