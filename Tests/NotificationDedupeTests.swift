import XCTest
@testable import ToqdasCore

/// `NotificationDedupe`: anahtar başına günde bir kez bildirim tekniği.
final class NotificationDedupeTests: XCTestCase {
    private final class MemoryStore: KeyValueStore {
        var values: [String: Any] = [:]
        func string(forKey key: String) -> String? { values[key] as? String }
        func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
        func object(forKey key: String) -> Any? { values[key] }
        func integer(forKey key: String) -> Int { values[key] as? Int ?? 0 }
        func data(forKey key: String) -> Data? { values[key] as? Data }
        func set(_ value: Any?, forKey key: String) {
            if let value { values[key] = value } else { values.removeValue(forKey: key) }
        }
        func removeObject(forKey key: String) { values.removeValue(forKey: key) }
    }

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Istanbul")!
        return calendar
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testMissingRecordAllowsNotification() {
        let dedupe = NotificationDedupe(store: MemoryStore())
        XCTAssertTrue(dedupe.shouldNotify(key: "k", now: date(2026, 11, 12), calendar: calendar))
    }

    func testSameDayBlocksSecondNotification() {
        let store = MemoryStore()
        let dedupe = NotificationDedupe(store: store)
        let morning = date(2026, 11, 12, 9)
        XCTAssertTrue(dedupe.shouldNotify(key: "k", now: morning, calendar: calendar))
        dedupe.record(key: "k", now: morning)
        // Aynı gün, saat farkıyla: yine engellenir.
        XCTAssertFalse(dedupe.shouldNotify(key: "k", now: date(2026, 11, 12, 21), calendar: calendar))
    }

    func testNextDayAllowsNotificationAgain() {
        let store = MemoryStore()
        let dedupe = NotificationDedupe(store: store)
        dedupe.record(key: "k", now: date(2026, 11, 12))
        XCTAssertTrue(dedupe.shouldNotify(key: "k", now: date(2026, 11, 13), calendar: calendar))
    }

    func testKeysAreIndependent() {
        let dedupe = NotificationDedupe(store: MemoryStore())
        dedupe.record(key: "critical", now: date(2026, 11, 12))
        // Ciddiyet başına anahtar: kritik bildirildi, uyarı bağımsız.
        XCTAssertTrue(dedupe.shouldNotify(key: "warning", now: date(2026, 11, 12), calendar: calendar))
    }

    func testResetAllowsImmediateNotification() {
        let store = MemoryStore()
        let dedupe = NotificationDedupe(store: store)
        dedupe.record(key: "k", now: date(2026, 11, 12))
        dedupe.reset(key: "k")
        XCTAssertTrue(dedupe.shouldNotify(key: "k", now: date(2026, 11, 12, 13), calendar: calendar))
    }
}
