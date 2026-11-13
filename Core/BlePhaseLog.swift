import Foundation

/// Faz geçişlerinin küçük halka tamponu (son 20 geçiş).
///
/// Neden gerekli: "neden koptu" sorusu yalnız serbest metin tanı satırlarından
/// okunabiliyordu; faz geçişleri zaman damgalı tutulduğunda kopma öncesi
/// son durum tek bakışta görülür. Komut göndermez, ağ kullanmaz.
///
/// Kasıtlı sınırlar:
/// - VIN/token yazılmaz; `detail` çağıranda kısa tutulur (neden kodu).
/// - En fazla `capacity` kayıt; eskiler atılır.
struct BlePhaseLog {
    struct Entry: Codable, Equatable {
        let at: TimeInterval
        let phase: String
        let detail: String
    }

    static let storageKey = "toqdas.ble.phase.v1"
    static let capacity = 20

    static func record(_ phase: BlePhase, detail: String = "",
                       at: Date = Date(), defaults: UserDefaults = .standard) {
        var entries = load(defaults: defaults)
        entries.append(Entry(at: at.timeIntervalSince1970,
                             phase: phase.rawValue,
                             detail: String(detail.prefix(80))))
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: storageKey)
        }
    }

    static func load(defaults: UserDefaults = .standard) -> [Entry] {
        guard let data = defaults.data(forKey: storageKey),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            return []
        }
        return entries
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }
}
