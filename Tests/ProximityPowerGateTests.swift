import XCTest
@testable import ToqdasCore

/// `ProximityPowerGate`: otomasyon yalnız aksesuar/hazır durumda durur.
/// Park hâlinde araç 0/1 bildiriyor ve kilit komutu uygulanıyor (cihaz kanıtı).
final class ProximityPowerGateTests: XCTestCase {
    func testAllowsStandbyMeasurement() {
        XCTAssertTrue(ProximityPowerGate.allowsAutomation(powerState: 2))
    }

    func testAllowsUnknownSleepStates() {
        // 0/1: araç uykuya geçmiş; kilit bu durumda uygulanabiliyor.
        XCTAssertTrue(ProximityPowerGate.allowsAutomation(powerState: 0))
        XCTAssertTrue(ProximityPowerGate.allowsAutomation(powerState: 1))
        XCTAssertTrue(ProximityPowerGate.allowsAutomation(powerState: nil))
    }

    func testBlocksAccessoryAndReady() {
        XCTAssertFalse(ProximityPowerGate.allowsAutomation(powerState: 3))
        XCTAssertFalse(ProximityPowerGate.allowsAutomation(powerState: 4))
    }

    func testBlockReasonsAreDistinctAndHonest() {
        XCTAssertNil(ProximityPowerGate.blockReason(powerState: 2))
        XCTAssertEqual(ProximityPowerGate.blockReason(powerState: 4),
                       "Araç hazır durumda; otomatik komut gönderilmedi.")
        XCTAssertEqual(ProximityPowerGate.blockReason(powerState: 3),
                       "Araç aksesuar durumunda; otomatik komut gönderilmedi.")
    }
}
