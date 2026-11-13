import Foundation

/// Sertifikanın nereden geldiğinin kaydı: önbellekten mi yeniden
/// kullanıldı, süresi dolmadan mı yenilendi, yoksa ilk kez mi alındı?
///
/// Neden gerekli: kullanıcı "dijital anahtarı aldım, tekrar alınmasın"
/// diyor; uygulama her bağlantıda sunucudan sertifika istiyor gibi
/// görünüyordu. Bu kayıt, davranışı kanıtlanabilir kılar: sertifika
/// ~1 yıl geçerlidir ve yalnız son 24 saatte yenilenir.
///
/// Kasıtlı sınırlar:
/// - VIN anahtarda; tanı metnine VIN yazılmaz.
/// - Yalnız kaynak + zaman; sertifika/anahtar içeriği saklanmaz.
struct CertificateProvenance: Codable, Equatable {
    enum Source: String, Codable {
        /// Keychain önbelleğinden kullanıldı (sunucuya gidilmedi).
        case reused
        /// Süresi dolmadan sunucudan yenilendi (son 24 saat).
        case refreshed
        /// İlk kez alındı / sahiplik kuruldu.
        case issued
    }

    let source: Source
    let at: TimeInterval

    static func summary(_ provenance: CertificateProvenance,
                        daysRemaining: Int?) -> String {
        let days = daysRemaining.map { " · \($0) gün geçerli" } ?? ""
        switch provenance.source {
        case .reused:
            return "Dijital anahtar yeniden kullanılıyor\(days)"
        case .refreshed:
            return "Sertifika süresi dolmadan yenilendi\(days)"
        case .issued:
            return "Dijital anahtar alındı\(days)"
        }
    }
}

struct CertificateProvenanceStore {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func key(_ vin: String) -> String { "toqdas.cert.provenance.\(vin)" }

    func load(vin: String) -> CertificateProvenance? {
        guard let data = defaults.data(forKey: Self.key(vin)) else { return nil }
        return try? JSONDecoder().decode(CertificateProvenance.self, from: data)
    }

    func save(_ provenance: CertificateProvenance, vin: String) {
        guard let data = try? JSONEncoder().encode(provenance) else { return }
        defaults.set(data, forKey: Self.key(vin))
    }

    func clear(vin: String) {
        defaults.removeObject(forKey: Self.key(vin))
    }
}
