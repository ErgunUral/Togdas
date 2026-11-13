import XCTest
@testable import ToqdasCore

/// `WatchDiagnostics`: saatte sınırlı boyutlu olay günlüğü.
final class WatchDiagnosticsTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "test.watchDiagnostics"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testEmptyByDefault() {
        XCTAssertTrue(WatchDiagnostics.events(defaults: defaults).isEmpty)
    }

    func testAppendsInOrder() {
        let base = Date(timeIntervalSince1970: 1_000)
        WatchDiagnostics.log("birinci", at: base, defaults: defaults)
        WatchDiagnostics.log("ikinci", at: base.addingTimeInterval(5), defaults: defaults)
        let events = WatchDiagnostics.events(defaults: defaults)
        XCTAssertEqual(events.map(\.message), ["birinci", "ikinci"])
        XCTAssertEqual(events.first?.at, 1_000)
        XCTAssertEqual(events.last?.at, 1_005)
    }

    func testCapacityKeepsLatest() {
        let base = Date(timeIntervalSince1970: 2_000)
        for index in 0..<(WatchDiagnostics.capacity + 10) {
            WatchDiagnostics.log("olay \(index)", at: base.addingTimeInterval(Double(index)),
                                 defaults: defaults)
        }
        let events = WatchDiagnostics.events(defaults: defaults)
        XCTAssertEqual(events.count, WatchDiagnostics.capacity)
        XCTAssertEqual(events.first?.message, "olay 10")
        XCTAssertEqual(events.last?.message, "olay \(WatchDiagnostics.capacity + 9)")
    }

    func testLongMessageIsTruncated() {
        WatchDiagnostics.log(String(repeating: "a", count: 400), defaults: defaults)
        XCTAssertEqual(WatchDiagnostics.events(defaults: defaults).first?.message.count, 160)
    }

    func testClearRemovesAll() {
        WatchDiagnostics.log("olay", defaults: defaults)
        WatchDiagnostics.clear(defaults: defaults)
        XCTAssertTrue(WatchDiagnostics.events(defaults: defaults).isEmpty)
    }

    func testCorruptDataIsIgnored() {
        defaults.set(Data("bozuk".utf8), forKey: WatchDiagnostics.storageKey)
        XCTAssertTrue(WatchDiagnostics.events(defaults: defaults).isEmpty)
    }
}
