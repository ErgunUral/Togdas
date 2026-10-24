import Foundation

/// Android sürümündeki "Şarj hesaplama" kartının saf hesaplama katmanı.
/// Kapasite ve birim fiyat kullanıcı varsayımıdır; araçtan okunmuş değer değildir.
struct ChargingEstimate: Equatable {
    let energyKWh: Double
    let cost: Double

    static func calculate(capacityKWh: Double, startPercent: Double,
                          targetPercent: Double, pricePerKWh: Double) -> ChargingEstimate {
        let capacity = finiteClamped(capacityKWh, upper: 200)
        let start = finiteClamped(startPercent, upper: 100)
        let target = finiteClamped(targetPercent, upper: 100)
        let price = finiteClamped(pricePerKWh, upper: 100)
        let energy = capacity * max(0, target - start) / 100
        return ChargingEstimate(energyKWh: energy, cost: energy * price)
    }

    var energyText: String { "\(ExperienceFormat.oneDecimal(energyKWh)) kWh" }
    var costText: String { "\(ExperienceFormat.whole(cost)) ₺" }

    private static func finiteClamped(_ value: Double, upper: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(upper, max(0, value))
    }
}
