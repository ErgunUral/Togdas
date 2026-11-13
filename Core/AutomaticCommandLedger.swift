import Foundation

/// Otomatik komut defteri: yakınlık otomasyonu ile geofence aynı araca
/// kısa süre içinde **iki kez** komut göndermesin.
///
/// Neden gerekli: geofence giriş/çıkış kapanışları doğrudan
/// `ble.unlock()/lock()` çağırıyordu ve yakınlık guard'larını atlıyordu;
/// eve yaklaşırken iki kaynak da açma/kilitleme komutu üretebiliyordu.
///
/// Kasıtlı sınırlar:
/// - Bellek içidir; uygulama ömrü boyunca yaşar (diskte anahtar yok).
/// - Karar eşiği **çağırandadır** (`within`); bu tip yalnız kayıt tutar.
/// - VIN anahtarı yalnız bellekte eşleştirme için kullanılır, loglanmaz.
@MainActor
final class AutomaticCommandLedger {
    enum Source: String {
        case proximity
        case geofence
    }

    struct Entry: Equatable {
        let source: Source
        let at: Date
    }

    static let shared = AutomaticCommandLedger()

    private var entries: [String: Entry] = [:]

    init() {}

    /// Komut gönderildiğini kaydeder. Aynı eylem için son kayıt yenilenir.
    func note(source: Source, action: String, vin: String, at: Date = Date()) {
        entries[key(action: action, vin: vin)] = Entry(source: source, at: at)
    }

    /// `within` saniye içinde aynı eylem için kayıt var mı?
    /// `excluding` verilirse o kaynak sayılmaz (kendi kaydını görmezden gelme).
    func recent(action: String, vin: String, within: TimeInterval,
                excluding: Source? = nil, now: Date = Date()) -> Entry? {
        guard let entry = entries[key(action: action, vin: vin)] else { return nil }
        if let excluding, entry.source == excluding { return nil }
        guard now.timeIntervalSince(entry.at) <= within else { return nil }
        return entry
    }

    func reset() {
        entries.removeAll()
    }

    private func key(action: String, vin: String) -> String {
        "\(vin)|\(action)"
    }
}
