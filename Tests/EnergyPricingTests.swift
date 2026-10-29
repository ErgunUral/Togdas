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

final class ChargeSpendingTests: XCTestCase {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    private let periodJSON = """
    {
      "summary": {"total_sessions": 4, "total_energy_kwh": 40, "avg_cost_per_kwh": 9.5},
      "charges": [
        {"charge_id": "c1", "kwh_added": 12, "soc_start_pct": 30, "soc_end_pct": 60},
        {"charge_id": "c2", "kwh_added": 10, "total_price": 95},
        {"charge_id": "c3", "kwh_added": 9},
        {"charge_id": "c4", "kwh_added": 9}
      ]
    }
    """

    func testPeriodShowsSessionAveragesAndEstimatedSpend() throws {
        let period = try XCTUnwrap(ExperienceFormat.period(from: data(periodJSON), kind: .charges,
                                                          pricePerKWh: 10))
        func value(_ label: String) -> String? {
            period.metrics.first { $0.label == label }?.value
        }
        XCTAssertEqual(value("Şarj sayısı"), "4")
        XCTAssertEqual(value("Seans başına"), "10.0 kWh")
        XCTAssertEqual(value("Tahmini maliyet"), "≈ 400 ₺")
        XCTAssertEqual(value("Seans başına tutar"), "≈ 100 ₺")
        // Sunucu toplam tutar döndürmediği için "Toplam harcama" uydurulmaz.
        XCTAssertNil(value("Toplam harcama"))
    }

    func testServerPeriodTotalTakesPrecedence() throws {
        let json = """
        {"summary": {"total_sessions": 2, "total_energy_kwh": 30, "total_price": 285},
         "charges": []}
        """
        let period = try XCTUnwrap(ExperienceFormat.period(from: data(json), kind: .charges, pricePerKWh: 10))
        XCTAssertEqual(period.metrics.first { $0.label == "Toplam harcama" }?.value, "285.00 ₺")
        XCTAssertEqual(period.metrics.first { $0.label == "Seans başına tutar" }?.value, "142.50 ₺")
        // Sunucu gerçek tutar verdiyse tahmini maliyet gösterilmez.
        XCTAssertNil(period.metrics.first { $0.label == "Tahmini maliyet" })
    }

    func testChargeRecordUsesServerCostThenEstimate() throws {
        let period = try XCTUnwrap(ExperienceFormat.period(from: data(periodJSON), kind: .charges,
                                                          pricePerKWh: 10))
        let withServerCost = try XCTUnwrap(period.records.first { $0.id == "c2" })
        XCTAssertEqual(withServerCost.metrics.first { $0.label == "Tutar" }?.value, "95.00 ₺")
        XCTAssertNil(withServerCost.metrics.first { $0.label == "Tahmini tutar" })

        let estimated = try XCTUnwrap(period.records.first { $0.id == "c1" })
        XCTAssertEqual(estimated.metrics.first { $0.label == "Tahmini tutar" }?.value, "≈ 120 ₺")
    }

    func testChargeWithoutEnergyDoesNotInventCost() throws {
        let json = """
        {"charges": [{"charge_id": "c9", "soc_start_pct": 20, "soc_end_pct": 40}]}
        """
        let period = try XCTUnwrap(ExperienceFormat.period(from: data(json), kind: .charges, pricePerKWh: 10))
        let record = try XCTUnwrap(period.records.first)
        XCTAssertNil(record.metrics.first { $0.label == "Tahmini tutar" })
    }

    func testDetailAddsEstimateWhenServerCostMissing() throws {
        let json = """
        {"charge_id": "c1", "kwh_added": 12, "duration_min": 30}
        """
        let detail = try XCTUnwrap(ExperienceFormat.detail(from: data(json), kind: .charges, pricePerKWh: 10))
        XCTAssertTrue(detail.notes.contains { $0.contains("Tahmini tutar") && $0.contains("120") })
        XCTAssertFalse(detail.notes.contains { $0.contains("Servisteki maliyet") })
    }

    func testDetailKeepsServerCostWhenPresent() throws {
        let json = """
        {"charge_id": "c2", "kwh_added": 10, "total_price": 95}
        """
        let detail = try XCTUnwrap(ExperienceFormat.detail(from: data(json), kind: .charges, pricePerKWh: 10))
        XCTAssertTrue(detail.notes.contains { $0.contains("Servisteki maliyet: 95.00") })
        XCTAssertFalse(detail.notes.contains { $0.contains("Tahmini tutar") })
    }
}

extension ChargeSpendingTests {
    /// Gerçek yanıtta `cost` birim fiyattır (₺/kWh); toplam sanılmamalı.
    func testUnitPriceFieldIsNotUsedAsTotalCost() throws {
        let json = """
        {"charges": [{"charge_id": "c7", "kwh_added": 10, "cost": 14.98, "currency": "TRY"}]}
        """
        let period = try XCTUnwrap(ExperienceFormat.period(from: data(json), kind: .charges, pricePerKWh: 10))
        let record = try XCTUnwrap(period.records.first)
        XCTAssertNil(record.metrics.first { $0.label == "Tutar" })
        XCTAssertEqual(record.metrics.first { $0.label == "Tahmini tutar" }?.value, "≈ 100 ₺")
    }

    func testDetailDoesNotTreatUnitPriceAsTotal() throws {
        let json = """
        {"charge_id": "c7", "kwh_added": 10, "cost": 14.98}
        """
        let detail = try XCTUnwrap(ExperienceFormat.detail(from: data(json), kind: .charges, pricePerKWh: 10))
        XCTAssertFalse(detail.notes.contains { $0.contains("Servisteki maliyet: 14.98") })
        XCTAssertTrue(detail.notes.contains { $0.contains("Tahmini tutar") && $0.contains("100") })
    }
}
