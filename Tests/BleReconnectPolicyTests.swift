import XCTest
@testable import ToqdasCore

final class BleReconnectPolicyTests: XCTestCase {
    private func action(
        connectedBefore: Bool = true,
        awaiting: Bool = false,
        needsRepair: Bool = false,
        pairingRequired: Bool = false,
        autoConnect: Bool = true,
        radio: Bool = true,
        attempts: Int = 0,
        pairingAttempts: Int = 0
    ) -> BleReconnectPolicy.Action {
        BleReconnectPolicy.action(
            connectedBefore: connectedBefore,
            awaitingConnection: awaiting,
            needsRepair: needsRepair,
            repairStatus: "Sertifika onarımı gerekiyor",
            pairingRequired: pairingRequired,
            autoConnectEnabled: autoConnect,
            radioAvailable: radio,
            radioFailureStatus: "Bluetooth kapalı",
            attempts: attempts,
            pairingAttempts: pairingAttempts
        )
    }

    func testFirstDisconnectedPublicationIsIgnored() {
        // Combine aboneliği mevcut değeri hemen yayınlar; bu kopma değildir.
        XCTAssertEqual(action(connectedBefore: false, awaiting: false), .ignore)
    }

    func testAwaitingConnectionCountsAsDrop() {
        XCTAssertEqual(action(connectedBefore: false, awaiting: true), .reconnect(delay: 1.5, attempt: 1))
    }

    func testRepairTakesPriority() {
        XCTAssertEqual(action(needsRepair: true), .repair("Sertifika onarımı gerekiyor"))
        // Onarım varken eşleştirme/geri çekilme yapılmaz.
        XCTAssertEqual(action(needsRepair: true, pairingRequired: true), .repair("Sertifika onarımı gerekiyor"))
    }

    func testPairingWaitInsteadOfFastBackoff() {
        XCTAssertEqual(action(pairingRequired: true), .pairingWait)
        XCTAssertEqual(action(pairingRequired: true, pairingAttempts: 29), .pairingWait)
    }

    func testPairingStopsAfterThirtyAttempts() {
        guard case .pairingExhausted(let message) = action(pairingRequired: true, pairingAttempts: 30) else {
            return XCTFail("Eşleştirme 30 denemede durmalı")
        }
        XCTAssertTrue(message.contains("eşleştirme"))
    }

    func testAutoConnectOffKeepsSilentAfterFirstConnection() {
        XCTAssertEqual(action(autoConnect: false), .ignore)
    }

    func testAutoConnectOffShowsStateWhenNeverConnected() {
        // İlk bağlantı denemesinde durum metni gösterilir (boş metin = mevcut durum korunur).
        XCTAssertEqual(action(connectedBefore: false, awaiting: true, autoConnect: false), .showStatus(""))
    }

    func testRadioOffDoesNotConsumeAttempts() {
        XCTAssertEqual(action(radio: false, attempts: 5), .waitForRadio("Bluetooth kapalı"))
    }

    func testBackoffSequenceIsCapped() {
        XCTAssertEqual(BleReconnectPolicy.backoffDelay(attempt: 1), 1.5, accuracy: 0.001)
        XCTAssertEqual(BleReconnectPolicy.backoffDelay(attempt: 2), 3, accuracy: 0.001)
        XCTAssertEqual(BleReconnectPolicy.backoffDelay(attempt: 3), 6, accuracy: 0.001)
        XCTAssertEqual(BleReconnectPolicy.backoffDelay(attempt: 4), 12, accuracy: 0.001)
        XCTAssertEqual(BleReconnectPolicy.backoffDelay(attempt: 5), 15, accuracy: 0.001)
        XCTAssertEqual(BleReconnectPolicy.backoffDelay(attempt: 50), 15, accuracy: 0.001)
        XCTAssertEqual(BleReconnectPolicy.backoffDelay(attempt: 0), 0, accuracy: 0.001)
    }

    func testReconnectStopsAtAttemptLimit() {
        XCTAssertEqual(action(attempts: 0), .reconnect(delay: 1.5, attempt: 1))
        XCTAssertEqual(action(attempts: 6), .reconnect(delay: 15, attempt: 7))
        guard case .stopped(let message) = action(attempts: 8) else {
            return XCTFail("8 denemeden sonra durmalı")
        }
        XCTAssertTrue(message.contains("8"))
    }

    func testForegroundRetryRequiresAllConditions() {
        XCTAssertTrue(BleReconnectPolicy.shouldRetryOnForeground(
            autoConnectEnabled: true, radioAvailable: true, stateDisconnectedOrFailed: true,
            sinceLastStart: 10, hasPendingTimerOrDisconnected: true))

        // Son denemeden 3 sn geçmeden tekrar denenmez.
        XCTAssertFalse(BleReconnectPolicy.shouldRetryOnForeground(
            autoConnectEnabled: true, radioAvailable: true, stateDisconnectedOrFailed: true,
            sinceLastStart: 2.9, hasPendingTimerOrDisconnected: true))
        // Hiç denenmemişse soğuma yok.
        XCTAssertTrue(BleReconnectPolicy.shouldRetryOnForeground(
            autoConnectEnabled: true, radioAvailable: true, stateDisconnectedOrFailed: true,
            sinceLastStart: nil, hasPendingTimerOrDisconnected: true))
        // Radyo kapalı / otomatik bağlantı kapalı / bağlıyken atlanır.
        XCTAssertFalse(BleReconnectPolicy.shouldRetryOnForeground(
            autoConnectEnabled: true, radioAvailable: false, stateDisconnectedOrFailed: true,
            sinceLastStart: 10, hasPendingTimerOrDisconnected: true))
        XCTAssertFalse(BleReconnectPolicy.shouldRetryOnForeground(
            autoConnectEnabled: false, radioAvailable: true, stateDisconnectedOrFailed: true,
            sinceLastStart: 10, hasPendingTimerOrDisconnected: true))
        XCTAssertFalse(BleReconnectPolicy.shouldRetryOnForeground(
            autoConnectEnabled: true, radioAvailable: true, stateDisconnectedOrFailed: false,
            sinceLastStart: 10, hasPendingTimerOrDisconnected: true))
        XCTAssertFalse(BleReconnectPolicy.shouldRetryOnForeground(
            autoConnectEnabled: true, radioAvailable: true, stateDisconnectedOrFailed: true,
            sinceLastStart: 10, hasPendingTimerOrDisconnected: false))
    }

    func testPolicyIsSideEffectFree() {
        // Aynı girdiler her zaman aynı kararı verir (durum makinesi deterministik).
        let first = action(attempts: 2)
        let second = action(attempts: 2)
        XCTAssertEqual(first, second)
    }
}
