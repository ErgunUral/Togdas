import XCTest
import Security
@testable import ToqdasCore

/// Anahtar üretim kuralı: yalnız öğe gerçekten yoksa üret.
/// Kilitli cihazda üretmek "anahtarı tekrar alma" zincirini başlatıyordu.
final class PhoneKeyStoreTests: XCTestCase {
    func testGeneratesOnlyWhenItemIsTrulyMissing() {
        XCTAssertTrue(PhoneKeyStore.canGenerate(for: errSecItemNotFound))
    }

    func testDoesNotGenerateWhileDeviceIsLocked() {
        XCTAssertFalse(PhoneKeyStore.canGenerate(for: errSecInteractionNotAllowed))
    }

    func testDoesNotGenerateOnTransientErrors() {
        XCTAssertFalse(PhoneKeyStore.canGenerate(for: errSecNotAvailable))
        XCTAssertFalse(PhoneKeyStore.canGenerate(for: errSecSuccess))
        XCTAssertFalse(PhoneKeyStore.canGenerate(for: errSecAuthFailed))
    }

    func testLockedMessageIsHonest() {
        let message = PhoneKeyStore.unavailableMessage(for: errSecInteractionNotAllowed)
        XCTAssertTrue(message.contains("kilitli"))
        XCTAssertFalse(message.contains("yeniden eşleştir"))
    }

    func testOtherErrorShowsCodeNotSilentRegeneration() {
        let message = PhoneKeyStore.unavailableMessage(for: errSecNotAvailable)
        XCTAssertTrue(message.contains("\(errSecNotAvailable)"))
    }
}
