import Foundation

/// Anahtar başına **pencere tabanlı** bildirim tekniği: aynı uyarı
/// `window` süresi içinde en fazla bir kez gösterilir.
///
/// Gün tabanlı `NotificationDedupe`'dan farkı: kısa vadeli durumlar için
/// tasarlandı (ör. otomatik komut başarısızlığı). Zayıf sinyal döngüsünde
/// aynı başarısızlık dakikalar içinde tekrar tekrar bildirim üretmesin;
/// pencere dolduğunda tekrar izin verir. "Bildirim + kullanıcı kontrolü"
/// kararı korunur: susturma tekrarı önler, kullanıcıyı harekete çağıran
/// ilk bildirim gecikmez.
///
/// Kasıtlı sınırlar:
/// - Eksik kayıt = hiç bildirilmemiş sayılır → `true`.
/// - Karar kaydedilir; gönderim `UNUserNotificationCenter`'a aittir.
struct NoticeThrottle {
    let store: KeyValueStore

    func shouldNotify(key: String, window: TimeInterval, now: Date = Date()) -> Bool {
        let last = store.object(forKey: key) as? Date ?? .distantPast
        return now.timeIntervalSince(last) >= window
    }

    func record(key: String, now: Date = Date()) {
        store.set(now, forKey: key)
    }

    func reset(key: String) {
        store.removeObject(forKey: key)
    }
}
