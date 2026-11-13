import XCTest
@testable import ToqdasCore

/// Bütçe: tek yerde tutulan sayaçlar; sıfırlama kuralları açık.
final class ReconnectBudgetTests: XCTestCase {
    func testStartsAtZero() {
        let budget = ReconnectBudget()
        XCTAssertEqual(budget, ReconnectBudget(attempts: 0, weakDrops: 0, pairingAttempts: 0))
    }

    func testWeakDropsAccumulateAndResetOnNewCycle() {
        var budget = ReconnectBudget()
        XCTAssertEqual(budget.noteWeakDrop(), 1)
        XCTAssertEqual(budget.noteWeakDrop(), 2)
        budget.startAttempt(2)
        budget.resetAttempts()
        XCTAssertEqual(budget.weakDrops, 0)
        XCTAssertEqual(budget.attempts, 0)
    }

    func testStableResetsEverythingIncludingPairing() {
        var budget = ReconnectBudget()
        budget.notePairingWait()
        budget.startAttempt(3)
        budget.noteWeakDrop()
        budget.resetAll()
        XCTAssertEqual(budget, ReconnectBudget(attempts: 0, weakDrops: 0, pairingAttempts: 0))
    }

    func testResetAttemptsKeepsPairingCounter() {
        var budget = ReconnectBudget()
        budget.notePairingWait()
        budget.notePairingWait()
        budget.resetAttempts()
        XCTAssertEqual(budget.pairingAttempts, 2)
    }

    func testNegativeAttemptIsClamped() {
        var budget = ReconnectBudget()
        budget.startAttempt(-5)
        XCTAssertEqual(budget.attempts, 0)
    }
}
