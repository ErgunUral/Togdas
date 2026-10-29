import XCTest
@testable import ToqdasCore

final class UserFacingErrorTests: XCTestCase {
    func testAuthenticationKeywordsWinOverNetworkWords() {
        let error = UserFacingError.classify(message: "Sunucu 401: oturum süresi doldu, lütfen giriş yapın")
        XCTAssertEqual(error.kind, .authentication)
        XCTAssertFalse(error.isRetryable)
        XCTAssertEqual(error.title, "Oturum doğrulanamadı")
    }

    func testTimeoutIsTreatedAsVehicleAsleepAndRetryable() {
        let error = UserFacingError.classify(message: "İstek zaman aşımına uğradı (timeout)")
        XCTAssertEqual(error.kind, .vehicleAsleep)
        XCTAssertTrue(error.isRetryable)
        XCTAssertNotNil(error.recovery)
    }

    func testCertificateKeywords() {
        let error = UserFacingError.classify(message: "Araç eşleştirmesi gerekiyor: sertifika yok")
        XCTAssertEqual(error.kind, .certificate)
    }

    func testBLEKeywords() {
        let error = UserFacingError.classify(message: "BLE bağlantısı hazır değil")
        XCTAssertEqual(error.kind, .bleNotReady)
    }

    func testNetworkKeywords() {
        let error = UserFacingError.classify(message: "İnternet bağlantısı yok")
        XCTAssertEqual(error.kind, .network)
        XCTAssertTrue(error.isRetryable)
    }

    func testPermissionKeywords() {
        let error = UserFacingError.classify(message: "Konum izni verilmedi")
        XCTAssertEqual(error.kind, .permission)
        XCTAssertFalse(error.isRetryable)
    }

    func testCancellationKeywords() {
        let error = UserFacingError.classify(message: "İşlem iptal edildi")
        XCTAssertEqual(error.kind, .cancelled)
    }

    func testUnknownMessageFallsBackToUnknown() {
        let error = UserFacingError.classify(message: "Beklenmeyen durum")
        XCTAssertEqual(error.kind, .unknown)
        XCTAssertTrue(error.isRetryable)
    }

    func testEveryKindHasTitleAndRecoveryExceptCancelled() {
        for kind in [UserFacingError.Kind.network, .authentication, .certificate, .vehicleAsleep,
                     .bleNotReady, .permission, .server, .unknown] {
            let error = UserFacingError.make(kind: kind, message: "x")
            XCTAssertFalse(error.title.isEmpty, "\(kind) başlıksız")
            XCTAssertNotNil(error.recovery, "\(kind) önerisiz")
        }
        XCTAssertNil(UserFacingError.make(kind: .cancelled, message: "x").recovery)
    }

    func testTechnicalDetailIsPreserved() {
        let error = UserFacingError.classify(message: "ağ hatası", technicalDetail: "URLError -1009")
        XCTAssertEqual(error.technicalDetail, "URLError -1009")
    }
}
