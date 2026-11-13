import XCTest
@testable import ToqdasCore

/// Faz geçişi halka tamponu.
final class BlePhaseLogTests: XCTestCase {
    private let suite = "test.blePhaseLog"
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testEmptyByDefault() {
        XCTAssertTrue(BlePhaseLog.load(defaults: defaults).isEmpty)
    }

    func testRecordsPhaseAndDetail() {
        BlePhaseLog.record(.searching, detail: "geri çekilme", at: Date(timeIntervalSince1970: 10),
                           defaults: defaults)
        BlePhaseLog.record(.ready, at: Date(timeIntervalSince1970: 20), defaults: defaults)
        let entries = BlePhaseLog.load(defaults: defaults)
        XCTAssertEqual(entries.map(\.phase), ["searching", "ready"])
        XCTAssertEqual(entries.first?.detail, "geri çekilme")
        XCTAssertEqual(entries.last?.at, 20)
    }

    func testCapacityKeepsLatest() {
        for index in 0..<(BlePhaseLog.capacity + 5) {
            BlePhaseLog.record(.connecting, detail: "\(index)",
                               at: Date(timeIntervalSince1970: Double(index)), defaults: defaults)
        }
        let entries = BlePhaseLog.load(defaults: defaults)
        XCTAssertEqual(entries.count, BlePhaseLog.capacity)
        XCTAssertEqual(entries.first?.detail, "5")
    }

    func testLongDetailIsTruncatedAndClearWorks() {
        BlePhaseLog.record(.ready, detail: String(repeating: "a", count: 200), defaults: defaults)
        XCTAssertEqual(BlePhaseLog.load(defaults: defaults).first?.detail.count, 80)
        BlePhaseLog.clear(defaults: defaults)
        XCTAssertTrue(BlePhaseLog.load(defaults: defaults).isEmpty)
    }
}
