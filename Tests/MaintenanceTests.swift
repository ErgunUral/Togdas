import XCTest
@testable import ToqdasCore

final class MaintenanceTests: XCTestCase {
    private func store() -> MaintenanceStore {
        let suite = "toqdas.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        return MaintenanceStore(vin: "VIN\(UUID().uuidString)", defaults: defaults)
    }

    func testAddAndList() {
        let store = store()
        let item = store.add(title: "Yağ değişimi", dueKm: 15000)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.title, "Yağ değişimi")
        XCTAssertEqual(store.items.first?.dueKm, 15000)
        XCTAssertFalse(item.done)
    }

    func testAddTrimsAndRejectsEmptyTitle() {
        let store = store()
        store.add(title: "   ", dueKm: 1000)
        XCTAssertEqual(store.items.first?.title, "Bakım")
        XCTAssertEqual(store.add(title: "  Fren  ", dueKm: 2000).title, "Fren")
    }

    func testMarkDoneStoresOdometerAndCanReopen() {
        let store = store()
        let item = store.add(title: "Lastik", dueKm: 10000)
        store.markDone(item.id, atOdometer: 10250)

        XCTAssertTrue(store.items[0].done)
        XCTAssertEqual(store.items[0].completedAtKm, 10250)

        store.markPending(item.id)
        XCTAssertFalse(store.items[0].done)
        XCTAssertNil(store.items[0].completedAtKm)
    }

    func testRemove() {
        let store = store()
        store.add(title: "A", dueKm: 1000)
        store.add(title: "B", dueKm: 2000)
        let id = store.items[0].id
        store.remove(id)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].title, "B")
    }

    func testUpcomingAndOverdueWindows() {
        let store = store()
        store.add(title: "Yaklaşan", dueKm: 10400)
        store.add(title: "Geciken", dueKm: 9500)
        store.add(title: "Uzak", dueKm: 30000)

        let upcoming = store.upcoming(currentOdometer: 10000, within: 500)
        XCTAssertEqual(upcoming.map(\.title), ["Geciken", "Yaklaşan"])

        XCTAssertEqual(store.overdue(currentOdometer: 10000).map(\.title), ["Geciken"])
    }

    func testDoneItemsAreExcludedFromUpcoming() {
        let store = store()
        let item = store.add(title: "Bitti", dueKm: 10100)
        store.markDone(item.id, atOdometer: 10000)
        XCTAssertTrue(store.upcoming(currentOdometer: 10000, within: 500).isEmpty)
        XCTAssertTrue(store.overdue(currentOdometer: 10000).isEmpty)
    }

    func testRemainingKmNeverNegative() {
        let item = MaintenanceItem(title: "X", dueKm: 1000)
        XCTAssertEqual(item.remainingKm(currentOdometer: 400), 600)
        XCTAssertEqual(item.remainingKm(currentOdometer: 3000), 0)
    }
}
