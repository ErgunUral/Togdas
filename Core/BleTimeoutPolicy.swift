import Foundation

/// BLE el sıkışma/komut zaman aşımı bütçesi.
///
/// Neden gerekli: sabit 6/8/10 sn'lik pencereler −90 dBm civarında
/// yetmiyordu; araç yanıtı gecikince uygulama bağlantıyı düşürüp yeniden
/// başlıyordu. Zayıf sinyalde bütçe uzatılır, güçlü sinyalde davranış
/// birebir korunur.
///
/// Kasıtlı sınırlar:
/// - Yalnız **bekleme süresi** uzar; protokol sırası veya paketler değişmez.
/// - Üst sınır 20 sn: çok uzun beklemek kullanıcıyı kilitli bırakır.
enum BleTimeoutPolicy {
    static let weakSignalThreshold = -85
    static let weakFactor = 1.5
    static let maxWeakTimeout: TimeInterval = 20

    static func scaled(_ base: TimeInterval, lastRSSI: Int?) -> TimeInterval {
        guard let lastRSSI, lastRSSI < weakSignalThreshold else { return base }
        return min(base * weakFactor, maxWeakTimeout)
    }
}
