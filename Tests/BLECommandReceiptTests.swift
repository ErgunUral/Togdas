import XCTest
@testable import ToqdasCore

final class BLECommandReceiptTests: XCTestCase {
    func testPhaseTitlesAreUserFacing() {
        XCTAssertEqual(BLECommandReceipt.Phase.queued.title, "Sıraya alındı")
        XCTAssertEqual(BLECommandReceipt.Phase.sent.title, "Gönderildi")
        XCTAssertEqual(BLECommandReceipt.Phase.acknowledged.title, "Araç aldı")
        XCTAssertEqual(BLECommandReceipt.Phase.verified.title, "Doğrulandı")
        XCTAssertEqual(BLECommandReceipt.Phase.failed.title, "Başarısız")
    }

    func testSummaryCombinesActionAndPhase() {
        let receipt = BLECommandReceipt(
            code: 2,
            action: "Kilidi aç",
            phase: .acknowledged,
            detail: "Araç komutu aldı.",
            updatedAt: Date()
        )
        XCTAssertEqual(receipt.summary, "Kilidi aç · Araç aldı")
        XCTAssertFalse(receipt.phase.isFailure)
    }

    func testFailurePhaseIsMarked() {
        let receipt = BLECommandReceipt(
            code: 4,
            action: "Bagajı aç",
            phase: .failed,
            detail: "Araç komut yanıtı göndermedi.",
            updatedAt: Date()
        )
        XCTAssertTrue(receipt.phase.isFailure)
        XCTAssertEqual(receipt.summary, "Bagajı aç · Başarısız")
    }
}
