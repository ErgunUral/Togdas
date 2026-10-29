import XCTest
@testable import ToqdasCore

final class ChargingBudgetTests: XCTestCase {
    private func date(_ year: Int, _ month: Int, _ day: Int = 15) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    func testStatusTransitions() {
        XCTAssertEqual(ChargingBudget(limitTRY: 0, spentTRY: 100).status, .unset)
        XCTAssertEqual(ChargingBudget(limitTRY: 5000, spentTRY: 1000).status, .normal)
        XCTAssertEqual(ChargingBudget(limitTRY: 5000, spentTRY: 4000).status, .nearLimit)
        XCTAssertEqual(ChargingBudget(limitTRY: 5000, spentTRY: 5000).status, .nearLimit)
        XCTAssertEqual(ChargingBudget(limitTRY: 5000, spentTRY: 5001).status, .exceeded)
    }

    func testNotificationThreshold() {
        XCTAssertEqual(ChargingBudget(limitTRY: 0, spentTRY: 9000).notificationThreshold, 0)
        XCTAssertEqual(ChargingBudget(limitTRY: 5000, spentTRY: 1000).notificationThreshold, 0)
        XCTAssertEqual(ChargingBudget(limitTRY: 5000, spentTRY: 4200).notificationThreshold, 80)
        XCTAssertEqual(ChargingBudget(limitTRY: 5000, spentTRY: 5500).notificationThreshold, 100)
    }

    func testRatioRemainingAndPercent() {
        let budget = ChargingBudget(limitTRY: 4000, spentTRY: 1000)
        XCTAssertEqual(budget.ratio, 0.25, accuracy: 0.001)
        XCTAssertEqual(budget.remainingTRY, 3000, accuracy: 0.001)
        XCTAssertEqual(budget.percentText, "25%")
        XCTAssertEqual(ChargingBudget(limitTRY: 0, spentTRY: 10).percentText, "—")
        XCTAssertEqual(ChargingBudget(limitTRY: 1000, spentTRY: 3000).ratio, 1, accuracy: 0.001,
                       "Oran 1 ile sınırlanır, ilerleme çubuğu taşmaz.")
    }

    func testMoneyAndMessage() {
        XCTAssertEqual(ChargingBudget.money(3940.34), "3.940 ₺")
        XCTAssertTrue(ChargingBudget(limitTRY: 5000, spentTRY: 4200).message.contains("kaldı"))
        XCTAssertTrue(ChargingBudget(limitTRY: 5000, spentTRY: 5500).message.contains("aşıldı"))
    }

    func testInvalidValuesAreClamped() {
        XCTAssertEqual(ChargingBudget(limitTRY: -50, spentTRY: -10).limitTRY, 0)
        XCTAssertEqual(ChargingBudget(limitTRY: -50, spentTRY: -10).spentTRY, 0)
        XCTAssertEqual(ChargingBudget(limitTRY: .nan, spentTRY: .nan).limitTRY, 0)
        XCTAssertEqual(ChargingBudget(limitTRY: 1_000_000, spentTRY: .infinity).limitTRY,
                       ChargingBudget.maximumLimitTRY)
    }

    func testStoreRecordsCurrentMonthAndRollsOver() {
        let defaults = UserDefaults(suiteName: "ChargingBudgetTests.\(UUID().uuidString)")!
        let store = ChargingSpendStore(vin: "VIN1", defaults: defaults)
        defer { defaults.removePersistentDomain(forName: "ChargingBudgetTests") }

        XCTAssertNil(store.snapshot(for: date(2026, 10)))
        store.record(amountTRY: 3940.34, month: "2026-10", at: date(2026, 10, 29))
        XCTAssertEqual(store.snapshot(for: date(2026, 10))?.amountTRY, 3940.34)

        // Ay değişince eski harcama gösterilmez.
        XCTAssertNil(store.snapshot(for: date(2026, 11)))

        store.record(amountTRY: 120, month: "2026-11", at: date(2026, 11, 2))
        XCTAssertEqual(store.snapshot(for: date(2026, 11))?.amountTRY, 120)
        XCTAssertNil(store.snapshot(for: date(2026, 10)), "Yeni ay kaydı eski ayı siler.")
    }

    func testStoreDoesNotLowerAmountWithinMonth() {
        let defaults = UserDefaults(suiteName: "ChargingBudgetTests.\(UUID().uuidString)")!
        let store = ChargingSpendStore(vin: "VIN1", defaults: defaults)
        defer { defaults.removePersistentDomain(forName: "ChargingBudgetTests") }

        store.record(amountTRY: 500, month: "2026-10", at: date(2026, 10, 10))
        store.record(amountTRY: 200, month: "2026-10", at: date(2026, 10, 11))
        XCTAssertEqual(store.snapshot(for: date(2026, 10))?.amountTRY, 500,
                       "Eksik/sayfalanmış yanıt gerçek harcamayı düşürmez.")
        store.record(amountTRY: 700, month: "2026-10", at: date(2026, 10, 12))
        XCTAssertEqual(store.snapshot(for: date(2026, 10))?.amountTRY, 700)
    }

