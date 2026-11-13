import XCTest
@testable import ToqdasCore

/// `AutomaticCommandLedger`: yakınlık ↔ geofence çakışma koruması.
@MainActor
final class AutomaticCommandLedgerTests: XCTestCase {
    private var ledger: AutomaticCommandLedger!

    override func setUp() async throws {
        try await super.setUp()
        ledger = AutomaticCommandLedger()
    }

    func testRecentWithinWindow() {
        let now = Date()
        ledger.note(source: .proximity, action: "unlock", vin: "V", at: now)
        XCTAssertEqual(ledger.recent(action: "unlock", vin: "V", within: 60, now: now.addingTimeInterval(10))?.source,
                       .proximity)
    }

    func testExpiredEntryIsIgnored() {
        let now = Date()
        ledger.note(source: .proximity, action: "unlock", vin: "V", at: now)
        XCTAssertNil(ledger.recent(action: "unlock", vin: "V", within: 60, now: now.addingTimeInterval(61)))
    }

    func testActionsAreIndependent() {
        let now = Date()
        ledger.note(source: .geofence, action: "lock", vin: "V", at: now)
        XCTAssertNil(ledger.recent(action: "unlock", vin: "V", within: 60, now: now))
        XCTAssertEqual(ledger.recent(action: "lock", vin: "V", within: 60, now: now)?.source, .geofence)
    }

    func testVINsAreIndependent() {
        let now = Date()
        ledger.note(source: .geofence, action: "unlock", vin: "A", at: now)
        XCTAssertNil(ledger.recent(action: "unlock", vin: "B", within: 60, now: now))
    }

    func testExcludingOwnSource() {
        let now = Date()
        ledger.note(source: .proximity, action: "unlock", vin: "V", at: now)
        // Yakınlık kendi kaydını görmemeli (kendini kilitlemesin).
        XCTAssertNil(ledger.recent(action: "unlock", vin: "V", within: 60, excluding: .proximity, now: now))
        // Geofence ise yakınlık kaydını görmeli (çift komut engeli).
        XCTAssertEqual(ledger.recent(action: "unlock", vin: "V", within: 60, excluding: .geofence, now: now)?.source,
                       .proximity)
    }

    func testLatestNoteWins() {
        let now = Date()
        ledger.note(source: .proximity, action: "unlock", vin: "V", at: now)
        ledger.note(source: .geofence, action: "unlock", vin: "V", at: now.addingTimeInterval(5))
        XCTAssertEqual(ledger.recent(action: "unlock", vin: "V", within: 60,
                                     now: now.addingTimeInterval(10))?.source, .geofence)
    }

    func testResetClearsAll() {
        let now = Date()
        ledger.note(source: .proximity, action: "lock", vin: "V", at: now)
        ledger.reset()
        XCTAssertNil(ledger.recent(action: "lock", vin: "V", within: 60, now: now))
    }
}
