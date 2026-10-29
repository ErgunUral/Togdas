import Foundation

extension UserFacingError {
    /// Bilinen hata türlerini kullanıcıya gösterilecek modele çevirir.
    /// `URLError` kodları ağ/uyku ayrımı için kullanılır.
    static func from(_ error: Error) -> UserFacingError {
        if let error = error as? UserFacingError { return error }

        if error is CancellationError {
            return .make(kind: .cancelled, message: "İşlem iptal edildi.")
        }

        if let urlError = error as? URLError {
            let detail = "URLError \(urlError.code.rawValue)"
            switch urlError.code {
            case .cancelled:
                return .make(kind: .cancelled, message: "İstek iptal edildi.", technicalDetail: detail)
            case .timedOut:
                return .make(kind: .vehicleAsleep,
                             message: "İstek zaman aşımına uğradı.",
                             technicalDetail: detail)
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost,
                 .cannotConnectToHost, .dnsLookupFailed, .dataNotAllowed:
                return .make(kind: .network,
                             message: "Sunucuya ulaşılamadı.",
                             technicalDetail: detail)
            case .userAuthenticationRequired:
                return .make(kind: .authentication,
                             message: "Oturum doğrulanamadı.",
                             technicalDetail: detail)
            default:
                return .make(kind: .network,
                             message: "Bağlantı sırasında bir sorun oluştu.",
                             technicalDetail: detail)
            }
        }

        if let certificateError = error as? CertificateServiceError {
            switch certificateError {
            case .ownerTransferRequired:
                return .make(
                    kind: .certificate,
                    message: "Araç başka bir telefon anahtarına bağlı.",
                    technicalDetail: "CertificateServiceError.ownerTransferRequired"
                )
            }
        }

        let detail = String(describing: type(of: error))
        return classify(message: error.localizedDescription, technicalDetail: detail)
    }
}
