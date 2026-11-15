import Foundation

/// Tek BLE oturumunun sinyal kalitesi. "Telefon nerede daha iyi çalışıyor"
/// sorusunu tahminle değil ölçümle yanıtlar; VIN veya kimlik içermez.
struct BleSessionQuality: Codable, Equatable {
    let startedAt: TimeInterval
    let endedAt: TimeInterval
    let duration: TimeInterval
    let minRSSI: Int?
    let maxRSSI: Int?
    let averageRSSI: Double?
    /// Kopma nedeni (kısa metin; ör. "araç oturumu kapattı").
    let endReason: String

    static func make(startedAt: Date, endedAt: Date, samples: [Int],
                     endReason: String) -> BleSessionQuality {
        let average = samples.isEmpty
            ? nil
            : (Double(samples.reduce(0, +)) / Double(samples.count) * 10).rounded() / 10
        return BleSessionQuality(
            startedAt: startedAt.timeIntervalSince1970,
            endedAt: endedAt.timeIntervalSince1970,
            duration: max(0, endedAt.timeIntervalSince(startedAt)),
            minRSSI: samples.min(),
            maxRSSI: samples.max(),
            averageRSSI: average,
            endReason: String(endReason.prefix(80))
        )
    }
}

/// Son 20 oturumun kalite kaydı (`toqdas.ble.session.v1`).
struct BleSessionQualityStore {
    static let storageKey = "toqdas.ble.session.v1"
    static let limit = 20

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> [BleSessionQuality] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let sessions = try? JSONDecoder().decode([BleSessionQuality].self, from: data) else {
            return []
        }
        return sessions
    }

    func append(_ session: BleSessionQuality) {
        var sessions = load()
        sessions.append(session)
        if sessions.count > Self.limit { sessions = Array(sessions.suffix(Self.limit)) }
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.storageKey)
    }
}
