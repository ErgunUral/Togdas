import XCTest
@testable import ToqdasCore

/// Faz modeli: tek doğru durum, öncelik sırası ve çelişkisiz gösterim.
final class BlePhaseTests: XCTestCase {
    private func phase(_ state: BleConnection.State,
                       needsRepair: Bool = false,
                       pairingRequired: Bool = false,
                       radioAvailable: Bool = true,
                       reconnecting: Bool = false,
                       telemetryFresh: Bool = true) -> BlePhase {
        BlePhaseMachine.phase(state: state,
                              needsRepair: needsRepair,
                              pairingRequired: pairingRequired,
                              radioAvailable: radioAvailable,
                              reconnecting: reconnecting,
                              telemetryFresh: telemetryFresh)
    }

    func testBasicStates() {
        XCTAssertEqual(phase(.disconnected), .idle)
        XCTAssertEqual(phase(.disconnected, reconnecting: true), .searching)
        XCTAssertEqual(phase(.connecting), .connecting)
        XCTAssertEqual(phase(.discovering), .connecting)
        XCTAssertEqual(phase(.certificate), .authenticating)
        XCTAssertEqual(phase(.challenge), .authenticating)
        XCTAssertEqual(phase(.authenticated), .authenticating)
        XCTAssertEqual(phase(.ready), .ready)
    }

    /// Onarım her şeyden önce gelir: "bağlı görünüp onarım isteyen" çelişki olmaz.
    func testRepairHasHighestPriority() {
        XCTAssertEqual(phase(.ready, needsRepair: true), .repairRequired)
        XCTAssertEqual(phase(.ready, needsRepair: true, radioAvailable: false), .repairRequired)
        XCTAssertEqual(phase(.failed(.pairingLost), needsRepair: true), .repairRequired)
    }

    func testRadioOffBeatsPairingWait() {
        XCTAssertEqual(phase(.disconnected, pairingRequired: true, radioAvailable: false), .radioOff)
        XCTAssertEqual(phase(.disconnected, pairingRequired: true), .pairingWait)
    }

    func testFailureWithoutRetryIsStopped() {
        XCTAssertEqual(phase(.failed(.pairingLost)), .stopped)
        XCTAssertEqual(phase(.failed(.connectionTimeout), reconnecting: true), .searching)
    }

    func testStaleTelemetryIsDegraded() {
        XCTAssertEqual(phase(.ready, telemetryFresh: false), .degraded)
        XCTAssertTrue(BlePhase.degraded.isConnected)
        XCTAssertTrue(BlePhase.ready.isConnected)
        XCTAssertFalse(BlePhase.searching.isConnected)
    }

    func testEveryPhaseHasLabel() {
        for item in BlePhase.allCases {
            XCTAssertFalse(item.label.isEmpty, "\(item.rawValue) etiketsiz")
        }
    }
}
