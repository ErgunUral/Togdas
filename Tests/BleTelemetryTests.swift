import XCTest
@testable import ToqdasCore

final class BleTelemetryTests: XCTestCase {
    private func telemetry(locked: Int = 1, doors: [Int] = [0, 0, 0, 0],
                           trunk: Int = 0, power: Int = 2) -> BleTelemetry {
        BleTelemetry(locked: locked, doors: doors, trunkAjar: trunk,
                     powerState: power, counter: 0, receivedAt: Date(timeIntervalSince1970: 0))
    }

    func testLockMappingUsesOfficialValues() {
        XCTAssertEqual(telemetry(locked: 1).isLocked, true)
        XCTAssertEqual(telemetry(locked: 2).isLocked, false)
        XCTAssertNil(telemetry(locked: 0).isLocked)
        XCTAssertEqual(telemetry(locked: 1).lockText, "Kilitli")
        XCTAssertEqual(telemetry(locked: 99).lockText, "Kilit durumu doğrulanıyor")
    }

    func testDoorReadingsAndText() {
        XCTAssertEqual(telemetry(doors: [0, 1, 0, 2]).openDoorCount, 2)
        XCTAssertEqual(telemetry(doors: [0, 1, 0, 2]).doorsText, "Kapı 2, Kapı 4 açık")
        XCTAssertEqual(telemetry(doors: [0, 0, 0, 0]).doorsText, "Tüm kapılar kapalı")
        XCTAssertEqual(telemetry(doors: [0, 1]).doorsText, "Kapı durumu doğrulanıyor")
        XCTAssertEqual(telemetry(doors: [0, 1]).openDoorCount, 1)
    }

    func testSecurityWarningCombinesOpenItems() {
        XCTAssertNil(telemetry(locked: 1, doors: [0, 0, 0, 0], trunk: 0, power: 4).securityWarning)
        XCTAssertEqual(telemetry(locked: 2, doors: [0, 1, 0, 0], trunk: 1).securityWarning,
                       "Kapı 2 açık · Bagaj açık")
        XCTAssertEqual(telemetry(locked: 2, doors: [0, 0, 0, 0], trunk: 0, power: 2).securityWarning,
                       "Araç beklemede ve kilit açık")
        XCTAssertNil(telemetry(locked: 1, doors: [0, 0, 0, 0], trunk: 0, power: 2).securityWarning)
    }

    func testPowerStateMapping() {
        XCTAssertEqual(telemetry(power: 2).powerStateText, "Bekleme")
        XCTAssertEqual(telemetry(power: 3).powerStateText, "Aksesuar")
        XCTAssertEqual(telemetry(power: 4).powerStateText, "Hazır")
        XCTAssertEqual(telemetry(power: 9).powerStateText, "Durum doğrulanıyor")
    }
}
