import Foundation

/// Widget'a yazılan **son komut sonucu**. App group ile paylaşılır
/// (`group.com.toqdas.ios`; kaynağın yapı eklemesini Widget/App hedefi tüm
/// dosyalarıyla beraber barındırabilir).
///
/// Gizlilik / dürüstlük kuralları:
/// - VIN, oturum token'ı, sertifika ve anahtar malzemesi yazılmaz.
/// - Etiket eylemi tanımlar ama komut sonucu iddiası taşımaz: `verified`
///   `nil` iken doğrulama yapılmamış demektir; araya "başarılı" gibi bir
///   onay nitelemesi **asla yazılmaz** — kesinlik yalnızca imzalı telemetri
///   doğrulamasıdır.
/// - Eksik etiket "—" değil satır yokluğu ile gösterilir; sahte tazelik
///   yoktur ve 24 saatten eski kayıt ekranda çıkarılmaz.
struct VehicleCommandStatus: Codable, Equatable {
    /// Eylem etiketi (örn. "Kilitleme", "Kilit açma", "Bagaj açma").
    let actionLabel: String
    /// Komutun gönderildiği an.
    let sentAt: Date
    /// İmzalı telemetri doğrulaması: `true`/`false` kesin sonucu,
    /// `nil` doğrulamanın henüz yapılmadığını gösterir.
    let verified: Bool?

    static let appGroup = "group.com.toqdas.ios"
    static let storageKey = "toqdas.widget.commandstatus.v1"

    /// 24 saatten eski sonuç iddiası taşımaz; widget'ta gösterilmez.
    var isStale: Bool {
        Date().timeIntervalSince(sentAt) > 24 * 3600
    }

    /// Doğrulama etiketi; eksik veri açıktır ve "bilgi yok" biçimindedir.
    var verificationText: String {
        switch verified {
        case .some(true): return "doğrulandı"
        case .some(false): return "doğrulanamadı"
        case .none: return "doğrulama yok"
        }
    }

    /// Widget satır metni: "Son komut: Kilit açma · doğrulama yok".
    /// Etiket boşsa nil döner; satır hiç çıkarılmaz.
    var displayText: String? {
        let label = actionLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return nil }
        return "Son komut: \(label) · \(verificationText)"
    }
}

enum VehicleCommandStatusStore {
    /// Uygulama tarafı yazım noktası: komut gönderimi ve doğrulama bildirimi.
    /// `defaults` test enjeksiyonu içindir; üretim önündeki çağrılar app
    /// group suite'i kullanır ve VIN/token gibi hassas veriyi asla yazmaz.
    static func save(
        _ status: VehicleCommandStatus,
        defaults: UserDefaults = UserDefaults(suiteName: VehicleCommandStatus.appGroup) ?? .standard
    ) {
        guard let data = try? JSONEncoder().encode(status) else { return }
        defaults.set(data, forKey: VehicleCommandStatus.storageKey)
    }

    /// Widget tarafı okuma noktası; kayıt yok/bozuk ise nil döner ve
    /// widget yalnız diğer alanlarıyla devam eder.
    static func load(
        defaults: UserDefaults = UserDefaults(suiteName: VehicleCommandStatus.appGroup) ?? .standard
    ) -> VehicleCommandStatus? {
        guard let data = defaults.data(forKey: VehicleCommandStatus.storageKey),
              let status = try? JSONDecoder().decode(VehicleCommandStatus.self, from: data) else { return nil }
        return status
    }

    /// Komutun imzalı telemetriyle doğrulandığı bildirimi: etiketi koruyarak
    /// `verified` alanını günceller; yalnız bekleyen (`verified == nil`) ve
    /// etiket önerilen koşula uyan kayıtlar güncellenir.
    static func markVerified(
        _ verified: Bool,
        ifLabelMatches predicate: (String) -> Bool,
        defaults: UserDefaults = UserDefaults(suiteName: VehicleCommandStatus.appGroup) ?? .standard
    ) {
        guard let current = load(defaults: defaults),
              current.verified == nil,
              predicate(current.actionLabel) else { return }
        save(
            VehicleCommandStatus(
                actionLabel: current.actionLabel,
                sentAt: current.sentAt,
                verified: verified
            ),
            defaults: defaults
        )
    }
}
