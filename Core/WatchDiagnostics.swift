import Foundation

/// Saat tarafı küçük olay günlüğü (halka tampon).
///
/// Neden gerekli: telefon tanısı zengin, ancak saatte "veri geldi mi /
/// yenileme istendi mi / komut sonucu ne" görünmüyordu; saha testinde
/// saat davranışı yalnızca tahminle açıklanabiliyordu. Günlük saat
/// UserDefaults'unda tutulur, cihazdan plist çekilerek okunur.
///
/// Kasıtlı sınırlar:
/// - UI'da gösterilmez; komut göndermez, ağ/kullanım yok.
/// - VIN/token yazılmaz; mesajlar çağıranda kısa tutulur.
/// - En fazla `capacity` olay; eskiler atılır (sabit bellek).
struct WatchDiagnostics {
    struct Entry: Codable, Equatable {
        let at: TimeInterval
        let message: String
    }

    static let storageKey = "toqdas.watch.diagnostics.v1"
    static let capacity = 40

    static func log(_ message: String, at: Date = Date(),
                    defaults: UserDefaults = .standard) {
        var entries = events(defaults: defaults)
        entries.append(Entry(at: at.timeIntervalSince1970,
                             message: String(message.prefix(160))))
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: storageKey)
        }
    }

    /// Eskiden yeniye sıralı olaylar; kayıt yoksa boş dizi.
    static func events(defaults: UserDefaults = .standard) -> [Entry] {
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
