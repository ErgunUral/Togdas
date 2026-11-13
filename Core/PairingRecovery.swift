import Foundation

/// Araç eşleşmesi geçersizleştiğinde (`pairingLost`) gösterilen kurtarma
/// rehberi — tek kaynak (banner + bildirim aynı metni kullanır).
///
/// Neden uygulama kendi çözemez: iOS'ta BLE bağı **işletim sistemi**
/// seviyesindedir; uygulama eşleşmeyi silemez. Doğru kurtarma yolu cihaz
/// ayarlarından aracı unutup yeniden eşleştirmektir.
///
/// Kasıtlı sınırlar:
/// - Metinler VIN içermez (gizlilik invariant'ı); kimlik (`identifier`)
///   VIN içerebilir, yereldir ve gösterilmez.
/// - Rehber **komut göndermez**; yalnız yönlendirir.
enum PairingRecovery {
    static let title = "Araç eşleşmesi geçersiz"

    static let steps: [String] = [
        "iPhone'da Ayarlar > Bluetooth'tan aracı unut.",
        "Araç ekranından bu telefonu kaldır.",
        "İki cihazı yeniden başlat, uygulamadan tekrar bağlan ve eşleştirmeyi başlat."
    ]

    /// Kabul edilebilir satırlık özet (banner üstü metin).
    static let summary = "Bağlantı şifrelemesi doğrulanamıyor; otomatik kilit/açma çalışmaz."

    /// Bildirim gövdesi: adımlar tek paragrafta, davranışa sadık.
    static let notificationBody = """
    \(steps[0]) \(steps[1]) \(steps[2]) Bu tamamlanana kadar otomatik komut gönderilmez.
    """

    static func notificationDraft(vin: String) -> NotificationPoster.Draft {
        NotificationPoster.Draft(
            identifier: "pairing-recovery-\(vin)",
            title: title,
            body: notificationBody
        )
    }
}
