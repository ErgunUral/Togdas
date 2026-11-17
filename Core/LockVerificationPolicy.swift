import Foundation

/// Kilit doğrulama penceresi: komut ack'inden sonra imzalı araç durumunun
/// hedef kilit değerini göstermesi için beklenen süre.
///
/// Neden ayrı tip: pencere sabiti `BleConnection` içinde gömülüyken
/// telemetri kadansıyla ilişkisi kaybolmuştu. Ölçüm (2026-11-17, 17 imzalı
/// paket): aralıklar 1–180 sn, **medyan ~60 sn**, yaygın üst sınır ~90 sn.
/// Eski 35 sn pencere medyanın altındaydı: araç komutu uygulasa bile sonraki
/// paket geç geldiğinde "doğrulanamadı" yazılabiliyordu.
///
/// Kasıtlı sınırlar:
/// - Pencere medyanın üstünde tutulur; gecikmiş telemetri geçmiş kaydı
///   **değiştirmez** (yanlış kesinlik üretilmez) — sonraki komutlar yeni
///   durumu zaten görür.
/// - Pencere, komut göndermeyi bloke etmez; yalnız "bekleniyor" durumunun
///   ne zaman "doğrulanamadı"ya döneceğini belirler.
enum LockVerificationPolicy {
    /// Ölçülen medyan kadans (referans; pencere bundan büyük olmalı).
    static let telemetryCadenceMedian: TimeInterval = 60
    /// Doğrulama penceresi: medyan kadansın üstünde, 90 sn.
    static let window: TimeInterval = 90

    static func timeoutDetail(window: TimeInterval = LockVerificationPolicy.window) -> String {
        "Kilit değişikliği \(Int(window)) sn içinde imzalı durumla doğrulanamadı."
    }
}
