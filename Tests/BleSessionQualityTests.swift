import XCTest
@testable import ToqdasCore

final class BleSessionQualityTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    func testSummarizesSignalSamples() {
        let session = BleSessionQuality.make(
            startedAt: start, endedAt: start.addingTimeInterval(30),
            samples: [-88, -91, -96, -90], endReason: "araç oturumu kapattı")

        XCTAssertEqual(session.duration, 30)
        XCTAssertEqual(session.minRSSI, -96)
        XCTAssertEqual(session.maxRSSI, -88)
        XCTAssertEqual(session.averageRSSI, -91.3)
        XCTAssertEqual(session.endReason, "araç oturumu kapattı")
    }

    func testMissingSamplesStayUnknown() {
        let session = BleSessionQuality.make(
            startedAt: start, endedAt: start.addingTimeInterval(3),
            samples: [], endReason: "zaman aşımı")
        XCTAssertNil(session.minRSSI)
        XCTAssertNil(session.averageRSSI)
    }

    func testStoreKeepsNewestSessions() {
        let suite = "test.sessionQuality"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = BleSessionQualityStore(defaults: defaults)

        for index in 0..<(BleSessionQualityStore.limit + 3) {
            store.append(BleSessionQuality.make(
                startedAt: start, endedAt: start.addingTimeInterval(1),
                samples: [-80 - index], endReason: "oturum \(index)"))
        }
        let sessions = store.load()
        XCTAssertEqual(sessions.count, BleSessionQualityStore.limit)
        XCTAssertEqual(sessions.last?.endReason, "oturum \(BleSessionQualityStore.limit + 2)")
        defaults.removePersistentDomain(forName: suite)
    }

func testSummaryAggregatesSessions() {
        let make: (TimeInterval, Int, String) -> BleSessionQuality = { duration, rssi, reason in
            BleSessionQuality.make(
                startedAt: self.start, endedAt: self.start.addingTimeInterval(duration),
                samples: [rssi], endReason: reason)
        }
        let summary = BleSessionQualitySummary.make(sessions: [
            make(30, -88, "araç oturumu kapattı"),
            make(10, -93, "araç oturumu kapattı"),
            make(60, -80, "bağlantı zaman aşımı"),
        ])
        XCTAssertEqual(summary.count, 3)
        XCTAssertEqual(summary.averageDuration ?? 0, 33.3, accuracy: 0.1)
        XCTAssertEqual(summary.averageRSSI ?? 0, -87, accuracy: 0.1)
        XCTAssertEqual(summary.weakSessions, 2)
        XCTAssertEqual(summary.mostCommonEndReason, "araç oturumu kapattı")
    }

    func testSummaryWithoutRSSIStaysUnknown() {
        let session = BleSessionQuality.make(
            startedAt: start, endedAt: start.addingTimeInterval(5),
            samples: [], endReason: "zaman aşımı")
        let summary = BleSessionQualitySummary.make(sessions: [session])
        XCTAssertEqual(summary.count, 1)
        XCTAssertNil(summary.averageRSSI)
        XCTAssertEqual(summary.weakSessions, 0)
        XCTAssertEqual(summary.mostCommonEndReason, "zaman aşımı")
    }

    func testEmptySummaryHasNoValues() {
        let summary = BleSessionQualitySummary.make(sessions: [])
        XCTAssertEqual(summary.count, 0)
        XCTAssertNil(summary.averageDuration)
        XCTAssertNil(summary.averageRSSI)
        XCTAssertNil(summary.mostCommonEndReason)
    }    /// Son görülme: en yeni kanal seçilir; hiçbiri yoksa nil.
    func testLastSeenPicksNewestSourceAndHandlesEmptiness() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let ble = now.addingTimeInterval(-90)
        let cloud = now.addingTimeInterval(-7_200)

        let bleNewer = LastSeenSummary.make(ble: ble, cloud: cloud, now: now)
        XCTAssertEqual(bleNewer?.sourceText, "BLE")
        XCTAssertEqual(bleNewer?.relativeText, "1 dakika önce")

        let cloudNewer = LastSeenSummary.make(
            ble: ble, cloud: now.addingTimeInterval(-30), now: now)
        XCTAssertEqual(cloudNewer?.sourceText, "bulut")
        XCTAssertEqual(cloudNewer?.relativeText, "az önce")

        XCTAssertNil(LastSeenSummary.make(ble: nil, cloud: nil, now: now))
        let cloudOnly = LastSeenSummary.make(ble: nil, cloud: cloud, now: now)
        XCTAssertEqual(cloudOnly?.sourceText, "bulut")
        XCTAssertEqual(cloudOnly?.relativeText, "2 saat önce")
    }

    /// Göreceli zaman kovaları: saniye→dakika→saat→gün; gelecek tarih
    /// "az önce" kırpılır (eksi süre yazılmaz).
    func testLastSeenRelativeBuckets() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertEqual(LastSeenSummary.relative(now.addingTimeInterval(-59), now), "az önce")
        XCTAssertEqual(LastSeenSummary.relative(now.addingTimeInterval(-5_400), now), "1 saat önce")
        XCTAssertEqual(LastSeenSummary.relative(now.addingTimeInterval(-3 * 86_400), now), "3 gün önce")
        XCTAssertEqual(LastSeenSummary.relative(now.addingTimeInterval(60), now), "az önce")
    }

}
