import XCTest
@testable import ToqdasCore

final class TirePressurePolicyTests: XCTestCase {
    private func tire(_ position: TirePosition, _ psi: Double?) -> TireReading {
        TireReading(position: position, pressurePSI: psi, temperatureC: 25)
    }

    func testMissingMeasurementsProduceNoAlert() {
        let policy = TirePressurePolicy.default
        XCTAssertTrue(policy.alerts(for: [tire(.frontLeft, nil)]).isEmpty)
        XCTAssertTrue(policy.alerts(for: [tire(.frontLeft, 0)]).isEmpty)
        XCTAssertTrue(policy.alerts(for: [tire(.frontLeft, .nan)]).isEmpty)
    }

    func testLowAndCriticalSeverity() {
        let policy = TirePressurePolicy(lowThresholdPSI: 30, criticalThresholdPSI: 26)
        let alerts = policy.alerts(for: [
            tire(.frontLeft, 24),
            tire(.frontRight, 28),
            tire(.rearLeft, 33)
        ])
        XCTAssertEqual(alerts.count, 2)
        XCTAssertEqual(alerts.first { $0.position == .frontLeft }?.severity, .critical)
        XCTAssertEqual(alerts.first { $0.position == .frontRight }?.severity, .low)
    }

    func testThresholdIsClampedToAllowedRange() {
        XCTAssertEqual(TirePressurePolicy(lowThresholdPSI: 5, criticalThresholdPSI: 1).lowThresholdPSI, 20)
        XCTAssertEqual(TirePressurePolicy(lowThresholdPSI: 90, criticalThresholdPSI: 80).lowThresholdPSI, 40)
    }

    func testCriticalAlwaysBelowLow() {
        let policy = TirePressurePolicy(lowThresholdPSI: 30, criticalThresholdPSI: 35)
        XCTAssertLessThan(policy.criticalThresholdPSI, policy.lowThresholdPSI)
    }

    func testSettingsPersistAndDefault() {
        let suite = "toqdas.tire.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        let settings = TirePressureSettings(defaults: defaults)
        XCTAssertEqual(settings.policy, TirePressurePolicy.default)

        settings.policy = TirePressurePolicy(lowThresholdPSI: 34, criticalThresholdPSI: 30)
        XCTAssertEqual(settings.policy.lowThresholdPSI, 34)
        XCTAssertEqual(settings.policy.criticalThresholdPSI, 30)
    }
}
