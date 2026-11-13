import XCTest
@testable import ToqdasCore

/// Dijital imza kimliği: parmak izi karşılaştırması.
final class KeyIdentityTests: XCTestCase {
    func testFingerprintIsShortAndStable() {
        let data = Data(repeating: 0xAB, count: 65)
        let fp = KeyIdentity.fingerprint(data)
        XCTAssertEqual(fp.count, 8)
        XCTAssertEqual(fp, KeyIdentity.fingerprint(data))
        XCTAssertNotEqual(fp, KeyIdentity.fingerprint(Data(repeating: 0xAC, count: 65)))
    }

    func testFirstUseDoesNotWarn() {
        XCTAssertEqual(KeyIdentity.check(current: "aaaa1111", stored: nil), .firstUse)
    }

    func testMatchIsSilent() {
        XCTAssertEqual(KeyIdentity.check(current: "aaaa1111", stored: "aaaa1111"), .match)
    }

    /// Anahtar değişimi sessizce geçilmez: eski sertifika yeni anahtara ait değildir.
    func testChangedKeyIsReportedWithPrevious() {
        XCTAssertEqual(KeyIdentity.check(current: "bbbb2222", stored: "aaaa1111"),
                       .changed(previous: "aaaa1111"))
    }

    func testMissingKeyIsNotTreatedAsChange() {
        // Anahtar yoksa (henüz üretilmemiş) sessiz geçilir; üretim akışı ayrıdır.
        XCTAssertEqual(KeyIdentity.check(current: nil, stored: "aaaa1111"), .match)
    }

    func testKeysAreVINScoped() {
        XCTAssertTrue(KeyIdentity.fingerprintKey("VIN1").hasSuffix("VIN1"))
        XCTAssertNotEqual(KeyIdentity.fingerprintKey("VIN1"), KeyIdentity.certificateFingerprintKey("VIN1"))
    }
}
