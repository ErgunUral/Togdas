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
    }
}
