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
    }
}
