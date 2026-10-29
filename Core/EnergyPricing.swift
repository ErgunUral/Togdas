import Foundation

/// Enerji maliyeti hesabı için tek fiyat kaynağı.
///
/// Fiyat kullanıcı varsayımıdır; araçtan veya faturdan okunmaz. Şarj
/// hesaplayıcısı, sürüş istatistikleri ve Seyahatname aynı anahtarı
/// (`toqdas.chargePricePerKWh`) kullanır; böylece ekranlar çelişmez.
struct EnergyPricing: Equatable {
    static let storageKey = "toqdas.chargePricePerKWh"
    static let defaultPricePerKWh: Double = 10
    static let maximumPricePerKWh: Double = 100

    let pricePerKWh: Double

    /// Geçersiz/sınırsız değerlerde varsayılana döner; 0 (ücretsiz şarj) geçerlidir.
    init(pricePerKWh: Double?) {
        guard let price = pricePerKWh, price.isFinite, price >= 0 else {
            self.pricePerKWh = Self.defaultPricePerKWh
            return
        }
        self.pricePerKWh = min(price, Self.maximumPricePerKWh)
    }

    func cost(forEnergyKWh energyKWh: Double?) -> Double? {
        guard let energyKWh, energyKWh.isFinite, energyKWh > 0 else { return nil }
        return energyKWh * pricePerKWh
    }

    func costPerKM(energyKWh: Double?, distanceKM: Double?) -> Double? {
        guard let cost = cost(forEnergyKWh: energyKWh),
              let distanceKM, distanceKM.isFinite, distanceKM > 0 else { return nil }
        return cost / distanceKM
    }

    var priceText: String { "\(ExperienceFormat.twoDecimals(pricePerKWh)) ₺/kWh" }
}
