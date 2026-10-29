import XCTest
@testable import ToqdasCore

final class WidgetRefreshPolicyTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_000_000)

    func testFirstPublishAlwaysReloads() {
        XCTAssertTrue(WidgetRefreshPolicy.shouldReload(
            isFirstPublish: true, contentChanged: true, lastReloadAt: nil, now: base))
        XCTAssertTrue(WidgetRefreshPolicy.shouldReload(
            isFirstPublish: true, contentChanged: false, lastReloadAt: nil, now: base))
    }

    func testUnchangedContentSkipsWithinWindow() {
        XCTAssertFalse(WidgetRefreshPolicy.shouldReload(
            isFirstPublish: false, contentChanged: false,
            lastReloadAt: base.addingTimeInterval(-30), now: base))
    }

    func testChangedContentRespectsMinimumInterval() {
        XCTAssertFalse(WidgetRefreshPolicy.shouldReload(
            isFirstPublish: false, contentChanged: true,
            lastReloadAt: base.addingTimeInterval(-30), now: base))
        XCTAssertTrue(WidgetRefreshPolicy.shouldReload(
            isFirstPublish: false, contentChanged: true,
            lastReloadAt: base.addingTimeInterval(-90), now: base))
    }

    func testForcedRefreshAfterLongInterval() {
        XCTAssertTrue(WidgetRefreshPolicy.shouldReload(
            isFirstPublish: false, contentChanged: false,
            lastReloadAt: base.addingTimeInterval(-301), now: base))
    }

    func testClockGoingBackwardsReloads() {
        XCTAssertTrue(WidgetRefreshPolicy.shouldReload(
            isFirstPublish: false, contentChanged: false,
            lastReloadAt: base.addingTimeInterval(120), now: base))
    }
}
