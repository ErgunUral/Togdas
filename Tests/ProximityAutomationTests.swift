import XCTest
@testable import ToqdasCore

final class ProximityAutomationTests: XCTestCase {
    func testAutoOffDeadlineOnlyAcceptsValidMinuteRangeAndExpiresAtBoundary() {
        let start = Date(timeIntervalSince1970: 1_000)
        let deadline = ProximityAutoOffPolicy.deadline(startedAt: start, durationMinutes: 5)!
        XCTAssertEqual(deadline, start.addingTimeInterval(300))
        XCTAssertFalse(ProximityAutoOffPolicy.isExpired(deadline, now: deadline.addingTimeInterval(-1)))
        XCTAssertTrue(ProximityAutoOffPolicy.isExpired(deadline, now: deadline))
        XCTAssertNotNil(ProximityAutoOffPolicy.deadline(startedAt: start, durationMinutes: 1_440))
        XCTAssertNil(ProximityAutoOffPolicy.deadline(startedAt: start, durationMinutes: 0))
        XCTAssertNil(ProximityAutoOffPolicy.deadline(startedAt: start, durationMinutes: 1_441))
    }

    func testCalibrationRequiresStrongNearFarSeparationAndAddsHysteresis() {
        let calibration = ProximityCalibration(nearSample: -75, farSample: -95)
        XCTAssertTrue(calibration.isValid)
        XCTAssertEqual(calibration.nearThreshold, -82)
        XCTAssertEqual(calibration.farThreshold, -88)

        let tooClose = ProximityCalibration(nearSample: -88, farSample: -99)
        XCTAssertFalse(tooClose.isValid)
        XCTAssertNil(tooClose.nearThreshold)
        XCTAssertNil(tooClose.farThreshold)
    }

    func testGateRequiresTwoSamplesAndHysteresisPreventsFlapping() {
        let calibration = ProximityCalibration(nearSample: -75, farSample: -95)
        var gate = ProximityGate(calibration: calibration)

        XCTAssertNil(gate.update(rssi: -80))
        XCTAssertEqual(gate.update(rssi: -80), .approached)
        XCTAssertEqual(gate.presence, .near)

        XCTAssertNil(gate.update(rssi: -85)) // Hysteresis band
        XCTAssertEqual(gate.presence, .near)
        XCTAssertNil(gate.update(rssi: -85))

        XCTAssertNil(gate.update(rssi: -90))
        XCTAssertEqual(gate.update(rssi: -90), .departed)
        XCTAssertEqual(gate.presence, .far)
    }

    func testInitialFarStateDoesNotTriggerLockAndInvalidCalibrationNeverTransitions() {
        var gate = ProximityGate(calibration: ProximityCalibration(nearSample: -75, farSample: -95))
        XCTAssertNil(gate.update(rssi: -95))
        XCTAssertNil(gate.update(rssi: -95))
        XCTAssertEqual(gate.presence, .far)

        var invalidGate = ProximityGate(calibration: ProximityCalibration(nearSample: -88, farSample: -99))
        XCTAssertNil(invalidGate.update(rssi: -50))
        XCTAssertEqual(invalidGate.presence, .unknown)
    }

    func testProfilesExposeDifferentLatencyAndFilteringPolicies() {
        XCTAssertEqual(ProximityProfile.balanced.requiredSamples, 2)
        XCTAssertEqual(ProximityProfile.fast.requiredSamples, 1)
        XCTAssertEqual(ProximityProfile.aggressive.requiredSamples, 1)
        XCTAssertEqual(ProximityProfile.fast.pollInterval, 1)
        XCTAssertEqual(ProximityProfile.balanced.pollInterval, 2)

        let calibration = ProximityCalibration(nearSample: -75, farSample: -95)
        var fast = ProximityGate(calibration: calibration, profile: .fast)
        XCTAssertEqual(fast.update(rssi: -80), .approached)

        var predictive = ProximityGate(calibration: calibration, profile: .predictive)
        XCTAssertNil(predictive.update(rssi: -90))
        XCTAssertNil(predictive.update(rssi: -85))
        XCTAssertEqual(predictive.update(rssi: -81), .approached)

        var kalman = ProximityGate(calibration: calibration, profile: .kalman)
        XCTAssertNil(kalman.update(rssi: -90))
        XCTAssertNil(kalman.update(rssi: -75))
        XCTAssertEqual(kalman.update(rssi: -75), .approached)
    }
}
