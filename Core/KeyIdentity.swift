import CryptoKit
import Foundation

/// Telefonun dijital imza kimliği (P-256 açık anahtar) için kararlılık kontrolü.
///
/// Neden gerekli: anahtar Keychain'de tutuluyor ve sessizce yenilenebiliyor
/// (yeniden kurulum, cihaz geri yükleme, Keychain hatası). Anahtar değişince
/// sunucudaki sertifika eski anahtara ait kalır; araç imzayı reddeder ve
/// kullanıcı bunu "eşleşme koptu" olarak yaşar. Parmak izi karşılaştırması
/// bu durumu ayırt eder: onarım akışına yönlendirir, sessiz yeniden
/// eşleştirme **yapmaz**.
///
/// Kasıtlı sınırlar:
/// - Parmak izi tam açık anahtarın SHA-256'sının ilk 4 baytıdır (8 hex).
///   Tanı amaçlıdır; gizli veri değildir, ama tam anahtar yazılmaz.
/// - Saklama anahtarı VIN içerir; tanı günlüğüne VIN yazılmaz.
enum KeyIdentity {
    enum Verdict: Equatable {
        /// Bu araç için ilk kez görülüyor; kaydet.
        case firstUse
        case match
        /// Kayıtlıdan farklı: sessiz devam etmek yanlış sonuç üretir.
        case changed(previous: String)
        /// Daha önce anahtar vardı, şimdi yok (Keychain kaybı). Sessizce yeni
        /// anahtar üretip yeniden eşleştirmek "anahtarı tekrar alma" demektir.
        case missing(previous: String)
    }

    static func fingerprintKey(_ vin: String) -> String {
        "toqdas.ble.keyFingerprint.\(vin)"
    }

    static func certificateFingerprintKey(_ vin: String) -> String {
        "toqdas.ble.certFingerprint.\(vin)"
    }

    static func fingerprint(_ data: Data) -> String {
        SHA256.hash(data: data).prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    /// Sessiz devam yalnız `isExplicitRepair` (kullanıcı "yeniden eşleştir"
    /// dedi) durumunda serbesttir; otomatik yollarda kimlik değişikliği durdurur.
    static func blocksAuthentication(_ verdict: Verdict,
                                     isExplicitRepair: Bool) -> Bool {
        guard !isExplicitRepair else { return false }
        switch verdict {
        case .changed, .missing: return true
        case .firstUse, .match: return false
        }
    }

    static func check(current: String?, stored: String?) -> Verdict {
        guard let stored else {
            // Hiç kayıt yok: ilk kullanım (anahtar üretimi normal akış).
            return .firstUse
        }
        guard let current else { return .missing(previous: stored) }
        return current == stored ? .match : .changed(previous: stored)
    }
}
