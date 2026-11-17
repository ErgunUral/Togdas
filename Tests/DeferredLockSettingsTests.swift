import XCTest
@testable import ToqdasCore

/// `DeferredLockSettings`: bilet son tarihinin VIN bazlı kalıcılığı.
/// Uygulama askıya alınırsa bilet sessizce kaybolmamalı; süresi dolmuş
/// kayıt geri yüklenmemeli.
final class DeferredLockSettingsTests: XCTestCase {
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

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testRoundTripKeepsDeadline() {
        let store = MemoryStore()
        let settings = DeferredLockSettings(store: store)
        let deadline = now.addingTimeInterval(120)
        settings.setDeadline(deadline, vin: "VIN1")

        XCTAssertEqual(settings.deadline(vin: "VIN1"), deadline)
        XCTAssertNil(settings.deadline(vin: "VIN2"))
    }

    func testRestoredTicketEndsAtSavedDeadline() {
        let store = MemoryStore()
        let settings = DeferredLockSettings(store: store)
        settings.setDeadline(now.addingTimeInterval(300), vin: "VIN1")

        let ticket = settings.restoredTicket(vin: "VIN1", now: now)
        XCTAssertNotNil(ticket)
        XCTAssertEqual(ticket?.deadline, now.addingTimeInterval(300))
    }

    func testExpiredTicketIsDroppedAndCleared() {
        let store = MemoryStore()
        let settings = DeferredLockSettings(store: store)
        settings.setDeadline(now.addingTimeInterval(-1), vin: "VIN1")

        XCTAssertNil(settings.restoredTicket(vin: "VIN1", now: now))
        XCTAssertNil(settings.deadline(vin: "VIN1"))
    }

    func testNilClearsRecord() {
        let store = MemoryStore()
        let settings = DeferredLockSettings(store: store)
        settings.setDeadline(now.addingTimeInterval(60), vin: "VIN1")
        settings.setDeadline(nil, vin: "VIN1")
        XCTAssertNil(settings.deadline(vin: "VIN1"))
    }

    func testKeyContainsVinOnlyOnceAndIsStable() {
        XCTAssertEqual(DeferredLockSettings.deadlineKey("VIN1"),
                       "toqdas.deferredLock.deadline.VIN1")
    }
}
