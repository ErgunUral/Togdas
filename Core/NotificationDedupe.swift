import Foundation

/// Bildirim tekniği ortaklaşması: anahtar başına **günde bir kez** bildirim.
///
/// Kullanıcılar: 12 V akü (ciddiyet başına), lastik (pozisyon × ciddiyet
/// başına), bakım maddeleri. Davranış her yerde aynıdır: son bildirim
/// tarihi depoya yazılır; aynı takvim günü içinde tekrar bildirim yok.
/// Anahtar biçimleri App katmanında (`StorageKeys`) tanımlıdır; Core
/// anahtar metnini bilmez, yalnız depolama davranışını taşır.
///
/// Kasıtlı sınırlar:
/// - "Gün" sınırı çağıranın takvimiyle hesaplanır (kullanıcı ayarlı
///   bölge/saat dilimi korunur).
/// - Eksik kayıt = hiç bildirilmemiş sayılır → `true`.
/// - Bildirim gönderilip gönderilmediği değil, **gösterilme kararı**
///   kaydedilir; gönderim `UNUserNotificationCenter`'a aittir.
struct NotificationDedupe {
    let store: KeyValueStore

    /// Bu anahtar için bugün bildirim gösterilebilir mi?
    func shouldNotify(key: String, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let last = store.object(forKey: key) as? Date ?? .distantPast
        return !calendar.isDate(last, inSameDayAs: now)
    }

    /// Bildirim kararını kaydeder; aynı gün içinde sonraki
    /// `shouldNotify` çağrıları `false` döner.
    func record(key: String, now: Date = Date()) {
        store.set(now, forKey: key)
    }

    /// Sıfırlama (ör. bakım maddesi tamamlanınca): sonraki gün değil,
    /// hemen tekrar bildirime izin verir.
    func reset(key: String) {
        store.removeObject(forKey: key)
    }
}
