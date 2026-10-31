import XCTest
@testable import ToqdasCore

/// `CloudSnapshotStore` testleri: VIN bazlı kayıt, bozulmuş veri toleransı
/// ve VIN değişiminde çapraz sızma olmaması.
final class CloudSnapshotStoreTests: XCTestCase {
    private final class MemoryStore: KeyValueStore {
        var values: [String: Any] = [:]
        func string(forKey key: String) -> String? { values[key] as? String }
        func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
        func set(_ value: Any?, forKey key: String) {
            if let value { values[key] = value } else { values.removeValue(forKey: key) }
        }
        func removeObject(forKey key: String) { values.removeValue(forKey: key) }
    }

    private func snapshot(
        battery: Double? = 78.5,
        range: Double? = 365,
        outside: Double? = 14.5,
        auxiliary: Double? = 65,
        odometer: Double? = 1_234.5,
        charging: String? = nil,
        updatedAt: Date = Date(timeIntervalSince1970: 1_790_000_000)
    ) -> CloudSnapshot {
        CloudSnapshot(
            batteryPercent: battery,
            rangeKM: range,
            outsideTemperatureC: outside,
            auxiliaryBatteryPercent: auxiliary,
            odometerKM: odometer,
            chargingState: charging,
            updatedAt: updatedAt
        )
    }

    func testSaveAndRoundTripPerVin() {
        let store = MemoryStore()
        let cloud = CloudSnapshotStore(store: store)
        let saved = snapshot()
        cloud.save(saved, for: "NL1CSU0P60G064536")
        XCTAssertEqual(cloud.snapshot(for: "NL1CSU0P60G064536"), saved)
        XCTAssertEqual(store.string(forKey: "toqdas.cloudSnapshot.NL1CSU0P60G064536")?.isEmpty, false)
    }

    func testVinsDoNotLeakIntoEachOther() {
        let store = MemoryStore()
        let cloud = CloudSnapshotStore(store: store)
        let owner = snapshot(battery: 80, range: 400)
        let shared = snapshot(battery: 31, range: 90)
        cloud.save(owner, for: "VINOWNER0000000001")
        cloud.save(shared, for: "VINSHARED000000001")
        XCTAssertEqual(cloud.snapshot(for: "VINOWNER0000000001"), owner)
        XCTAssertEqual(cloud.snapshot(for: "VINSHARED000000001"), shared)
    }

    func testZeroValuesSurviveAndMissingFieldsStayNil() {
        let store = MemoryStore()
        let cloud = CloudSnapshotStore(store: store)
        let zeroed = snapshot(
            battery: 0,
            range: 0,
            outside: nil,
            auxiliary: nil,
            odometer: 0,
            charging: nil
        )
        cloud.save(zeroed, for: "VINZERO00000000001")
        let read = cloud.snapshot(for: "VINZERO00000000001")
        XCTAssertEqual(read?.batteryPercent, 0)
        XCTAssertEqual(read?.rangeKM, 0)
        XCTAssertEqual(read?.odometerKM, 0)
        XCTAssertNil(read?.outsideTemperatureC)
        XCTAssertNil(read?.auxiliaryBatteryPercent)
        XCTAssertNil(read?.chargingState)
    }

    func testEmptyVinIsIgnored() {
        let store = MemoryStore()
        let cloud = CloudSnapshotStore(store: store)
        cloud.save(snapshot(), for: "")
        XCTAssertTrue(store.values.isEmpty)
        XCTAssertNil(cloud.snapshot(for: ""))
        cloud.clear(for: "")
        XCTAssertTrue(store.values.isEmpty)
    }

    func testClearRemovesOnlyThatVin() {
        let store = MemoryStore()
        let cloud = CloudSnapshotStore(store: store)
        cloud.save(snapshot(), for: "VINCLEAR000000001")
        cloud.save(snapshot(battery: 10), for: "VINKEEP00000000001")
        cloud.clear(for: "VINCLEAR000000001")
        XCTAssertNil(cloud.snapshot(for: "VINCLEAR000000001"))
        XCTAssertEqual(cloud.snapshot(for: "VINKEEP00000000001")?.batteryPercent, 10)
    }

    func testCorruptPayloadIsDroppedWithoutCrash() {
        let store = MemoryStore()
        let cloud = CloudSnapshotStore(store: store)
        store.set("{not json", forKey: CloudSnapshotStore.key(for: "VINBROKEN0000001"))
        XCTAssertNil(cloud.snapshot(for: "VINBROKEN0000001"))
    }
}
