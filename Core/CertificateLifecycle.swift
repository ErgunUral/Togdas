import Foundation

/// Sertifikanın son kullanma durumunu ve yenileme penceresini tek yerde tutar.
/// Sertifika süresi dolmadan önce yenilenmeye çalışılır; yenileme başarısız
/// olursa hâlâ geçerli olan sertifika kullanılmaya devam eder.
struct CertificateLifecycle: Equatable {
    enum State: String, Equatable {
        case valid
        /// 24 saatten az kaldı; bağlantı sırasında yenilenmeli.
        case expiringSoon
        case expired
    }

    /// Yenileme penceresi: son 24 saat.
    static let refreshWindow: TimeInterval = 86_400

    let expiresAt: Date
    let state: State
    /// Kalan tam gün sayısı; süresi dolmuşsa 0.
    let daysRemaining: Int

    init(expiresAt: Date, now: Date = Date()) {
        self.expiresAt = expiresAt
        let remaining = expiresAt.timeIntervalSince(now)
        if remaining <= 0 {
            state = .expired
            daysRemaining = 0
        } else if remaining <= Self.refreshWindow {
            state = .expiringSoon
            daysRemaining = max(1, Int((remaining / 86_400).rounded(.up)))
        } else {
            state = .valid
            daysRemaining = Int((remaining / 86_400).rounded(.up))
        }
    }

    init?(certificateBase64: String, now: Date = Date()) {
        guard let data = Data(base64Encoded: certificateBase64),
              let expiresAt = BLEProtocol.certificateEndDate(data) else {
            return nil
        }
        self.init(expiresAt: expiresAt, now: now)
    }

    var needsRefresh: Bool { state != .valid }
    var isUsable: Bool { state != .expired }

    var summary: String {
        switch state {
        case .valid:
            return "Geçerli · \(daysRemaining) gün kaldı"
        case .expiringSoon:
            return "Yakında doluyor · \(daysRemaining) gün kaldı"
        case .expired:
            return "Süresi doldu"
        }
    }
}
