import XCTest
@testable import ToqdasCore

final class BleTimeoutPolicyTests: XCTestCase {
    func testStrongSignalKeepsBaseTimeout() {
        XCTAssertEqual(BleTimeoutPolicy.scaled(6, lastRSSI: -60), 6)
        XCTAssertEqual(BleTimeoutPolicy.scaled(10, lastRSSI: -85), 10)
    }

    func testUnknownSignalKeepsBaseTimeout() {
        XCTAssertEqual(BleTimeoutPolicy.scaled(8, lastRSSI: nil), 8)
    }

    func testWeakSignalExtendsHandshakeWindows() {
        XCTAssertEqual(BleTimeoutPolicy.scaled(6, lastRSSI: -91), 9)
        XCTAssertEqual(BleTimeoutPolicy.scaled(10, lastRSSI: -91), 15)
        XCTAssertEqual(BleTimeoutPolicy.scaled(8, lastRSSI: -95), 12)
    }

    func testWeakTimeoutIsCapped() {
        XCTAssertEqual(BleTimeoutPolicy.scaled(16, lastRSSI: -97), 20)
    }
}
