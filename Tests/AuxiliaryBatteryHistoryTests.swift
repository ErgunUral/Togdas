import XCTest
@testable import ToqdasCore

/// `AuxiliaryBatteryHistory`: gün başına en güncel ölçüm, 30 gün üst sınırı,
/// eksik gün `—`, gerçek 0 `%0`.
final class AuxiliaryBatteryHistoryTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Istanbul")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testRecordRejectsInvalidPercent() {
        var history = AuxiliaryBatteryHistory()
        XCTAssertFalse(history.record(percent: nil, on: date(2026, 11, 11), calendar: calendar))
        XCTAssertFalse(history.record(percent: 101, on: date(2026, 11, 11), calendar: calendar))
        XCTAssertFalse(history.record(percent: -1, on: date(2026, 11, 11), calendar: calendar))
        XCTAssertFalse(history.record(percent: .nan, on: date(2026, 11, 11), calendar: calendar))
        XCTAssertTrue(history.samples.isEmpty)
    }

    func testSameDayKeepsLatestSample() {
        var history = AuxiliaryBatteryHistory()
        XCTAssertTrue(history.record(percent: 72, on: date(2026, 11, 11, 8), calendar: calendar))
        XCTAssertTrue(history.record(percent: 75, on: date(2026, 11, 11, 20), calendar: calendar))
        XCTAssertEqual(history.samples.count, 1)
        XCTAssertEqual(history.samples.first?.percent, 75)
        // Geriye yazım engellenir: daha eski zamanlı kayıt kabul edilmez.
        XCTAssertFalse(history.record(percent: 10, on: date(2026, 11, 11, 6), calendar: calendar))
        XCTAssertEqual(history.samples.first?.percent, 75)
    }

    func testDisplayValuesMarksMissingDays() {
        var history = AuxiliaryBatteryHistory()
        XCTAssertTrue(history.record(percent: 72, on: date(2026, 11, 10), calendar: calendar))
        XCTAssertTrue(history.record(percent: 75, on: date(2026, 11, 11), calendar: calendar))
        // 9 Kasım kaydı yok → "—"; sıra eskiden yeniye: 9, 10, 11.
        let display = history.displayValues(count: 3, today: date(2026, 11, 11), calendar: calendar)
        XCTAssertEqual(display, ["—", "%72", "%75"])
    }

    func testRealZeroIsNotMissing() {
        var history = AuxiliaryBatteryHistory()
        XCTAssertTrue(history.record(percent: 0, on: date(2026, 11, 11), calendar: calendar))
        XCTAssertEqual(
            history.displayValues(count: 1, today: date(2026, 11, 11), calendar: calendar),
            ["%0"]
        )
    }

    func testHistoryCappedAtThirtyDays() {
        var history = AuxiliaryBatteryHistory()
        for day in 1...40 {
            XCTAssertTrue(history.record(percent: 60, on: date(2026, 10, day), calendar: calendar))
        }
        XCTAssertEqual(history.samples.count, AuxiliaryBatteryHistory.maxSamples)
        XCTAssertEqual(history.samples.first?.day, "2026-10-11")
        XCTAssertEqual(history.samples.last?.day, "2026-11-09")
    }

    func testDayKeyFormat() {
        XCTAssertEqual(Self.dayString(date(2026, 3, 5), calendar: calendar), "2026-03-05")
    }

    private static func dayString(_ date: Date, calendar: Calendar) -> String {
        AuxiliaryBatteryHistory.dayKey(for: date, calendar: calendar)
    }
}
