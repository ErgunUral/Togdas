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
}
