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

}
