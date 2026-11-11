import Foundation

/// 12 V akü geçmişi kalıcılığı: JSON kodlu `AuxiliaryBatteryHistory` tek
/// anahtar altında okunur/yazılır.
///
/// Neden gerekli: pano geçmişi okuma/kayıt kodu DashboardView içindeydi;
/// depolama davranışı test edilemez ve widget/saat gibi ikinci bir
/// tüketicide kopyalanma riski taşıyordu. Saf mantık
/// (`AuxiliaryBatteryHistory`) zaten Core'da; bu tip yalnız depolama
/// katmanını ekler (`KeyValueStore` enjeksiyonu, testlerde bellek içi
/// sahte depo).
///
/// Kasıtlı sınırlar:
/// - Bozuk/okunamayan veri sessizce boş geçmiş döner; kullanıcıya hata
///   gösterilmez, "bilgi yok" görünümü korunur.
/// - Anahtar biçimi App katmanındadır (`StorageKeys`); Core anahtar
///   metnini bilmez.
/// - Geçmiş yalnız gün başına en güncel ölçümü tutar (30 gün cap,
///   `AuxiliaryBatteryHistory.record` içinde).
struct AuxiliaryBatteryHistoryStore {
    let store: KeyValueStore

    /// Kayıt yoksa veya veri bozuksa boş geçmiş döner.
    func load(key: String) -> AuxiliaryBatteryHistory {
        guard let data = store.data(forKey: key),
              let history = try? JSONDecoder().decode(AuxiliaryBatteryHistory.self, from: data) else {
            return AuxiliaryBatteryHistory()
        }
        return history
    }

    /// Geçmişi kaydeder; kodlama başarısızsa sessizce çıkar (önceki
    /// kayıt bozulmaz).
    func save(_ history: AuxiliaryBatteryHistory, key: String) {
        guard let data = try? JSONEncoder().encode(history) else { return }
        store.set(data, forKey: key)
    }
}
