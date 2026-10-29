import XCTest
@testable import ToqdasCore

final class DrivingStatsTests: XCTestCase {
    private func day(_ dayOfMonth: Int, inMonthOf date: Date = Date()) -> Date {
        var comps = Calendar.current.dateComponents([.year, .month], from: date)
        comps.day = dayOfMonth
        comps.hour = 12
        return Calendar.current.date(from: comps) ?? date
    }

    private func store() -> DrivingStatsStore {
        let suite = "toqdas.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        return DrivingStatsStore(vin: "VIN\(UUID().uuidString)", defaults: defaults)
    }

    func testMonthlyKmFromOdometerDelta() {
        let store = store()
        store.record(odometer: 1000, on: day(2))
        store.record(odometer: 1250, on: day(20))

        let stats = store.monthlyStats(for: day(20))
        XCTAssertEqual(stats.km, 250, accuracy: 0.001)
        XCTAssertEqual(stats.estimatedKWh, 250 * 17.0 / 100.0, accuracy: 0.001)
        XCTAssertEqual(stats.estimatedCostTRY, stats.estimatedKWh * 10.0, accuracy: 0.001)
        XCTAssertEqual(stats.daysWithData, 2)
    }

    func testSameDayKeepsFirstAndLastOdometer() {
        let store = store()
        store.record(odometer: 1000, on: day(2))
        store.record(odometer: 1100, on: day(2))
        store.record(odometer: 1200, on: day(20))

        XCTAssertEqual(store.monthlyStats(for: day(20)).km, 200, accuracy: 0.001)
        XCTAssertEqual(store.monthlyStats(for: day(20)).daysWithData, 2)
    }

    func testSameDayOnlyTripCounts() {
        let store = store()
        store.record(odometer: 1000, on: day(5))
        store.record(odometer: 1060, on: day(5))

        XCTAssertEqual(store.monthlyStats(for: day(5)).km, 60, accuracy: 0.001)
    }

    func testNoRecordsReturnsZero() {
        let stats = store().monthlyStats()
        XCTAssertEqual(stats.km, 0)
        XCTAssertEqual(stats.estimatedCostTRY, 0)
        XCTAssertEqual(stats.daysWithData, 0)
    }

    func testNegativeDeltaClampedToZero() {
        let store = store()
        store.record(odometer: 500, on: day(2))
        store.record(odometer: 400, on: day(20))

        XCTAssertEqual(store.monthlyStats(for: day(20)).km, 0)
    }

    func testMonthWithSingleReadingReportsZeroKm() {
        let store = store()
        store.record(odometer: 4321, on: day(10))

        XCTAssertEqual(store.monthlyStats(for: day(10)).km, 0, accuracy: 0.001)
        XCTAssertEqual(store.monthlyStats(for: day(10)).daysWithData, 1)
    }

    func testInvalidOdometersAreIgnored() {
        let store = store()
        store.record(odometer: .nan, on: day(2))
        store.record(odometer: -5, on: day(2))
        XCTAssertEqual(store.monthlyStats(for: day(2)).daysWithData, 0)
    }

    func testPreviousMonthIsSeparate() {
        let store = store()
        let now = Date()
        let previousMonth = Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now
        store.record(odometer: 100, on: day(5, inMonthOf: previousMonth))
        store.record(odometer: 400, on: day(25, inMonthOf: previousMonth))
        store.record(odometer: 500, on: day(2, inMonthOf: now))

        XCTAssertEqual(store.monthlyStats(for: previousMonth).km, 300, accuracy: 0.001)
        XCTAssertEqual(store.monthlyStats(for: now).km, 0, accuracy: 0.001)
    }

    func testLast7DaysKm() {
        let store = store()
        let now = Date()
        store.record(odometer: 1000, on: Calendar.current.date(byAdding: .day, value: -3, to: now) ?? now)
        store.record(odometer: 1150, on: now)

        XCTAssertEqual(store.last7DaysKm(asOf: now), 150, accuracy: 0.001)
    }
}
