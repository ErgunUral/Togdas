import Foundation

/// BLE oturumunda kullanıcıya gösterilen hata nedenleri.
/// Serbest metin yerine tipli nedenler kullanılır; ayrıntı gereken yerlerde
/// ilişkili değer yalnızca teknik ayrıntıyı taşır.
enum BLEIssue: Equatable {
    case radioUnavailable
    case radioOff
    case bluetoothUnauthorized
    case certificatePreparationFailed
    case vehicleKeyMissing
    case vehicleNotFound
    case connectionTimeout
    case serviceDiscoveryFailed
    case characteristicDiscoveryFailed
    case pairingLost
    case writeFailed
    case vehicleKeyMismatch
    case phoneKeyMissing
    case authenticationFailed(String)
    case secureRandomFailed
    case carProofUnavailable
    case carProofInvalid
    case handshakeTimeout(String)
    case connectionFailed(String)
    case unknown(String)

    var message: String {
        switch self {
        case .radioUnavailable:
            return "Bluetooth kapalı veya izin yok."
        case .radioOff:
            return "Bluetooth kapalı"
        case .bluetoothUnauthorized:
            return "Bluetooth izni yok"
        case .certificatePreparationFailed:
            return "Sertifika çerçevesi hazırlanamadı."
        case .vehicleKeyMissing:
            return "Araç eşleştirmesi gerekiyor"
        case .vehicleNotFound:
            return "Araç bulunamadı"
        case .connectionTimeout:
            return "Araç bağlantısı zaman aşımı"
        case .serviceDiscoveryFailed:
            return "Servis keşif hatası"
        case .characteristicDiscoveryFailed:
            return "Karakteristik keşif hatası"
        case .pairingLost:
            return "Eşleşme hatası"
        case .writeFailed:
            return "Yazma hatası"
        case .vehicleKeyMismatch:
            return "Araç anahtarı sunucu kaydıyla eşleşmiyor"
        case .phoneKeyMissing:
            return "Telefon anahtarı yok"
        case .authenticationFailed(let detail):
            return "Kimlik doğrulama hatası: \(detail)"
        case .secureRandomFailed:
            return "Güvenli rastgele sayı üretilemedi"
        case .carProofUnavailable:
            return "Araç imzası için anahtar veya soru yok"
        case .carProofInvalid:
            return "Araç imzası doğrulanamadı"
        case .handshakeTimeout(let detail):
            return detail
        case .connectionFailed(let detail):
            return "Bağlantı hatası: \(detail)"
        case .unknown(let detail):
            return detail
        }
    }
}
