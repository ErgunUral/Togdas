import XCTest
@testable import ToqdasCore

final class ChargingSessionTrackerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_500_000)

    func testClassifierExcludesPlannedAndFinished() {
        XCTAssertTrue(ChargingStateClassifier.isCharging("CHRGMODE_CHARGING"))
        XCTAssertFalse(ChargingStateClassifier.isCharging("CHRGMODE_NOTCONNECTED"))
        XCTAssertFalse(ChargingStateClassifier.isCharging("CHRGMODE_SCHEDULED"))
        XCTAssertFalse(ChargingStateClassifier.isCharging("CHRGMODE_FINISH"))
        XCTAssertFalse(ChargingStateClassifier.isCharging(nil))
    }

    func testSessionStartRecordsTimeAndSamples() {
        var record = ChargingSessionRecord.empty
        record = ChargingSessionTracker.updated(record, charging: true, percent: 70, at: start)
        record = ChargingSessionTracker.updated(
            record, charging: true, percent: 72, at: start.addingTimeInterval(300))

        XCTAssertTrue(record.charging)
        XCTAssertEqual(record.startedAt, start.timeIntervalSince1970)
        XCTAssertEqual(record.samples.count, 2)
        XCTAssertEqual(record.samples.last?.percent, 72)
    }

    func testSessionEndBecomesLastSessionAndClears() {
        var record = ChargingSessionRecord.empty
        record = ChargingSessionTracker.updated(record, charging: true, percent: 70, at: start)
        record = ChargingSessionTracker.updated(
            record, charging: false, percent: 73, at: start.addingTimeInterval(600))

        XCTAssertFalse(record.charging)
        XCTAssertNil(record.startedAt)
        XCTAssertTrue(record.samples.isEmpty)
        XCTAssertEqual(record.last?.startedAt, start.timeIntervalSince1970)
        XCTAssertEqual(record.last?.endedAt, start.addingTimeInterval(600).timeIntervalSince1970)
        XCTAssertEqual(record.last?.lastPercent, 73)
    }

    func testSampleCapKeepsNewest() {
        var record = ChargingSessionRecord.empty
        record = ChargingSessionTracker.updated(record, charging: true, percent: 10, at: start)
        for index in 0..<50 {
            record = ChargingSessionTracker.updated(
                record, charging: true, percent: Double(10 + index),
                at: start.addingTimeInterval(TimeInterval(index + 1) * 60))
        }
        XCTAssertEqual(record.samples.count, 40)
        XCTAssertEqual(record.samples.last?.percent, 59)
    }

    func testRateFromLinearSamples() {
        // 10 dakikada %4,2 artış → %0,42/dk.
        let samples = stride(from: 0, through: 10, by: 1).map { minute in
            ChargingSample(
                at: start.timeIntervalSince1970 + Double(minute) * 60,
                percent: 70 + Double(minute) * 0.42)
        }
        let rate = ChargingSessionTracker.rate(in: samples, now: start.addingTimeInterval(600))
        XCTAssertEqual(rate ?? 0, 0.42, accuracy: 0.01)
    }

    func testRateNeedsSpanAndRecentWindow() {
        // Yayılım 3 dakikanın altında: ölçülemez.
        let short = [
            ChargingSample(at: start.timeIntervalSince1970, percent: 70),
            ChargingSample(at: start.timeIntervalSince1970 + 60, percent: 70.5),
        ]
        XCTAssertNil(ChargingSessionTracker.rate(in: short, now: start.addingTimeInterval(60)))

        // Eski örnekler 15 dakikalık pencerenin dışında kalır.
        let stale = [
            ChargingSample(at: start.timeIntervalSince1970 - 1800, percent: 70),
            ChargingSample(at: start.timeIntervalSince1970 - 1500, percent: 71),
        ]
        XCTAssertNil(ChargingSessionTracker.rate(
            in: stale, now: start.addingTimeInterval(600)))
    }

    func testRateFilteredWhenNoiseOnly() {
        let noise = [
            ChargingSample(at: start.timeIntervalSince1970, percent: 70.4),
            ChargingSample(at: start.timeIntervalSince1970 + 300, percent: 70.2),
            ChargingSample(at: start.timeIntervalSince1970 + 600, percent: 70.3),
        ]
        XCTAssertNil(ChargingSessionTracker.rate(in: noise, now: start.addingTimeInterval(600)))
    }

    func testLiveViewChargingAndIdle() {
        var record = ChargingSessionRecord.empty
        record = ChargingSessionTracker.updated(record, charging: true, percent: 70, at: start)
        record = ChargingSessionTracker.updated(
            record, charging: true, percent: 74, at: start.addingTimeInterval(600))

        let live = ChargingSessionTracker.liveView(record: record, now: start.addingTimeInterval(600))
        XCTAssertTrue(live.charging)
        XCTAssertEqual(live.startedAt, start.timeIntervalSince1970)
        XCTAssertNotNil(live.percentPerMinute)

        let ended = ChargingSessionTracker.updated(
            record, charging: false, percent: 74, at: start.addingTimeInterval(900))
        let idle = ChargingSessionTracker.liveView(record: ended, now: start.addingTimeInterval(900))
        XCTAssertFalse(idle.charging)
        XCTAssertNil(idle.startedAt)
        XCTAssertNotNil(idle.lastSession)
    }

    func testStoreRoundTripAndClear() {
        let suite = "test.chargingSession"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = ChargingSessionStore(defaults: defaults)

        var record = ChargingSessionRecord.empty
        record = ChargingSessionTracker.updated(record, charging: true, percent: 70, at: start)
        store.save(record, vin: "TESTVIN123")
        XCTAssertEqual(store.load(vin: "TESTVIN123").samples.count, 1)

        store.clear(vin: "TESTVIN123")
        XCTAssertEqual(store.load(vin: "TESTVIN123"), .empty)
        defaults.removePersistentDomain(forName: suite)
    }    /// Oturum bitişinde geçmiş girdisi üretilir: ilk/son yüzde ve oturum sonu
    /// gözlemlenen hız saklanır; "last" davranışı korunur.
    func testSessionEndAppendsHistoryEntry() {
        var record = ChargingSessionRecord.empty
        record = ChargingSessionTracker.updated(record, charging: true, percent: 70, at: start)
        record = ChargingSessionTracker.updated(
            record, charging: true, percent: 74, at: start.addingTimeInterval(600))
        record = ChargingSessionTracker.updated(
            record, charging: false, percent: 75, at: start.addingTimeInterval(1200))

        XCTAssertEqual(record.history.count, 1)
        let entry = record.history[0]
        XCTAssertEqual(entry.startedAt, start.timeIntervalSince1970)
        XCTAssertEqual(entry.endedAt, start.addingTimeInterval(1200).timeIntervalSince1970)
        XCTAssertEqual(entry.startPercent ?? -1, 70, accuracy: 0.01)
        XCTAssertEqual(entry.endPercent ?? -1, 75, accuracy: 0.01)
        // Örnekler %70→%74, 10 dk yayılım: %0.4/dk
        XCTAssertEqual(entry.ratePerMinute ?? -1, 0.4, accuracy: 0.05)
        XCTAssertEqual(record.last?.lastPercent, 75)
    }

    /// Yüzde telemetrisi hiç gelmemiş oturum: süre bilinir, yüzde ve hız "—".
    func testHistoryEntryWithoutSamplesKeepsUnknownFields() {
        var record = ChargingSessionRecord.empty
        record = ChargingSessionTracker.updated(record, charging: true, percent: nil, at: start)
        record = ChargingSessionTracker.updated(
            record, charging: false, percent: nil, at: start.addingTimeInterval(600))

        XCTAssertEqual(record.history.count, 1)
        XCTAssertNil(record.history[0].startPercent)
        XCTAssertNil(record.history[0].endPercent)
        XCTAssertNil(record.history[0].ratePerMinute)
    }

    /// Geçmiş üst sınırı: en yeniler kalır, eskiler düşer.
    func testHistoryCapsAtLimit() {
        var record = ChargingSessionRecord.empty
        for index in 0..<25 {
            let at = start.addingTimeInterval(TimeInterval(index) * 3600)
            record = ChargingSessionTracker.updated(record, charging: true, percent: 50, at: at)
            record = ChargingSessionTracker.updated(
                record, charging: false, percent: 60, at: at.addingTimeInterval(60))
        }
        XCTAssertEqual(record.history.count, 20)
        XCTAssertEqual(record.history.last?.startedAt,
                       start.addingTimeInterval(24 * 3600).timeIntervalSince1970)
    }

    /// Eski kalıcı kayıtta "history" anahtarı yok; çözümleme kaybı olmadan
    /// boş geçmişle açılır (mevcut "last" korunur).
    func testLegacyRecordWithoutHistoryDecodes() throws {
        let legacy = """
        {"charging":false,"last":{"startedAt":100,"endedAt":200,"lastPercent":71}}
        """
        let data = Data(legacy.utf8)
        let record = try JSONDecoder().decode(ChargingSessionRecord.self, from: data)
        XCTAssertFalse(record.charging)
        XCTAssertEqual(record.last?.lastPercent, 71)
        XCTAssertTrue(record.history.isEmpty)
    }
    /// Hedefe kalan: bilinen yüzdeyle puan üretir; eksik veri nil; aşım 0.
    func testChargingTargetRemaining() {
        XCTAssertEqual(ChargingTargetPolicy.remaining(target: 80, percent: 71.4) ?? -1,
                       8.6, accuracy: 0.01)
        XCTAssertEqual(ChargingTargetPolicy.remaining(target: 80, percent: 95) ?? -1,
                       0, accuracy: 0.01)
        XCTAssertNil(ChargingTargetPolicy.remaining(target: nil, percent: 71))
        XCTAssertNil(ChargingTargetPolicy.remaining(target: 80, percent: nil))
        XCTAssertNil(ChargingTargetPolicy.remaining(target: 80, percent: .nan))
    }

    /// Ulaşıldı: eşik dahil; bilinmeyen yüzde asla ulaşıldı demez.
    func testChargingTargetReached() {
        XCTAssertFalse(ChargingTargetPolicy.reached(target: 80, percent: 79.9))
        XCTAssertTrue(ChargingTargetPolicy.reached(target: 80, percent: 80))
        XCTAssertTrue(ChargingTargetPolicy.reached(target: 80, percent: 100))
        XCTAssertFalse(ChargingTargetPolicy.reached(target: nil, percent: 100))
        XCTAssertFalse(ChargingTargetPolicy.reached(target: 80, percent: nil))
    }

    /// Hedef saklaması: tur-uçuş ve kapalı (nil) sıfırlaması.
    func testChargingTargetStoreRoundTrip() {
        let suite = "test.chargingTarget"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = ChargingTargetStore(defaults: defaults)

        XCTAssertNil(store.load(vin: "TESTVIN123")) // kapalı varsayılan
        store.save(80, vin: "TESTVIN123")
        XCTAssertEqual(store.load(vin: "TESTVIN123"), 80)
        store.save(nil, vin: "TESTVIN123")
        XCTAssertNil(store.load(vin: "TESTVIN123"))
        XCTAssertNil(store.load(vin: "")) // boş VIN yutulur
        defaults.removePersistentDomain(forName: suite)
    }

}
