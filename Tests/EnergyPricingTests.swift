import XCTest
@testable import ToqdasCore

final class EnergyPricingTests: XCTestCase {
    func testDefaultAndClamping() {
        XCTAssertEqual(EnergyPricing(pricePerKWh: nil).pricePerKWh, 10)
        XCTAssertEqual(EnergyPricing(pricePerKWh: .nan).pricePerKWh, 10)
        XCTAssertEqual(EnergyPricing(pricePerKWh: -1).pricePerKWh, 10)
        XCTAssertEqual(EnergyPricing(pricePerKWh: 12.5).pricePerKWh, 12.5)
        XCTAssertEqual(EnergyPricing(pricePerKWh: 500).pricePerKWh, 100)
        // Ücretsiz şarj geçerli bir varsayımdır.
        XCTAssertEqual(EnergyPricing(pricePerKWh: 0).pricePerKWh, 0)
    }

    func testCostAndCostPerKM() throws {
        let pricing = EnergyPricing(pricePerKWh: 10)
        XCTAssertEqual(try XCTUnwrap(pricing.cost(forEnergyKWh: 12)), 120, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(pricing.costPerKM(energyKWh: 12, distanceKM: 100)), 1.2, accuracy: 0.001)
    }

    func testMissingOrInvalidEnergyProducesNoEstimate() {
        let pricing = EnergyPricing(pricePerKWh: 10)
        XCTAssertNil(pricing.cost(forEnergyKWh: nil))
        XCTAssertNil(pricing.cost(forEnergyKWh: 0))
        XCTAssertNil(pricing.cost(forEnergyKWh: -5))
        XCTAssertNil(pricing.cost(forEnergyKWh: .nan))
        XCTAssertNil(pricing.costPerKM(energyKWh: 12, distanceKM: nil))
        XCTAssertNil(pricing.costPerKM(energyKWh: 12, distanceKM: 0))
    }

    func testPriceTextUsesTwoDecimals() {
        XCTAssertEqual(EnergyPricing(pricePerKWh: 10).priceText, "10.00 ₺/kWh")
    }
}

final class ExperienceCostMetricsTests: XCTestCase {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    private let journeyJSON = """
    {
      "summary": {
        "total_distance_km": 500,
        "total_kwh_consumed": 85,
        "journey_count": 12
      },
      "journeys": []
    }
    """

    func testJourneyCostMetricsAreComputedWhenPriceProvided() throws {
        let period = try XCTUnwrap(ExperienceFormat.period(from: data(journeyJSON), kind: .journeys,
                                                          pricePerKWh: 10))
        let cost = period.metrics.first { $0.label == "Tahmini maliyet" }
        let perKM = period.metrics.first { $0.label == "Km başına" }
        XCTAssertNotNil(cost)
        XCTAssertTrue(cost?.value.contains("850") ?? false, "85 kWh × 10 ₺ = 850 ₺")
        XCTAssertTrue(cost?.value.contains("≈") ?? false, "Tahmin olduğu işaretlenmeli")
        XCTAssertNotNil(perKM)
        XCTAssertTrue(perKM?.value.contains("1.70") ?? false, "850 ₺ / 500 km = 1,70 ₺/km")
    }

    func testNoCostMetricsWithoutPrice() throws {
        let period = try XCTUnwrap(ExperienceFormat.period(from: data(journeyJSON), kind: .journeys))
        XCTAssertFalse(period.metrics.contains { $0.label == "Tahmini maliyet" })
        XCTAssertFalse(period.metrics.contains { $0.label == "Km başına" })
    }

    func testMissingEnergyDoesNotInventCost() throws {
        let json = """
        {"summary": {"total_distance_km": 500}, "journeys": []}
        """
        let period = try XCTUnwrap(ExperienceFormat.period(from: data(json), kind: .journeys, pricePerKWh: 10))
        XCTAssertFalse(period.metrics.contains { $0.label == "Tahmini maliyet" })
    }

    func testChargesCostEstimateUsesAddedEnergy() throws {
        let json = """
        {"summary": {"total_energy_kwh": 40}, "charges": []}
        """
        let period = try XCTUnwrap(ExperienceFormat.period(from: data(json), kind: .charges, pricePerKWh: 10))
        let cost = period.metrics.first { $0.label == "Tahmini maliyet" }
        XCTAssertTrue(cost?.value.contains("400") ?? false)
    }
}
