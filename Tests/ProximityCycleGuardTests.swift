import XCTest
@testable import ToqdasCore

/// `ProximityCycleGuard`: Android 1.0.24.57 oto kilit akışındaki
/// uzak↔geri-yaklaşma döngü korumalarının iOS çekirdek testi.
///
/// Protokol: `decideApproach` bilet alır (`.sendUnlock`) ve bileti sayar;
/// gönderim başarılıysa `noteUnlockIssued` çağrılır (yeni açma için uzaklaşma
/// şartı), başarısızsa `noteAmbiguity` (bilet iptal + 30 sn hold) çağrılır.
final class ProximityCycleGuardTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_791_000_000)

    func testApproachWithoutConfirmedDepartureIsDenied() {
        var guardState = ProximityCycleGuard()
        XCTAssertEqual(
            guardState.decideApproach(now: base),
            .deny(reason: "Yeni uzak-geri yaklaşma kanıtı gerekli; açma gönderilmedi.")
        )
        XCTAssertFalse(guardState.unlockTicket)
    }

    func testDepartureThenApproachIssuesUnlockAndRequiresNewCycle() {
        var guardState = ProximityCycleGuard()
        guardState.noteDepartureConfirmed(now: base)
        XCTAssertEqual(guardState.decideApproach(now: base.addingTimeInterval(2)), .sendUnlock)
        XCTAssertTrue(guardState.unlockTicket)
        // Aynı yakınlıkta ikinci karar düşer: bilet tek kullanım.
        XCTAssertEqual(
            guardState.decideApproach(now: base.addingTimeInterval(3)),
            .deny(reason: "Bu yaklaşmada açma zaten gönderildi.")
        )
        guardState.noteUnlockIssued()
        XCTAssertFalse(guardState.unlockTicket)
        // Gönderim sonrası yeni açma için teyitli uzaklaşma şart.
        XCTAssertEqual(
            guardState.decideApproach(now: base.addingTimeInterval(5)),
            .deny(reason: "Yeni uzak-geri yaklaşma kanıtı gerekli; açma gönderilmedi.")
        )
        guardState.noteDepartureConfirmed(now: base.addingTimeInterval(30))
        XCTAssertEqual(guardState.decideApproach(now: base.addingTimeInterval(40)), .sendUnlock)
    }

    func testAmbiguityCancelsTicketAndHoldsThenPostHoldApproachArms() {
        var guardState = ProximityCycleGuard()
        guardState.noteDepartureConfirmed(now: base)
        guardState.decideApproach(now: base.addingTimeInterval(2))
        // Gönderim başarısız: bileti iptal + 30 sn hold.
        guardState.noteAmbiguity(now: base.addingTimeInterval(3))
        XCTAssertFalse(guardState.unlockTicket)
        XCTAssertEqual(
            guardState.decideApproach(now: base.addingTimeInterval(20)),
            .deny(reason: "Belirsiz geçiş guard'ı 30 sn açmayı bekletiyor.")
        )
        XCTAssertEqual(
            guardState.decideApproach(now: base.addingTimeInterval(32)),
            .deny(reason: "Belirsiz geçiş guard'ı 30 sn açmayı bekletiyor.")
        )
        // Hold bitiminde gelen yeni yaklaşma bilet alır.
        XCTAssertEqual(guardState.decideApproach(now: base.addingTimeInterval(35)), .sendUnlock)
    }

    func testDepartureClearsHold() {
        var guardState = ProximityCycleGuard()
        guardState.noteAmbiguity(now: base)
        guardState.noteDepartureConfirmed(now: base.addingTimeInterval(5))
        XCTAssertNil(guardState.holdUntil)
        XCTAssertEqual(guardState.decideApproach(now: base.addingTimeInterval(6)), .sendUnlock)
    }
}
