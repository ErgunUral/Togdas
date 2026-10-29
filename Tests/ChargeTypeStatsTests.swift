import XCTest
@testable import ToqdasCore

final class ChargeTypeStatsTests: XCTestCase {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    func testGroupsByTypeAndSumsRealCost() {
        let page1 = data("""
        {"charges": [
          {"charge_id": "1", "charge_type": "FAST", "kwh_added": 10, "total_price": 100},
          {"charge_id": "2", "charge_type": "FAST", "kwh_added": 20, "total_price": 200},
          {"charge_id": "3", "charge_type": "SLOW", "kwh_added": 5, "total_price": 50}
        ]}
        """)
        let page2 = data("""
        {"charges": [
          {"charge_id": "4", "charge_type": "FAST", "kwh_added": 5, "total_price": 50}
        ]}
        """)
        let stats = ExperienceFormat.chargeTypeStats(from: [page1, page2])
        XCTAssertEqual(stats.count, 2)

        let fast = try? XCTUnwrap(stats.first { $0.type == "Hızlı şarj" })
        XCTAssertEqual(fast?.sessions, 3)
        XCTAssertEqual(fast?.energyKWh ?? -1, 35, accuracy: 0.001)
        XCTAssertEqual(fast?.costTRY ?? -1, 350, accuracy: 0.001)
        XCTAssertEqual(fast?.hasEstimatedCost, false)
        XCTAssertEqual(fast?.averageCostPerKWh ?? -1, 10, accuracy: 0.001)
        XCTAssertEqual(fast?.averageCostPerSession ?? -1, 116.666, accuracy: 0.01)

        let slow = stats.first { $0.type == "Yavaş şarj" }
        XCTAssertEqual(slow?.sessions, 1)
        XCTAssertEqual(slow?.costTRY ?? -1, 50, accuracy: 0.001)
        XCTAssertEqual(slow?.hasEstimatedCost, false)
    }

    func testMissingServerCostUsesUserPriceAndFlagsEstimate() {
        let page = data("""
        {"charges": [
          {"charge_type": "FAST", "kwh_added": 12.5}
        ]}
        """)
        let stats = ExperienceFormat.chargeTypeStats(from: [page], pricePerKWh: 8)
        let stat = try? XCTUnwrap(stats.first)
        XCTAssertEqual(stat?.costTRY ?? -1, 100, accuracy: 0.001)
        XCTAssertEqual(stat?.hasEstimatedCost, true)
        XCTAssertEqual(stat?.hasCost, true)
    }

    func testNoPriceMeansNoCostButEnergyKept() {
        let page = data("""
        {"charges": [{"charge_type": "FAST", "kwh_added": 12.5}]}
        """)
        let stat = ExperienceFormat.chargeTypeStats(from: [page]).first
        XCTAssertEqual(stat?.energyKWh ?? -1, 12.5, accuracy: 0.001)
        XCTAssertEqual(stat?.costTRY ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(stat?.hasCost, false)
        XCTAssertNil(stat?.averageCostPerKWh)
    }

    func testUnknownAndMissingTypeGrouped() {
        let page = data("""
        {"charges": [
          {"charge_type": "AC", "kwh_added": 3, "total_price": 30},
          {"kwh_added": 2, "total_price": 20}
        ]}
        """)
        let stats = ExperienceFormat.chargeTypeStats(from: [page])
        XCTAssertEqual(stats.first { $0.type == "AC" }?.sessions, 1)
        XCTAssertEqual(stats.first { $0.type == "Bilinmeyen" }?.sessions, 1)
    }

    func testEmptyPagesReturnEmpty() {
        XCTAssertTrue(ExperienceFormat.chargeTypeStats(from: []).isEmpty)
        XCTAssertTrue(ExperienceFormat.chargeTypeStats(from: [data("{\"charges\": []}")]).isEmpty)
    }

    func testSortedByCostDescending() {
        let page = data("""
        {"charges": [
          {"charge_type": "SLOW", "kwh_added": 1, "total_price": 10},
          {"charge_type": "FAST", "kwh_added": 1, "total_price": 90}
        ]}
        """)
        let stats = ExperienceFormat.chargeTypeStats(from: [page])
        XCTAssertEqual(stats.map(\.type), ["Hızlı şarj", "Yavaş şarj"])
    }
}

final class ChargeCostComparisonTests: XCTestCase {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    func testOctoberComparison() throws {
        let json = """
        {"summary": {"total_price": 3940.34, "total_energy_kwh": 263.04,
                     "avg_cost_per_kwh": 14.98}, "charges": []}
        """
        let comparison = try XCTUnwrap(ExperienceFormat.chargeCostComparison(from: data(json),
                                                                            pricePerKWh: 10))
        XCTAssertEqual(comparison.actualTRY, 3940.34, accuracy: 0.01)
        XCTAssertEqual(comparison.estimatedTRY, 2630.40, accuracy: 0.01)
        XCTAssertEqual(comparison.differenceTRY, 1309.94, accuracy: 0.01)
        XCTAssertEqual(comparison.differenceRatio ?? 0, 0.498, accuracy: 0.001)
        XCTAssertEqual(comparison.actualPricePerKWh ?? 0, 14.98, accuracy: 0.01)
        XCTAssertEqual(comparison.assumedPricePerKWh, 10, accuracy: 0.001)
    }

    func testActualUnitPriceFallsBackToDivision() throws {
        let json = """
        {"summary": {"total_price": 500, "total_energy_kwh": 50}, "charges": []}
        """
        let comparison = try XCTUnwrap(ExperienceFormat.chargeCostComparison(from: data(json),
                                                                            pricePerKWh: 8))
        XCTAssertEqual(comparison.actualPricePerKWh ?? 0, 10, accuracy: 0.001)
        XCTAssertEqual(comparison.estimatedTRY, 400, accuracy: 0.001)
    }

    func testServerTotalFallsBackToTotalCost() throws {
        let json = """
        {"summary": {"total_cost": 987.48, "total_energy_kwh": 65.83}, "charges": []}
        """
        XCTAssertNotNil(ExperienceFormat.chargeCostComparison(from: data(json), pricePerKWh: 15))
    }

    func testMissingInputsReturnNil() {
        XCTAssertNil(ExperienceFormat.chargeCostComparison(from: data("{\"summary\": {}}"),
                                                           pricePerKWh: 10))
        XCTAssertNil(ExperienceFormat.chargeCostComparison(
            from: data("{\"summary\": {\"total_price\": 100, \"total_energy_kwh\": 0}}"),
            pricePerKWh: 10))
        XCTAssertNil(ExperienceFormat.chargeCostComparison(
            from: data("{\"summary\": {\"total_price\": 100, \"total_energy_kwh\": 10}}"),
            pricePerKWh: 0))
        // Birim fiyat 100 ile sınırlanır; tahmin yine üretilir.
        let comparison = ExperienceFormat.chargeCostComparison(
            from: data("{\"summary\": {\"total_price\": 100, \"total_energy_kwh\": 10}}"),
            pricePerKWh: 500)
        XCTAssertEqual(comparison?.estimatedTRY ?? 0, 1000, accuracy: 0.001)
    }
}
