import XCTest
@testable import ToqdasCore

/// `GaragePreferences` testleri: anahtar adları, varsayılanlar ve VIN bazlı izin.
final class GaragePreferencesTests: XCTestCase {
    private final class MemoryStore: KeyValueStore {
        var values: [String: Any] = [:]
        func string(forKey key: String) -> String? { values[key] as? String }
        func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
        func set(_ value: Any?, forKey key: String) {
            if let value { values[key] = value } else { values.removeValue(forKey: key) }
        }
        func removeObject(forKey key: String) { values.removeValue(forKey: key) }
    }

    func testDefaultsAreEmptyAndDenyAutoConnect() {
        let preferences = GaragePreferences(store: MemoryStore())
        XCTAssertNil(preferences.selectedVin)
        XCTAssertFalse(preferences.keepConnected)
        XCTAssertFalse(preferences.proximityEnabled(for: "VIN1"))
        XCTAssertFalse(preferences.autoConnectEnabled(for: "VIN1"))
        XCTAssertFalse(preferences.autoConnectEnabled(for: ""))
    }

    func testSelectedVinRoundTrip() {
        let store = MemoryStore()
        let preferences = GaragePreferences(store: store)
        preferences.selectedVin = "VIN1"
        XCTAssertEqual(preferences.selectedVin, "VIN1")
        XCTAssertEqual(store.string(forKey: "toqdas.selectedVin"), "VIN1")
        preferences.selectedVin = nil
        XCTAssertNil(preferences.selectedVin)
        XCTAssertNil(store.values["toqdas.selectedVin"])
    }

    func testKeepConnectedEnablesAutoConnectForAnyVin() {
        let store = MemoryStore()
        let preferences = GaragePreferences(store: store)
        store.set(true, forKey: "toqdas.ble.keepConnected")
        XCTAssertTrue(preferences.autoConnectEnabled(for: "VIN1"))
        XCTAssertTrue(preferences.autoConnectEnabled(for: "VIN2"))
        XCTAssertFalse(preferences.autoConnectEnabled(for: ""))
    }

    func testProximityIsPerVehicle() {
        let preferences = GaragePreferences(store: MemoryStore())
        preferences.setProximityEnabled(true, for: "VIN1")
        XCTAssertTrue(preferences.proximityEnabled(for: "VIN1"))
        XCTAssertTrue(preferences.autoConnectEnabled(for: "VIN1"))
        XCTAssertFalse(preferences.proximityEnabled(for: "VIN2"))
        XCTAssertFalse(preferences.autoConnectEnabled(for: "VIN2"))
    }

    func testProximityKeyIsStableAndIgnoredForEmptyVin() {
        XCTAssertEqual(GaragePreferences.proximityKey(for: "VIN1"), "toqdas.proximity.enabled.VIN1")
        let store = MemoryStore()
        let preferences = GaragePreferences(store: store)
        preferences.setProximityEnabled(true, for: "")
        XCTAssertFalse(preferences.proximityEnabled(for: ""))
        XCTAssertTrue(store.values.isEmpty)
    }
}
