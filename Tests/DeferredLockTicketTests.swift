import XCTest
@testable import ToqdasCore

/// `DeferredLockTicket`: araç, dijital anahtar yakınken kilit komutunu
/// uygulamıyor (ölçüm: yakın 7/7 red, uzak 6/6 uygulama). Bilet, tek
/// komutu sinyal zayıfladığı an göndermek için kullanılır.
final class DeferredLockTicketTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func decide(
        rssi: Int? = -90,
        secondsLater: TimeInterval = 5,
        isLocked: Bool? = false,
        telemetryAge: TimeInterval? = 2,
        recentLock: Bool = false
    ) -> DeferredLockTicket.Decision {
        let ticket = DeferredLockTicket(armedAt: start)
        return ticket.decide(
            rssi: rssi,
            now: start.addingTimeInterval(secondsLater),
            isLocked: isLocked,
            telemetryAge: telemetryAge,
            recentLock: recentLock
        )
    }

    func testSendsWhenSignalWeakAndTelemetryFresh() {
        XCTAssertEqual(decide(), .send)
    }

    func testWaitsWhileKeyIsNearVehicle() {
        XCTAssertEqual(decide(rssi: -60), .wait)
        XCTAssertEqual(decide(rssi: -84), .wait)
    }

    func testSendsAtWeakSignalThreshold() {
        XCTAssertEqual(decide(rssi: BleReconnectPolicy.weakSignalThreshold), .send)
    }

    func testWaitsWithoutRSSISample() {
        XCTAssertEqual(decide(rssi: nil), .wait)
    }

    func testWaitsWhenTelemetryIsStaleOrMissing() {
        XCTAssertEqual(decide(telemetryAge: 15), .wait)
        XCTAssertEqual(decide(telemetryAge: nil), .wait)
    }

    func testWaitsWhenLockStateIsUnknown() {
        XCTAssertEqual(decide(isLocked: nil), .wait)
    }

    func testCancelsWhenVehicleIsAlreadyLocked() {
        guard case .cancel(let reason) = decide(isLocked: true) else {
            return XCTFail("kilitli araçta bilet kapanmalı")
        }
        XCTAssertTrue(reason.contains("zaten kilitli"))
    }

    func testCancelsAfterDeadline() {
        guard case .cancel(let reason) = decide(secondsLater: DeferredLockTicket.duration) else {
            return XCTFail("süre dolunca bilet iptal edilmeli")
        }
        XCTAssertTrue(reason.contains("süresi doldu"))
    }

    func testCancelsWhenAnotherSourceJustLocked() {
        guard case .cancel(let reason) = decide(recentLock: true) else {
            return XCTFail("çift komut engellenmeli")
        }
        XCTAssertTrue(reason.contains("çift komut"))
    }
}
