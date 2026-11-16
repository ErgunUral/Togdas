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

    /// Sayısal pencere: eksik gün `nil` ("bilgi yok"), gerçek 0 değeri
    /// `0.0` korunur; sıra eskiden yeniye.
    func testNumericValuesWindowKeepsMissingDaysAndZero() {
        var history = AuxiliaryBatteryHistory()
        XCTAssertTrue(history.record(percent: 72, on: date(2026, 11, 9), calendar: calendar))
        XCTAssertTrue(history.record(percent: 0, on: date(2026, 11, 11), calendar: calendar))
        let values = history.numericValues(count: 5, today: date(2026, 11, 11), calendar: calendar)
        XCTAssertEqual(values, [nil, nil, 72, nil, 0])
    }

    private static func dayString(_ date: Date, calendar: Calendar) -> String {
        AuxiliaryBatteryHistory.dayKey(for: date, calendar: calendar)
    }    /// Trend: bilinen günler arası net düşüş yön üretir; eksik günler nil kalır.
    func testTrendDetectsDeclineAcrossKnownDays() {
        var history = AuxiliaryBatteryHistory()
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        let calendar = Calendar.current
        for (offset, percent) in [80.0, 78.0, 72.0].enumerated() {
            let day = calendar.date(byAdding: .day, value: -(2 - offset), to: today)!
            XCTAssertTrue(history.record(percent: percent, on: day))
        }
        let trend = AuxiliaryBatteryTrend.make(history: history, today: today, calendar: calendar)
        XCTAssertEqual(trend.direction, .declining)
        XCTAssertEqual(trend.change ?? 0, -8, accuracy: 0.01)
        XCTAssertEqual(trend.minPercent, 72)
        XCTAssertEqual(trend.maxPercent, 80)
        XCTAssertEqual(trend.summaryText(), "−8 puan, düşüş eğilimi · en düşük %72 / en yüksek %80")
    }

    /// Bant içindeki küçük oynama "kararlı" der; tek bilinen gün trend üretmez.
    func testTrendStableWithinBandAndUnknownWithSingleSample() {
        var history = AuxiliaryBatteryHistory()
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        let calendar = Calendar.current
        XCTAssertTrue(history.record(percent: 80, on: calendar.date(byAdding: .day, value: -1, to: today)!))
        XCTAssertTrue(history.record(percent: 82, on: today))
        XCTAssertEqual(AuxiliaryBatteryTrend.make(history: history, today: today, calendar: calendar).direction,
                       .stable)

        var single = AuxiliaryBatteryHistory()
        XCTAssertTrue(single.record(percent: 80, on: today))
        let trend = AuxiliaryBatteryTrend.make(history: single, today: today, calendar: calendar)
        XCTAssertNil(trend.direction)
        XCTAssertNil(trend.summaryText())
        XCTAssertEqual(trend.dailyValues.count, 7)
    }

    /// Toparlanma yönü ve "bilgi yok" günlerin nil korunumu.
    func testTrendRisingAndMissingDaysStayNil() {
        var history = AuxiliaryBatteryHistory()
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        let calendar = Calendar.current
        XCTAssertTrue(history.record(percent: 70, on: calendar.date(byAdding: .day, value: -3, to: today)!))
        XCTAssertTrue(history.record(percent: 76, on: today)) // ara günler kayıtsız
        let trend = AuxiliaryBatteryTrend.make(history: history, today: today, calendar: calendar)
        XCTAssertEqual(trend.direction, .rising)
        XCTAssertEqual(trend.dailyValues.filter { $0 == nil }.count, 5)
    }

}
