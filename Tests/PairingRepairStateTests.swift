import XCTest
@testable import ToqdasCore

/// Onarım durumunun oturumlar arası kalıcılığı.
final class PairingRepairStateTests: XCTestCase {
    private let suite = "test.pairingRepair"
    private var defaults: UserDefaults!
    private var store: PairingRepairStore!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        store = PairingRepairStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testEmptyByDefault() {
        XCTAssertNil(store.load(vin: "V"))
    }

    func testRoundTrip() {
        let state = PairingRepairState(detectedAt: 1_800_000_000, reason: "eşleşme silindi")
        store.save(state, vin: "V")
        XCTAssertEqual(store.load(vin: "V"), state)
    }

    func testClearRemovesState() {
        store.save(PairingRepairState(detectedAt: 1, reason: "x"), vin: "V")
        store.clear(vin: "V")
        XCTAssertNil(store.load(vin: "V"))
    }

    func testVehiclesAreIndependent() {
        store.save(PairingRepairState(detectedAt: 1, reason: "x"), vin: "A")
        XCTAssertNil(store.load(vin: "B"))
        XCTAssertNotEqual(PairingRepairStore.key("A"), PairingRepairStore.key("B"))
    }
}
