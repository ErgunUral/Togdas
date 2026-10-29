import XCTest
import CoreBluetooth
@testable import ToqdasCore

/// Android 1.0.24.42'nin GATT hata gruplarının iOS karşılığı.
final class BleFailureTests: XCTestCase {
    func testTimeoutIsSignalFailure() {
        let kind = BleFailureClassifier.classify(
            domain: CBErrorDomain,
            code: CBError.Code.connectionTimeout.rawValue
        )
        XCTAssertEqual(kind, .signal)
        XCTAssertEqual(kind.summary, "Sinyal zayıf · bağlantı koptu")
        XCTAssertFalse(kind.requiresRepair)
    }

    func testVehicleClosingIsPeerClosed() {
        let kind = BleFailureClassifier.classify(
            domain: CBErrorDomain,
            code: CBError.Code.peripheralDisconnected.rawValue
        )
        XCTAssertEqual(kind, .peerClosed)
        XCTAssertFalse(kind.requiresRepair)
    }

    func testRemovedPairingRequiresRepair() {
        for code in [CBError.Code.peerRemovedPairingInformation,
                     CBError.Code.encryptionTimedOut] {
            let kind = BleFailureClassifier.classify(domain: CBErrorDomain, code: code.rawValue)
            XCTAssertEqual(kind, .pairingLost)
            XCTAssertTrue(kind.requiresRepair)
        }
    }

    func testAuthenticationErrorsArePairingLost() {
        for code in [CBATTError.Code.insufficientAuthentication,
                     CBATTError.Code.insufficientEncryption,
                     CBATTError.Code.insufficientAuthorization] {
            XCTAssertEqual(
                BleFailureClassifier.classify(domain: CBATTErrorDomain, code: code.rawValue),
                .pairingLost
            )
        }
    }

    func testOtherGATTErrorsAreGroupedAsGATT() {
        let kind = BleFailureClassifier.classify(
            domain: CBATTErrorDomain,
            code: CBATTError.Code.invalidHandle.rawValue
        )
        XCTAssertEqual(kind, .gatt)
    }

    func testNilErrorMeansVehicleClosed() {
        XCTAssertEqual(BleFailureClassifier.classify(nil), .peerClosed)
    }

    func testUnknownDomainIsUnknown() {
        XCTAssertEqual(BleFailureClassifier.classify(domain: "NSPOSIXErrorDomain", code: -1), .unknown)
    }

    func testCounterCountsWithinWindow() {
        var counter = BleFailureCounter(window: 60)
        let start = Date()
        XCTAssertEqual(counter.record(.signal, at: start), 1)
        XCTAssertEqual(counter.record(.signal, at: start.addingTimeInterval(10)), 2)
        XCTAssertEqual(counter.record(.signal, at: start.addingTimeInterval(20)), 3)
        XCTAssertEqual(counter.total(at: start.addingTimeInterval(20)), 3)
        // Pencere dışına çıkanlar sayılmaz.
        XCTAssertEqual(counter.count(.signal, at: start.addingTimeInterval(50)), 3)
        XCTAssertEqual(counter.total(at: start.addingTimeInterval(90)), 0)
    }

    func testCounterSeparatesKinds() {
        var counter = BleFailureCounter(window: 60)
        let now = Date()
        counter.record(.signal, at: now)
        counter.record(.signal, at: now)
        let count = counter.record(.peerClosed, at: now)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(counter.count(.signal, at: now), 2)
    }

    func testCounterResetClearsEntries() {
        var counter = BleFailureCounter()
        counter.record(.gatt)
        counter.reset()
        XCTAssertEqual(counter.total(), 0)
    }

    /// Android'deki "PI → normal devir" karşılığı: iki evre, ikincisi ısrarlı.
    func testScanPolicyHasStubbornSecondPhase() {
        XCTAssertEqual(BleScanPolicy.phases.count, 2)
        XCTAssertFalse(BleScanPolicy.phases[0].allowDuplicates)
        XCTAssertTrue(BleScanPolicy.phases[1].allowDuplicates)
        XCTAssertEqual(BleScanPolicy.totalWindow, 24)
        XCTAssertEqual(BleScanPolicy.phases[1].name, "ısrarlı")
    }
}
