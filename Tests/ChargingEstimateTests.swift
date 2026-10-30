import XCTest
@testable import ToqdasCore

final class ChargingEstimateTests: XCTestCase {
    func testEstimateMatchesAndroidExample() {
        let estimate = ChargingEstimate.calculate(
            capacityKWh: 88.5,
            startPercent: 20,
            targetPercent: 80,
            pricePerKWh: 10
        )
        XCTAssertEqual(estimate.energyKWh, 53.1, accuracy: 0.001)
        XCTAssertEqual(estimate.cost, 531, accuracy: 0.001)
        XCTAssertEqual(estimate.energyText, "53,1 kWh")
        XCTAssertEqual(estimate.costText, "531 ₺")
    }

    func testEstimateClampsInvalidValuesAndTargetBelowStart() {
        let estimate = ChargingEstimate.calculate(
            capacityKWh: .infinity,
            startPercent: 90,
            targetPercent: 40,
            pricePerKWh: -5
        )
        XCTAssertEqual(estimate.energyKWh, 0)
        XCTAssertEqual(estimate.cost, 0)
        XCTAssertEqual(estimate.energyText, "0,0 kWh")
        XCTAssertEqual(estimate.costText, "0 ₺")
    }

    func testEstimateCapsCapacityAndPrice() {
        let estimate = ChargingEstimate.calculate(
            capacityKWh: 500,
            startPercent: 0,
            targetPercent: 100,
            pricePerKWh: 500
        )
        XCTAssertEqual(estimate.energyKWh, 200, accuracy: 0.001)
        XCTAssertEqual(estimate.cost, 20_000, accuracy: 0.001)
    }
}
