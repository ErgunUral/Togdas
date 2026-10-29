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
        XCTAssertFalse(stats.consumptionIsMeasured)
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
        XCTAssertFalse(stats.consumptionIsMeasured)
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

    // MARK: - Gerçek tüketim

    func testConsumptionIsMeasuredFromBatteryDrop() {
        let store = store()
        // 100 km yol, %20 düşüş => 17,7 kWh => 17,7 kWh/100 km
        store.record(odometer: 1000, batteryPercent: 80, on: day(2))
        store.record(odometer: 1100, batteryPercent: 60, on: day(6))

        let stats = store.monthlyStats(for: day(6))
        XCTAssertTrue(stats.consumptionIsMeasured)
        XCTAssertEqual(stats.consumptionKWhPer100km, 17.7, accuracy: 0.001)
        XCTAssertEqual(stats.estimatedKWh, 17.7, accuracy: 0.001)
        XCTAssertEqual(stats.estimatedCostTRY, 177, accuracy: 0.01)
    }

    func testChargingSegmentIsIgnored() {
        let store = store()
        store.record(odometer: 1000, batteryPercent: 80, on: day(2))
        store.record(odometer: 1100, batteryPercent: 50, on: day(3))
        // Şarj: yüzde arttı, tüketim hesabına katılmamalı
        store.record(odometer: 1100, batteryPercent: 90, on: day(4))

        let stats = store.monthlyStats(for: day(4))
        XCTAssertTrue(stats.consumptionIsMeasured)
        XCTAssertEqual(stats.consumptionKWhPer100km, 26.55, accuracy: 0.01)
    }

    func testTooFewKilometresFallsBackToDefault() {
        let store = store()
        store.record(odometer: 1000, batteryPercent: 80, on: day(2))
        store.record(odometer: 1005, batteryPercent: 79, on: day(3))

        let stats = store.monthlyStats(for: day(3))
        XCTAssertFalse(stats.consumptionIsMeasured)
        XCTAssertEqual(stats.consumptionKWhPer100km, DrivingStats.defaultConsumptionKWhPer100km)
    }

    func testImplausibleDischargeIsIgnored() {
        let store = store()
        store.record(odometer: 1000, batteryPercent: 95, on: day(2))
        // %95 düşüş mantıksız kabul edilir
        store.record(odometer: 1200, batteryPercent: 0, on: day(5))

        XCTAssertFalse(store.monthlyStats(for: day(5)).consumptionIsMeasured)
    }

    func testConsumptionWithinSameDay() {
        let store = store()
        store.record(odometer: 1000, batteryPercent: 90, on: day(3))
        store.record(odometer: 1100, batteryPercent: 70, on: day(3))

        let stats = store.monthlyStats(for: day(3))
        XCTAssertTrue(stats.consumptionIsMeasured)
        XCTAssertEqual(stats.consumptionKWhPer100km, 17.7, accuracy: 0.001)
    }

    func testInvalidBatteryValuesAreIgnored() {
        let store = store()
        store.record(odometer: 1000, batteryPercent: 140, on: day(2))
        store.record(odometer: 1100, batteryPercent: -3, on: day(3))
        store.record(odometer: 1200, batteryPercent: .nan, on: day(4))

        XCTAssertFalse(store.monthlyStats(for: day(4)).consumptionIsMeasured)
    }
}
