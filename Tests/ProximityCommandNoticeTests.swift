import XCTest
@testable import ToqdasCore

/// `ProximityCommandNotice`: otomatik yakınlık komutunun sonucunu bildirime
/// çeviren karar katmanı. Metin sözleşmesi `BleConnection.lastEvent` ile
/// uyumlu olmalı ve gövde/başlık VIN içermemeli.
final class ProximityCommandNoticeTests: XCTestCase {

    func testOutcomeRecognizesVerifiedEvents() {
        XCTAssertEqual(ProximityCommandNotice.outcome(forEvent: "Kapılar kilitli; araç durumuyla doğrulandı."), .verified)
        XCTAssertEqual(ProximityCommandNotice.outcome(forEvent: "Kapı kilitleri açık; araç durumuyla doğrulandı."), .verified)
        XCTAssertEqual(ProximityCommandNotice.outcome(forEvent: "Araç komutu onayladı; kilit durumu hedef değerle eşleşiyor."), .verified)
    }

    func testOutcomeRecognizesFailureEvent() {
        XCTAssertEqual(ProximityCommandNotice.outcome(forEvent: "Araç komutu onayladı ancak kilit değişikliği doğrulanamadı."), .failed)
    }

    func testOutcomeIgnoresUnrelatedEvents() {
        XCTAssertNil(ProximityCommandNotice.outcome(forEvent: "Bağlantı durumu: Komut hazır"))
        XCTAssertNil(ProximityCommandNotice.outcome(forEvent: "aracın kapıları açıldı"))
        XCTAssertNil(ProximityCommandNotice.outcome(forEvent: ""))
    }

    func testLockFailureDraftIsFaithfulToBehavior() {
        let draft = ProximityCommandNotice.failureDraft(kind: .lock, failure: .notVerified, vin: "VIN123")
        XCTAssertEqual(draft.title, "Otomatik kilitleme doğrulanamadı")
        XCTAssertTrue(draft.body.contains("Komut yeniden gönderilmedi"))
        XCTAssertTrue(draft.body.contains("Kapılar açık olabilir"))
        XCTAssertEqual(draft.identifier, "proximity-command-lock-failed-VIN123")
        XCTAssertFalse(draft.timeSensitive)
        XCTAssertTrue(draft.sound)
    }

    func testUnlockStartFailureDraft() {
        let draft = ProximityCommandNotice.failureDraft(kind: .unlock, failure: .notStarted, vin: "VIN123")
        XCTAssertEqual(draft.title, "Otomatik kilit açma başlatılamadı")
        XCTAssertTrue(draft.body.contains("gönderilemedi"))
        XCTAssertEqual(draft.identifier, "proximity-command-unlock-failed-VIN123")
    }

    func testDraftTextContainsNoVIN() {
        // Gizlilik invariant'ı: başlık/gövde VIN içermez; kimlik içerebilir.
        for kind in [ProximityCommandNotice.Kind.lock, .unlock] {
            for failure in [ProximityCommandNotice.Failure.notVerified, .notStarted] {
                let draft = ProximityCommandNotice.failureDraft(kind: kind, failure: failure, vin: "NL1CSU0P60G064536")
                XCTAssertFalse(draft.title.contains("NL1CSU0P60G064536"))
                XCTAssertFalse(draft.body.contains("NL1CSU0P60G064536"))
            }
        }
    }

    func testIdentifierIsStablePerKindAndVin() {
        let first = ProximityCommandNotice.failureDraft(kind: .lock, failure: .notVerified, vin: "A")
        let second = ProximityCommandNotice.failureDraft(kind: .lock, failure: .notStarted, vin: "A")
        // Aynı kimlik: yeni bildirim eskisini değiştirir (yığılma yok).
        XCTAssertEqual(first.identifier, second.identifier)
        let otherVin = ProximityCommandNotice.failureDraft(kind: .lock, failure: .notVerified, vin: "B")
        XCTAssertNotEqual(first.identifier, otherVin.identifier)
    }
}
