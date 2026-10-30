import XCTest
@testable import ToqdasCore

final class BLECommandPolicyTests: XCTestCase {
    private func telemetry(locked: Int = 1, receivedAt: Date) -> BleTelemetry {
        BleTelemetry(locked: locked, doors: [0, 0, 0, 0], trunkAjar: 0,
                     powerState: 2, counter: 1, receivedAt: receivedAt)
    }

    func testRejectsWhenLinkIsNotReady() {
        let now = Date()
        XCTAssertNotNil(BLECommandPolicy.rejectionReason(
            code: 2, linkReady: false, telemetry: telemetry(receivedAt: now), now: now
        ))
    }

    func testRejectsMissingStaleAndFutureTelemetry() {
        let now = Date()
        XCTAssertNotNil(BLECommandPolicy.rejectionReason(code: 2, linkReady: true, telemetry: nil, now: now))
        XCTAssertNotNil(BLECommandPolicy.rejectionReason(
            code: 2, linkReady: true, telemetry: telemetry(receivedAt: now.addingTimeInterval(-15)), now: now
        ))
        XCTAssertNotNil(BLECommandPolicy.rejectionReason(
            code: 2, linkReady: true, telemetry: telemetry(receivedAt: now.addingTimeInterval(1)), now: now
        ))
    }

    func testUnlockAndLockRequireKnownLockState() {
        let now = Date()
        let unknown = telemetry(locked: 0, receivedAt: now)
        XCTAssertNotNil(BLECommandPolicy.rejectionReason(code: 1, linkReady: true, telemetry: unknown, now: now))
        XCTAssertNotNil(BLECommandPolicy.rejectionReason(code: 2, linkReady: true, telemetry: unknown, now: now))
        XCTAssertNil(BLECommandPolicy.rejectionReason(code: 1, linkReady: true, telemetry: telemetry(receivedAt: now), now: now))
    }

    func testFreshTelemetryAllowsNonLockCommands() {
        let now = Date()
        let state = telemetry(locked: 0, receivedAt: now)
        for code in [4, 5, 6, 7, 14] {
            XCTAssertNil(BLECommandPolicy.rejectionReason(code: UInt8(code), linkReady: true, telemetry: state, now: now))
        }
    }

    func testTypedRejectionReasons() {
        let now = Date()
        XCTAssertEqual(
            BLECommandPolicy.rejection(code: 2, linkReady: false, telemetry: nil, now: now),
            .linkNotReady
        )
        XCTAssertEqual(
            BLECommandPolicy.rejection(code: 2, linkReady: true, telemetry: nil, now: now),
            .telemetryMissing
        )
        XCTAssertEqual(
            BLECommandPolicy.rejection(
                code: 2,
                linkReady: true,
                telemetry: telemetry(receivedAt: now.addingTimeInterval(-15)),
                now: now
            ),
            .telemetryStale
        )
        XCTAssertEqual(
            BLECommandPolicy.rejection(
                code: 1,
                linkReady: true,
                telemetry: telemetry(locked: 0, receivedAt: now),
                now: now
            ),
            .lockStateUnknown
        )
    }

    func testTypedRejectionCodesAndMessagesAreStable() {
        XCTAssertEqual(BLECommandRejection.linkNotReady.diagnosticCode, "link_not_ready")
        XCTAssertEqual(BLECommandRejection.telemetryMissing.diagnosticCode, "telemetry_missing")
        XCTAssertEqual(BLECommandRejection.telemetryStale.diagnosticCode, "telemetry_stale")
        XCTAssertEqual(BLECommandRejection.lockStateUnknown.diagnosticCode, "lock_state_unknown")
        XCTAssertEqual(
            BLECommandRejection.linkNotReady.message,
            "Dijital anahtar hazır değil; komut gönderilmedi."
        )
    }
}
