import Foundation

/// Saat complication'ının veri köprüsü: watch uygulamasının aldığı
/// `WatchSnapshot`'ı app group'a yazar; widget extension okur.
///
/// Kasıtlı sınırlar (invariant korunur):
/// - Complication **yalnız gösterim verisi** taşır: anahtar, token,
///   komut kuyruğu ve konum yoktur; complication komut göndermez.
/// - App group sağlanamıyorsa (entitlement bekliyorsa) yazım/okuma
///   sessizce no-op olur; watch uygulamasının kendi cache'i
///   (`WatchLink`, standart UserDefaults) etkilenmez.
/// - Tazelik `WatchSnapshot.updatedAt` üzerinden çağıran tarafın
///   işidir; depo zaman yorumu yapmaz.
enum WatchComplicationStore {
    /// iPhone widget ve VehicleCommandStatus ile aynı app group.
    static let appGroup = "group.com.toqdas.ios"
    static let snapshotKey = "toqdas.watch.complication.snapshot.v1"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    /// Kodlanmış `WatchSnapshot` JSON'unu yazar.
    static func saveSnapshotData(_ data: Data) {
        defaults?.set(data, forKey: snapshotKey)
    }

    /// Kodlanmış `WatchSnapshot` JSON'unu okur; yoksa nil.
    static func snapshotData() -> Data? {
        defaults?.data(forKey: snapshotKey)
    }

    /// Depoyu temizler (iPhone bağlantısı kopunca eski veri kalmasın).
    static func clear() {
        defaults?.removeObject(forKey: snapshotKey)
    }
}
