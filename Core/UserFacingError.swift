import Foundation

/// Kullanıcıya gösterilecek hata modeli.
///
/// Amaç: "The operation couldn't be completed. (NSURLErrorDomain error -1001.)"
/// gibi ham metinleri göstermek yerine ne olduğunu, ne yapılması gerektiğini ve
/// tekrar denenenin anlamlı olup olmadığını tek yerde belirlemek.
///
/// Bu tip ağ/araç/BLE katmanlarından bağımsızdır; sınıflandırma metin
/// kalıplarına ve hata türüne göre yapılır, böylece Core katmanında test
/// edilebilir.
struct UserFacingError: Equatable {
    enum Kind: String, Equatable {
        case network
        case authentication
        case certificate
        case vehicleAsleep
        case bleNotReady
        case permission
        case server
        case cancelled
        case unknown
    }

    let kind: Kind
    let title: String
    let message: String
    /// Kullanıcının atabileceği somut adım; yoksa nil.
    let recovery: String?
    let isRetryable: Bool
    /// Geliştirici/teşhis için ham ayrıntı. Arayüzde varsayılan olarak gizlenir.
    let technicalDetail: String?

    init(
        kind: Kind,
        title: String,
        message: String,
        recovery: String? = nil,
        isRetryable: Bool = false,
        technicalDetail: String? = nil
    ) {
        self.kind = kind
        self.title = title
        self.message = message
        self.recovery = recovery
        self.isRetryable = isRetryable
        self.technicalDetail = technicalDetail
    }

    /// Türüne göre başlık, öneri ve tekrar denenebilirlik.
    static func make(
        kind: Kind,
        message: String,
        technicalDetail: String? = nil
    ) -> UserFacingError {
        switch kind {
        case .network:
            return UserFacingError(
                kind: kind,
                title: "Bağlantı kurulamadı",
                message: message,
                recovery: "İnternet bağlantınızı kontrol edip tekrar deneyin.",
                isRetryable: true,
                technicalDetail: technicalDetail
            )
        case .authentication:
            return UserFacingError(
                kind: kind,
                title: "Oturum doğrulanamadı",
                message: message,
                recovery: "Çıkış yapıp Togg hesabınızla yeniden giriş yapın.",
                isRetryable: false,
                technicalDetail: technicalDetail
            )
        case .certificate:
            return UserFacingError(
                kind: kind,
                title: "Araç anahtarı hazır değil",
                message: message,
                recovery: "Araç yanında, uygulama açıkken dijital anahtarın hazır olmasını bekleyin.",
                isRetryable: true,
                technicalDetail: technicalDetail
            )
        case .vehicleAsleep:
            return UserFacingError(
                kind: kind,
                title: "Araç yanıt vermiyor",
                message: message,
                recovery: "Araç bekleme modunda olabilir. Kapıyı açıp aracı uyandırdıktan sonra tekrar deneyin.",
                isRetryable: true,
                technicalDetail: technicalDetail
            )
        case .bleNotReady:
            return UserFacingError(
                kind: kind,
                title: "Dijital anahtar hazır değil",
                message: message,
                recovery: "Uygulama ekranını açık tutup bağlantının “Komut hazır” olmasını bekleyin.",
                isRetryable: true,
                technicalDetail: technicalDetail
            )
        case .permission:
            return UserFacingError(
                kind: kind,
                title: "İzin gerekiyor",
                message: message,
                recovery: "Ayarlar > Toqdas bölümünden gerekli izni verin.",
                isRetryable: false,
                technicalDetail: technicalDetail
            )
        case .server:
            return UserFacingError(
                kind: kind,
                title: "Sunucu hatası",
                message: message,
                recovery: "Birkaç dakika sonra tekrar deneyin. Sorun sürerse oturumu kapatıp açın.",
                isRetryable: true,
                technicalDetail: technicalDetail
            )
        case .cancelled:
            return UserFacingError(
                kind: kind,
                title: "İşlem iptal edildi",
                message: message,
                recovery: nil,
                isRetryable: true,
                technicalDetail: technicalDetail
            )
        case .unknown:
            return UserFacingError(
                kind: kind,
                title: "İşlem tamamlanamadı",
                message: message,
                recovery: "Tekrar deneyin. Sorun sürerse uygulamayı kapatıp açın.",
                isRetryable: true,
                technicalDetail: technicalDetail
            )
        }
    }

    /// Ham hata metninden tür çıkarır.
    static func classify(message: String, technicalDetail: String? = nil) -> UserFacingError {
        let text = message.lowercased()

        func contains(_ needles: [String]) -> Bool {
            needles.contains { text.contains($0) }
        }

        let kind: Kind
        if contains(["iptal", "cancelled", "canceled", "nsurlerrorcancelled", "-999"]) {
            kind = .cancelled
        } else if contains(["401", "403", "yetki", "yetkisiz", "unauthorized", "forbidden",
                            "oturum", "token", "giriş yap", "login required"]) {
            kind = .authentication
        } else if contains(["sertifika", "certificate", "eşleştirme", "pairing", "owner transfer",
                            "anahtar", "digital key", "challenge"]) {
            kind = .certificate
        } else if contains(["uyku", "bekleme", "uyan", "zaman aşımı", "timeout", "timed out", "-1001"]) {
            kind = .vehicleAsleep
        } else if contains(["izin", "permission", "konum", "location", "mikrofon", "microphone",
                            "bluetooth izni", "denied"]) {
            kind = .permission
        } else if contains(["ble", "bluetooth", "komut hazır", "gatt", "peripheral"]) {
            kind = .bleNotReady
        } else if contains(["internet", "ağ", "bağlantı", "offline", "network", "host", "-1009",
                            "-1005", "-1003", "dns"]) {
            kind = .network
        } else if contains(["500", "502", "503", "504", "sunucu", "server error", "internal error"]) {
            kind = .server
        } else {
            kind = .unknown
        }

        return make(kind: kind, message: message, technicalDetail: technicalDetail)
    }

    /// Boş metin göstermemek için kullanılan güvenli varsayılan.
    static let generic = UserFacingError(
        kind: .unknown,
        title: "İşlem tamamlanamadı",
        message: "Beklenmeyen bir sorun oluştu.",
        recovery: "Tekrar deneyin.",
        isRetryable: true,
        technicalDetail: nil
    )
}
