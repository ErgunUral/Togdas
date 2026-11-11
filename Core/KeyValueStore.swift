import Foundation

/// `UserDefaults` yerine enjekte edilebilen basit anahtar-değer deposu.
/// Testlerde bellek içi sahte depo kullanılır; üretimde `UserDefaults.standard`.
///
/// Neden ayrı dosya: protokol `GaragePreferences` içindeyken watch hedefi
/// (GaragePreferences'ı derlemeyen) `CloudSnapshotStore` gibi depo sınıfları
/// bu tipi göremiyordu. Genel altyapı siparişe taşındı.
protocol KeyValueStore: AnyObject {
    func string(forKey key: String) -> String?
    func bool(forKey key: String) -> Bool
    func object(forKey key: String) -> Any?
    func integer(forKey key: String) -> Int
    func data(forKey key: String) -> Data?
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
}

extension UserDefaults: KeyValueStore {}
