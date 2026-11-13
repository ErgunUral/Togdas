import XCTest
@testable import ToqdasCore

/// Sahiplik çakışması yanıtının şekil kaydı: alan adları görünür,
/// **değerler asla** yazılmaz.
final class ClaimResponseShapeTests: XCTestCase {
    func testDescribesKeysAndTypesOnly() {
        let json = #"""
        {"resultEnum":"OverwriteDetection","ownerEmail":"a@b.com",
         "owner":{"phone":"+905551112233","device":"iPhone 17 Pro"},
         "relations":[{"deviceName":"Ural'ın iPhone'u"}]}
        """#
        let shape = ClaimResponseShape.describe(Data(json.utf8))

        XCTAssertTrue(shape.contains("resultEnum:string(18)"))
        XCTAssertTrue(shape.contains("ownerEmail:string(7)"))
        XCTAssertTrue(shape.contains("owner.phone:string(13)"))
        XCTAssertTrue(shape.contains("relations:array(1)"))
        XCTAssertTrue(shape.contains("relations[].deviceName:string"))

        // Değer sızıntısı olmamalı.
        XCTAssertFalse(shape.contains("a@b.com"))
        XCTAssertFalse(shape.contains("+905551112233"))
        XCTAssertFalse(shape.contains("iPhone 17 Pro"))
        XCTAssertFalse(shape.contains("Ural'ın iPhone'u"))
    }

    func testInvalidPayloadIsReported() {
        XCTAssertEqual(ClaimResponseShape.describe(Data("bozuk".utf8)), "geçersiz")
    }

    func testArrayRoot() {
        let shape = ClaimResponseShape.describe(Data("[1,2,3]".utf8))
        XCTAssertEqual(shape, "root:array(3)")
    }

    func testDeepNestingIsCapped() {
        let json = #"{"a":{"b":{"c":{"d":{"e":"gizli-deger"}}}}}"#
        let shape = ClaimResponseShape.describe(Data(json.utf8))
        XCTAssertFalse(shape.contains("gizli-deger"))
        XCTAssertTrue(shape.contains("a.b.c"))
    }

    func testSaveAndLoad() {
        let suite = "test.claimShape"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        ClaimResponseShape.save("resultEnum:string(18)", at: Date(timeIntervalSince1970: 42),
                                defaults: defaults)
        XCTAssertEqual(ClaimResponseShape.load(defaults: defaults)?.shape, "resultEnum:string(18)")
        XCTAssertEqual(ClaimResponseShape.load(defaults: defaults)?.at, 42)
        ClaimResponseShape.clear(defaults: defaults)
        XCTAssertNil(ClaimResponseShape.load(defaults: defaults))
        defaults.removePersistentDomain(forName: suite)
    }
}
