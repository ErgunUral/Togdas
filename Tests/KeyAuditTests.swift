import XCTest
@testable import ToqdasCore

final class KeyAuditTests: XCTestCase {
    func testKeepsNewestEventsWithinLimit() {
        let suite = "test.keyAudit"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        for index in 0..<(KeyAudit.limit + 5) {
            KeyAudit.record("event", detail: "\(index)", defaults: defaults)
        }
        let events = KeyAudit.load(defaults: defaults)
        XCTAssertEqual(events.count, KeyAudit.limit)
        XCTAssertEqual(events.last?.detail, "\(KeyAudit.limit + 4)")
        defaults.removePersistentDomain(forName: suite)
    }

    func testSummaryContainsKindAndDetail() {
        let suite = "test.keyAuditSummary"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        KeyAudit.record("generated", detail: "status=-25300", defaults: defaults)
        XCTAssertTrue(KeyAudit.summary(defaults: defaults).contains("generated:status=-25300"))
        defaults.removePersistentDomain(forName: suite)
    }

    func testRepairPolicyBlocksOnlyImplicitChange() {
        let changed = KeyIdentity.Verdict.changed(previous: "aaaa")
        let missing = KeyIdentity.Verdict.missing(previous: "aaaa")

        XCTAssertTrue(KeyIdentity.blocksAuthentication(changed, isExplicitRepair: false))
        XCTAssertTrue(KeyIdentity.blocksAuthentication(missing, isExplicitRepair: false))
        // Açık onarımda kullanıcı zaten yeni anahtarı kabul etti.
        XCTAssertFalse(KeyIdentity.blocksAuthentication(changed, isExplicitRepair: true))
        XCTAssertFalse(KeyIdentity.blocksAuthentication(missing, isExplicitRepair: true))
        XCTAssertFalse(KeyIdentity.blocksAuthentication(.firstUse, isExplicitRepair: false))
        XCTAssertFalse(KeyIdentity.blocksAuthentication(.match, isExplicitRepair: false))
    }
}
