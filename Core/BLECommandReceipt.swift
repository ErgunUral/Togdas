import Foundation

/// Tek bir BLE komutunun araç tarafındaki ilerlemesi.
/// `lastEvent` serbest metninden bağımsız olarak komutun hangi aşamada
/// olduğunu gösterir.
struct BLECommandReceipt: Codable, Equatable, Identifiable {
    enum Phase: String, Codable, Equatable {
        case queued
        case sent
        case acknowledged
        case verified
        case failed

        var title: String {
            switch self {
            case .queued: return "Sıraya alındı"
            case .sent: return "Gönderildi"
            case .acknowledged: return "Araç aldı"
            case .verified: return "Doğrulandı"
            case .failed: return "Başarısız"
            }
        }

        var isFailure: Bool { self == .failed }
    }

    /// Başarısızlığın **sınıfı**. Araç ack paketinde ret gerekçesi
    /// göndermiyor (tanıda "bilinmeyen araç paketi" 0; ack yalnız 8 byte
    /// önek). Bu yüzden sınıf, gözlenebilen ayrımdan üretilir:
    /// komut hiç gitmedi mi, protokol yanıtı mı gelmedi, araç onaylayıp
    /// durum mu bildirmedi, doğrulama beklerken bağlantı mı kapandı.
    enum FailureReason: String, Codable, Equatable {
        /// Komut güvenlik kapısında reddedildi; araca hiç gitmedi.
        case gateRejected
        /// Araç protokol yanıtı (saat/nonce/ack) gelmedi.
        case protocolTimeout
        /// Araç onayladı ancak imzalı durum hedef değeri göstermedi.
        case notVerified
        /// Doğrulama beklerken bağlantı kapandı; sonuç bilinmiyor.
        case linkLost

        var title: String {
            switch self {
            case .gateRejected: return "komut gönderilmedi"
            case .protocolTimeout: return "araç protokol yanıtı yok"
            case .notVerified: return "araç durumu bildirmedi"
            case .linkLost: return "bağlantı kapandı"
            }
        }

        /// Dürüst ayrım: hiçbiri "araç reddetti" demez — araç gerekçe
        /// bildirmiyor.
        var explanation: String {
            switch self {
            case .gateRejected:
                return "Komut güvenlik kapısında durdu; araca gönderilmedi."
            case .protocolTimeout:
                return "Araç komut akışına yanıt vermedi; komut iletilmedi."
            case .notVerified:
                return "Araç komutu onayladı ancak imzalı durum hedef değeri göstermedi."
            case .linkLost:
                return "Bağlantı doğrulama tamamlanmadan kapandı; sonuç bilinmiyor."
            }
        }
    }

    let id: UUID
    let code: UInt8
    let action: String
    var phase: Phase
    var detail: String?
    var updatedAt: Date
    /// Yalnız `.failed` aşamasında dolu; eski kayıtlarda yok (nil).
    var failureReason: FailureReason?

    init(
        id: UUID = UUID(),
        code: UInt8,
        action: String,
        phase: Phase,
        detail: String?,
        updatedAt: Date,
        failureReason: FailureReason? = nil
    ) {
        self.id = id
        self.code = code
        self.action = action
        self.phase = phase
        self.detail = detail
        self.updatedAt = updatedAt
        self.failureReason = failureReason
    }

    var summary: String {
        "\(action) · \(phase.title)"
    }
}
