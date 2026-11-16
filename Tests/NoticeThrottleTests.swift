import XCTest
@testable import ToqdasCore

final class NoticeThrottleTests: XCTestCase {
    private final class MemoryStore: KeyValueStore {
        var values: [String: Any] = [:]
        func string(forKey key: String) -> String? { values[key] as? String }
        func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
        func object(forKey key: String) -> Any? { values[key] }
        func integer(forKey key: String) -> Int { values[key] as? Int ?? 0 }
        func data(forKey key: String) -> Data? { values[key] as? Data }
        func set(_ value: Any?, forKey key: String) { values[key] = value }
        func removeObject(forKey key: String) { values[key] = nil }
    }

    private var store: MemoryStore!
    private var throttle: NoticeThrottle!

    override func setUp() {
        super.setUp()
        store = MemoryStore()
        throttle = NoticeThrottle(store: store)
    }

    func testUnknownKeyAllowsImmediately() {
        XCTAssertTrue(throttle.shouldNotify(key: "k", window: 600,
                                            now: Date(timeIntervalSince1970: 1_000)))
    }

    func testRepeatWithinWindowIsSuppressed() {
        let now = Date(timeIntervalSince1970: 1_000)
        throttle.record(key: "k", now: now)
        XCTAssertFalse(throttle.shouldNotify(key: "k", window: 600,
                                             now: now.addingTimeInterval(300)))
    }

    func testAfterWindowAllowsAgain() {
        let now = Date(timeIntervalSince1970: 1_000)
        throttle.record(key: "k", now: now)
        XCTAssertTrue(throttle.shouldNotify(key: "k", window: 600,
                                            now: now.addingTimeInterval(601)))
    }

    func testResetAllowsImmediately() {
        let now = Date(timeIntervalSince1970: 1_000)
        throttle.record(key: "k", now: now)
        throttle.reset(key: "k")
        XCTAssertTrue(throttle.shouldNotify(key: "k", window: 600, now: now))
    }
}
