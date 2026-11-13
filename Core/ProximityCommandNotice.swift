import Foundation

/// Otomatik yakınlık komutunun sonucunu yerel bildirime çeviren karar
/// katmanı. `DashboardView`'daki akışı test edilebilir kılar.
///
/// Kasıtlı sınırlar:
/// - Bildirim **yalnızca otomatik (yakınlık) komutlar** için çağrılır;
///   manuel komutların sonucu uygulama içinde gösterilir.
/// - Metin davranışa sadıktır: komut **yeniden gönderilmez**, kullanıcıdan
///   uygulamadan kontrol etmesi istenir.
/// - Kimlik (`identifier`) VIN içerebilir (yerel, gösterilmez); başlık ve
///   gövde VIN içermez (gizlilik invariant'ı).
enum ProximityCommandNotice {
    enum Kind: Equatable {
        case lock, unlock

        var actionText: String {
            switch self {
            case .lock: return "kilitleme"
            case .unlock: return "kilit açma"
            }
        }

        var identifierKey: String {
            switch self {
            case .lock: return "lock"
            case .unlock: return "unlock"
            }
        }
    }

    enum Failure: Equatable {
        /// Komut araca ulaştı ancak imzalı telemetri hedef durumu doğrulamadı.
        case notVerified
        /// Komut hiç başlatılamadı (guard/bağlantı/red).
        case notStarted
    }

    enum Outcome: Equatable {
        case verified
        case failed
    }

    /// `BleConnection.lastEvent` metnini sonuç olarak yorumlar.
    /// Metin sözleşmesi BleConnection'dadır:
    /// - doğrulama: "…araç durumuyla doğrulandı." veya
    ///   "…kilit durumu hedef değerle eşleşiyor."
    /// - başarısızlık: "…kilit değişikliği doğrulanamadı."
    static func outcome(forEvent event: String) -> Outcome? {
        if event.contains("kilit değişikliği doğrulanamadı") { return .failed }
        if event.contains("araç durumuyla doğrulandı") { return .verified }
        if event.contains("kilit durumu hedef değerle eşleşiyor") { return .verified }
        return nil
    }

    /// Başarısız otomatik komut için bildirim taslağı.
    static func failureDraft(kind: Kind, failure: Failure, vin: String) -> NotificationPoster.Draft {
        let title: String
        let body: String
        switch (kind, failure) {
        case (.lock, .notVerified):
            title = "Otomatik kilitleme doğrulanamadı"
            body = "Kapılar açık olabilir. Komut yeniden gönderilmedi; uygulamadan kontrol edebilirsin."
        case (.lock, .notStarted):
            title = "Otomatik kilitleme başlatılamadı"
            body = "Uzaklaşma algılandı ancak kilitleme komutu gönderilemedi; uygulamadan kontrol edebilirsin."
        case (.unlock, .notVerified):
            title = "Otomatik kilit açma doğrulanamadı"
            body = "Kapıların açıldığı doğrulanamadı. Komut yeniden gönderilmedi; uygulamadan kontrol edebilirsin."
        case (.unlock, .notStarted):
            title = "Otomatik kilit açma başlatılamadı"
            body = "Yaklaşma algılandı ancak kilit açma komutu gönderilemedi; uygulamadan kontrol edebilirsin."
        }
        return NotificationPoster.Draft(
            identifier: "proximity-command-\(kind.identifierKey)-failed-\(vin)",
            title: title,
            body: body
        )
    }
}
