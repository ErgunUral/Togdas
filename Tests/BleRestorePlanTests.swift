import XCTest
@testable import ToqdasCore

/// `BleRestorePlan`: iOS CBCentralManager state restoration üzerinden
/// Android boot-paritesi taşınırken arka plan güvenlik invariant'ları.
final class BleRestorePlanTests: XCTestCase {
    func testNoRestoreEventMeansBaseline() {
        XCTAssertEqual(
            BleRestorePlan.evaluate(restoredCount: 0, systemConnected: true, isRadioOn: true).action,
            .none
        )
    }

    func testRadioOffBlocksAnyPlan() {
        XCTAssertEqual(
            BleRestorePlan.evaluate(restoredCount: 3, systemConnected: true, isRadioOn: false).action,
            .none
        )
    }

    func testRestoredConnectedPeripheralResumesSession() {
        let plan = BleRestorePlan.evaluate(restoredCount: 1, systemConnected: true, isRadioOn: true)
        XCTAssertEqual(plan.action, .resumeSession)
    }

    func testRestoredDisconnectedPeripheralRequiresReconnect() {
        let plan = BleRestorePlan.evaluate(restoredCount: 2, systemConnected: false, isRadioOn: true)
        XCTAssertEqual(plan.action, .reconnect)
    }

    func testPlanNeverSendsCommands() {
        for action in [BleRestorePlan.Action.none, .resumeSession, .reconnect] {
            XCTAssertFalse(BleRestorePlan(action: action).sendsCommand)
        }
    }
}
