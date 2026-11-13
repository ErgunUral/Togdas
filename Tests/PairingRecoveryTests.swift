import XCTest
@testable import ToqdasCore

/// `PairingRecovery`: eşleşme geçersiz kurtarma rehberi. Metin cihaz
/// ayarlarına yönlendirmeli, komut vaat etmemeli ve VIN içermemeli.
final class PairingRecoveryTests: XCTestCase {

    func testStepsAreCompleteAndOrdered() {
        XCTAssertEqual(PairingRecovery.steps.count, 3)
        XCTAssertTrue(PairingRecovery.steps[0].contains("Bluetooth"))
        XCTAssertTrue(PairingRecovery.steps[0].contains("unut"))
        XCTAssertTrue(PairingRecovery.steps[1].contains("Araç ekranından"))
        XCTAssertTrue(PairingRecovery.steps[2].contains("eşleştirmeyi başlat"))
    }

    func testSummaryStatesAutomationIsBlocked() {
        // Davranışa sadakat: eşleşme geçersizken otomasyon çalışmaz.
        XCTAssertTrue(PairingRecovery.summary.contains("otomatik kilit/açma çalışmaz"))
    }

    func testNotificationBodyContainsAllSteps() {
        for step in PairingRecovery.steps {
            XCTAssertTrue(PairingRecovery.notificationBody.contains(step))
        }
        XCTAssertTrue(PairingRecovery.notificationBody.contains("otomatik komut gönderilmez"))
    }

    func testDraftHasNoVINInVisibleText() {
        let draft = PairingRecovery.notificationDraft(vin: "NL1CSU0P60G064536")
        XCTAssertEqual(draft.title, PairingRecovery.title)
        XCTAssertFalse(draft.title.contains("NL1CSU0P60G064536"))
        XCTAssertFalse(draft.body.contains("NL1CSU0P60G064536"))
        XCTAssertEqual(draft.identifier, "pairing-recovery-NL1CSU0P60G064536")
        XCTAssertFalse(draft.timeSensitive)
    }

    func testDraftIdentifierIsStablePerVIN() {
        XCTAssertEqual(PairingRecovery.notificationDraft(vin: "A").identifier,
                       PairingRecovery.notificationDraft(vin: "A").identifier)
        XCTAssertNotEqual(PairingRecovery.notificationDraft(vin: "A").identifier,
                          PairingRecovery.notificationDraft(vin: "B").identifier)
    }
}
