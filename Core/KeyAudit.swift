import Foundation

/// Dijital anahtarın kimlik geçmişi: hangi olay, ne zaman, hangi sebeple?
///
/// Neden gerekli: "anahtar neden sürekli değişiyor" sorusunun yanıtı tanı
/// halkasında kayboluyordu (500 olay sınırı) ve üretim sebebi hiç
/// kaydedilmiyordu. Bu kayıt son 20 olayı tutar; parmak izi dışında gizli
/// veri yazmaz.
enum KeyAudit {
    struct Event: Codable, Equatable {
        let at: TimeInterval
        /// `generated`, `changed`, `missing`, `unavailable`, `confirmed`,
        /// `repair_allowed`, `repair_completed`
        let kind: String
        let detail: String
    }

    static let storageKey = "toqdas.key.history.v1"
    static let limit = 20

    static func record(_ kind: String, detail: String = "",
                       at: Date = Date(), defaults: UserDefaults = .standard) {
        var events = load(defaults: defaults)
        events.append(Event(at: at.timeIntervalSince1970, kind: kind,
                            detail: String(detail.prefix(120))))
        if events.count > limit { events = Array(events.suffix(limit)) }
        guard let data = try? JSONEncoder().encode(events) else { return }
        defaults.set(data, forKey: storageKey)
    }

    static func load(defaults: UserDefaults = .standard) -> [Event] {
        guard let data = defaults.data(forKey: storageKey),
              let events = try? JSONDecoder().decode([Event].self, from: data) else {
            return []
        }
        return events
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }

    /// Cihazda okunacak tek satırlık özet (en son 5 olay).
    static func summary(defaults: UserDefaults = .standard) -> String {
        load(defaults: defaults).suffix(5).map { "\($0.kind):\($0.detail)" }
            .joined(separator: " | ")
    }
}
