import XCTest
@testable import ToqdasCore

/// `ClimateSettings`: klima hedef sıcaklık kalıcılığı.
final class ClimateSettingsTests: XCTestCase {
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

    func testKeyFormatMatchesPreviousLiteral() {
        XCTAssertEqual(ClimateSettings.targetKey("V1"), "toqdas.climateTarget.V1")
    }

    func testMissingTargetIsNil() {
        let settings = ClimateSettings(store: MemoryStore())
        XCTAssertNil(settings.target(vin: "V1"))
        XCTAssertFalse(settings.hasTarget(vin: "V1"))
    }

    func testTargetRoundTripAndHasTarget() {
        let settings = ClimateSettings(store: MemoryStore())
        settings.setTarget(21.5, vin: "V1")
        XCTAssertEqual(settings.target(vin: "V1"), 21.5)
        XCTAssertTrue(settings.hasTarget(vin: "V1"))

        // nil yazımı = kaydı kaldırma; "araç durumundan ilk hedef alma"
        // kararı tekrar devreye girer.
        settings.setTarget(nil, vin: "V1")
        XCTAssertNil(settings.target(vin: "V1"))
        XCTAssertFalse(settings.hasTarget(vin: "V1"))
    }

    func testVinsAreIsolated() {
        let settings = ClimateSettings(store: MemoryStore())
        settings.setTarget(20, vin: "V1")
        XCTAssertNil(settings.target(vin: "V2"))
    }
}
