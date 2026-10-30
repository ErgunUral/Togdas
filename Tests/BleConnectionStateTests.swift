import XCTest
@testable import ToqdasCore

/// BLE durum makinesinin kapı semantiği: komut yalnızca `.ready` iken gider.
final class BleConnectionStateTests: XCTestCase {
    private let allStates: [BleConnection.State] = [
        .disconnected, .connecting, .discovering, .certificate, .challenge, .authenticated, .ready, .failed(.unknown("hata"))
    ]

    func testOnlyReadyAllowsCommands() {
        for state in allStates {
            XCTAssertEqual(state.isReady, state.description == "Komut hazır", "Yalnız .ready komut kapısını açmalı: \(state)")
        }
        XCTAssertTrue(BleConnection.State.ready.isReady)
    }

    func testPredicatesAreMutuallyConsistent() {
        for state in allStates {
            let flags = [state.isReady, state.isFailed, state.isDisconnected, state.isConnecting,
                         state.isCertificate, state.isChallenge].filter { $0 }.count
            // .failed, .disconnected vb. her durum en fazla bir predicate'i doğrular.
            XCTAssertLessThanOrEqual(flags, 1, "Durum aynı anda birden fazla sınıfa girmemeli: \(state)")
        }
    }

    func testFailedCarriesTypedIssue() {
        guard case .failed(let issue) = BleConnection.State.failed(.vehicleKeyMissing) else {
            return XCTFail("failed ilişkili değer taşımalı")
        }
        XCTAssertEqual(issue, .vehicleKeyMissing)
        XCTAssertEqual(BleConnection.State.failed(.vehicleKeyMissing).description, "Hata: Araç eşleştirmesi gerekiyor")
    }

    func testTypedIssueMessagesRemainUserFacing() {
        XCTAssertEqual(BLEIssue.radioUnavailable.message, "Bluetooth kapalı veya izin yok.")
        XCTAssertEqual(BLEIssue.pairingLost.message, "Eşleşme hatası")
        XCTAssertEqual(BLEIssue.connectionFailed("zaman aşımı").message, "Bağlantı hatası: zaman aşımı")
        XCTAssertEqual(BLEIssue.handshakeTimeout("Araç sertifikayı yanıtlamadı.").message, "Araç sertifikayı yanıtlamadı.")
    }

    func testEveryStateHasVisibleDescription() {
        for state in allStates {
            XCTAssertFalse(state.description.isEmpty, "Durum metni boş olmamalı: \(state)")
        }
    }
}
