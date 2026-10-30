import XCTest
@testable import ToqdasCore

final class BLECommandHistoryStoreTests: XCTestCase {
    private func receipt(_ index: Int, phase: BLECommandReceipt.Phase = .queued) -> BLECommandReceipt {
        BLECommandReceipt(
            code: 2,
            action: "Komut \(index)",
            phase: phase,
            detail: "detay \(index)",
            updatedAt: Date(timeIntervalSince1970: TimeInterval(index))
        )
    }

    func testAppendKeepsNewestAndLimitsToTwenty() {
        var history: [BLECommandReceipt] = []
        for index in 0..<25 {
            history = BLECommandHistoryStore.append(receipt(index), to: history)
        }
        XCTAssertEqual(history.count, BLECommandHistoryStore.limit)
        XCTAssertEqual(history.first?.action, "Komut 24")
        XCTAssertEqual(history.last?.action, "Komut 5")
    }

    func testUpdateReplacesMatchingReceipt() {
        let original = receipt(1)
        var history = BLECommandHistoryStore.append(original, to: [])
        var updated = original
        updated.phase = .verified
        updated.detail = "doğrulandı"
        history = BLECommandHistoryStore.update(updated, in: history)

        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].phase, .verified)
        XCTAssertEqual(history[0].detail, "doğrulandı")
    }

    func testRoundTripThroughUserDefaults() {
        let suiteName = "BLECommandHistoryStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let value = receipt(7, phase: .acknowledged)
        BLECommandHistoryStore.save([value], to: defaults)
        let loaded = BLECommandHistoryStore.load(from: defaults)

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, value.id)
        XCTAssertEqual(loaded.first?.phase, .acknowledged)
    }
}
