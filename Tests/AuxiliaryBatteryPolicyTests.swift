import XCTest
@testable import ToqdasCore

/// `AuxiliaryBatteryPolicy`: 12 V akü yüzdesinden uyarı üretimi.
/// Invariantlar: eksik veri → nil (asla uyarı değil); gerçek 0 → kritik;
/// eşikler karışmaz (25 kritik, 40 uyarı, 41+ temiz).
final class AuxiliaryBatteryPolicyTests: XCTestCase {
    func testMissingOrInvalidValuesProduceNoAlert() {
        XCTAssertNil(AuxiliaryBatteryPolicy.assess(nil))
        XCTAssertNil(AuxiliaryBatteryPolicy.assess(.infinity))
        XCTAssertNil(AuxiliaryBatteryPolicy.assess(.nan))
        XCTAssertNil(AuxiliaryBatteryPolicy.assess(-1))
        XCTAssertNil(AuxiliaryBatteryPolicy.assess(101))
    }

    func testBoundaryThresholds() {
        XCTAssertEqual(AuxiliaryBatteryPolicy.assess(25)?.severity, .critical)
        XCTAssertEqual(AuxiliaryBatteryPolicy.assess(26)?.severity, .warning)
        XCTAssertEqual(AuxiliaryBatteryPolicy.assess(40)?.severity, .warning)
        XCTAssertNil(AuxiliaryBatteryPolicy.assess(41))
        XCTAssertNil(AuxiliaryBatteryPolicy.assess(85))
    }

    func testRealZeroIsCriticalNotMissing() {
        let assessment = AuxiliaryBatteryPolicy.assess(0)
        XCTAssertEqual(assessment?.percent, 0)
        XCTAssertEqual(assessment?.severity, .critical)
        XCTAssertEqual(assessment?.isCritical, true)
    }

    func testRoundingIsStable() {
        XCTAssertEqual(AuxiliaryBatteryPolicy.assess(24.4)?.percent, 24)
        XCTAssertEqual(AuxiliaryBatteryPolicy.assess(24.6)?.percent, 25)
        // 24.6 → 25 → kritik eşik dahil.
        XCTAssertEqual(AuxiliaryBatteryPolicy.assess(24.6)?.severity, .critical)
    }
}