    func testRecordingAnotherMonthDoesNotInheritCurrentAmount() {
        let defaults = UserDefaults(suiteName: "ChargingBudgetTests.\(UUID().uuidString)")!
        let store = ChargingSpendStore(vin: "VIN1", defaults: defaults)
        defer { defaults.removePersistentDomain(forName: "ChargingBudgetTests") }

        store.record(amountTRY: 500, month: "2026-10", at: date(2026, 10, 10))
        // Geçmiş bir ayı yazmak cari ayın tutarını devralmaz.
        store.record(amountTRY: 40, month: "2026-09", at: date(2026, 10, 11))
        XCTAssertEqual(store.snapshot(for: date(2026, 9))?.amountTRY, 40)
        XCTAssertNil(store.snapshot(for: date(2026, 10)), "Tek kayıt alanı yeni ayla değişir.")
    }

    func testLimitAndBudget() {
        let defaults = UserDefaults(suiteName: "ChargingBudgetTests.\(UUID().uuidString)")!
        let store = ChargingSpendStore(vin: "VIN1", defaults: defaults)
        defer { defaults.removePersistentDomain(forName: "ChargingBudgetTests") }

        XCTAssertEqual(store.monthlyLimit(), 0)
        store.setMonthlyLimit(5000)
        store.record(amountTRY: 3940.34, month: "2026-10", at: date(2026, 10, 29))

        let budget = store.budget(for: date(2026, 10))
        XCTAssertEqual(budget.limitTRY, 5000, accuracy: 0.001)
        XCTAssertEqual(budget.spentTRY, 3940.34, accuracy: 0.001)
        XCTAssertEqual(budget.status, .normal)

        store.setMonthlyLimit(1_000_000)
        XCTAssertEqual(store.monthlyLimit(), ChargingBudget.maximumLimitTRY)
        store.setMonthlyLimit(-5)
        XCTAssertEqual(store.monthlyLimit(), 0)
    }

    func testNotificationOncePerMonthAndThreshold() {
        let defaults = UserDefaults(suiteName: "ChargingBudgetTests.\(UUID().uuidString)")!
        let store = ChargingSpendStore(vin: "VIN1", defaults: defaults)
        defer { defaults.removePersistentDomain(forName: "ChargingBudgetTests") }

        XCTAssertEqual(store.lastNotifiedThreshold(for: "2026-10"), 0)
        store.markNotified(threshold: 80, month: "2026-10")
        XCTAssertEqual(store.lastNotifiedThreshold(for: "2026-10"), 80)
        // Farklı ay sıfırdan başlar.
        XCTAssertEqual(store.lastNotifiedThreshold(for: "2026-11"), 0)
        // Yeni eşik var olanı yükseltir.
        store.markNotified(threshold: 100, month: "2026-10")
        XCTAssertEqual(store.lastNotifiedThreshold(for: "2026-10"), 100)
    }

    func testClearRemovesEverything() {
        let defaults = UserDefaults(suiteName: "ChargingBudgetTests.\(UUID().uuidString)")!
        let store = ChargingSpendStore(vin: "VIN1", defaults: defaults)
        defer { defaults.removePersistentDomain(forName: "ChargingBudgetTests") }

        store.setMonthlyLimit(3000)
        store.record(amountTRY: 100, month: "2026-10", at: date(2026, 10, 1))
        store.markNotified(threshold: 80, month: "2026-10")
        store.clear()
        XCTAssertEqual(store.monthlyLimit(), 0)
        XCTAssertNil(store.snapshot(for: date(2026, 10)))
        XCTAssertEqual(store.lastNotifiedThreshold(for: "2026-10"), 0)
    }
}

/// Aylık harcama önbelleğinin Seyahatname yanıtıyla beslendiğini doğrular.
final class ChargingSpendExtractionTests: XCTestCase {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    func testChargeSpendUsesServerTotal() throws {
        let json = """
        {"summary": {"total_price": 3940.34, "total_energy_kwh": 263.04, "total_sessions": 5},
         "charges": []}
        """
        XCTAssertEqual(ExperienceFormat.chargeSpend(from: data(json)) ?? -1, 3940.34, accuracy: 0.001)
    }

    func testChargeSpendFallsBackToTotalCost() throws {
        let json = """
        {"summary": {"total_cost": 987.48}, "charges": []}
        """
        XCTAssertEqual(ExperienceFormat.chargeSpend(from: data(json)) ?? -1, 987.48, accuracy: 0.001)
    }

    func testChargeSpendMissingIsNil() {
        XCTAssertNil(ExperienceFormat.chargeSpend(from: data("{\"charges\": []}")))
        XCTAssertNil(ExperienceFormat.chargeSpend(from: data("{}")))
    }

}
