import XCTest
@testable import ToqdasCore

/// `AuxiliaryBatteryHistoryStore`: 12 V geçmiş kalıcılığı (JSON kodlu
/// tek anahtar). Bozuk/eksik veri boş geçmiş döner; "bilgi yok" ≠ 0.
final class AuxiliaryBatteryHistoryStoreTests: XCTestCase {
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

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func testMissingKeyReturnsEmptyHistory() {
        let store = AuxiliaryBatteryHistoryStore(store: MemoryStore())
        XCTAssertEqual(store.load(key: "k"), AuxiliaryBatteryHistory())
    }

    func testRoundTrip() {
        let memory = MemoryStore()
        let store = AuxiliaryBatteryHistoryStore(store: memory)
        var history = AuxiliaryBatteryHistory()
        XCTAssertTrue(history.record(percent: 72, on: date(2026, 11, 10), calendar: calendar))
        XCTAssertTrue(history.record(percent: 74, on: date(2026, 11, 11), calendar: calendar))
        store.save(history, key: "k")

        XCTAssertEqual(store.load(key: "k"), history)
    }

    func testRealZeroSurvivesRoundTrip() {
        // Gerçek 0 = ölçüm; asla "bilgi yok" ile karışmaz.
        let store = AuxiliaryBatteryHistoryStore(store: MemoryStore())
        var history = AuxiliaryBatteryHistory()
        XCTAssertTrue(history.record(percent: 0, on: date(2026, 11, 11), calendar: calendar))
        store.save(history, key: "k")

        let loaded = store.load(key: "k")
        // Son iki gün penceresi: 11'i %0, 12'si kayıtsız ("—").
        XCTAssertEqual(loaded.displayValues(count: 2, today: date(2026, 11, 12), calendar: calendar), ["%0", "—"])
    }

    func testCorruptDataReturnsEmptyHistory() {
        let memory = MemoryStore()
        memory.set(Data("bozuk-veri".utf8), forKey: "k")
        let store = AuxiliaryBatteryHistoryStore(store: memory)
        XCTAssertEqual(store.load(key: "k"), AuxiliaryBatteryHistory())
    }

    func testInvalidPercentIsRejectedByRecord() {
        // Store katmanı saf mantığa dokunmaz: aralık dışı değer yazılmaz.
        let store = AuxiliaryBatteryHistoryStore(store: MemoryStore())
        var history = AuxiliaryBatteryHistory()
        XCTAssertFalse(history.record(percent: 120, on: date(2026, 11, 11), calendar: calendar))
        XCTAssertEqual(store.load(key: "k"), AuxiliaryBatteryHistory())
    }
}
