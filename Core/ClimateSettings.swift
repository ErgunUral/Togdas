import Foundation

/// Klima hedef sıcaklığı kalıcılığı (VIN bazlı).
///
/// Neden gerekli: okuma/yazma kodu DashboardView içinde
/// `UserDefaults.standard` üzerinden üç ayrı noktada tekrarlanıyordu;
/// davranış test edilemezdi. Anahtar biçimi önceki literalle
/// **byte-identicaldir** ("toqdas.climateTarget.<vin>").
///
/// Kasıtlı sınırlar:
/// - 16–30 °C aralık doğrulaması çağırandadır (`VehicleCommandPolicy`
///   tarafındaki kural); burada yalnız kalıcılık vardır.
/// - "Hiç kayıt yok" ile "kayıt var ama geçersiz" ayrımı yapılır:
///   `hasTarget` yalnız gerçek kayıt varken `true` döner.
/// - Sıcaklık `Double` saklanır; ondalık gösterim `TurkishFormat`'tadır.
struct ClimateSettings {
    let store: KeyValueStore

    static func targetKey(_ vin: String) -> String { "toqdas.climateTarget.\(vin)" }

    /// Kayıtlı hedef; hiç kayıt yoksa `nil` (araç durumundan ilk hedef
    /// seçme kararının çağrı tarafında verilmesi için).
    func target(vin: String) -> Double? {
        (store.object(forKey: Self.targetKey(vin)) as? NSNumber)?.doubleValue
    }

    /// Hiç kayıt var mı? (DashboardView "araç hedefini ilk kez mi
    /// alıyorum" kararında `object != nil` semantiğiyle aynıdır.)
    func hasTarget(vin: String) -> Bool {
        store.object(forKey: Self.targetKey(vin)) != nil
    }

    /// Hedef kaydeder; `nil` yazımı kaydı kaldırır.
    func setTarget(_ value: Double?, vin: String) {
        store.set(value, forKey: Self.targetKey(vin))
    }
}
