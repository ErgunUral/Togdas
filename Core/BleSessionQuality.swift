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

/// Birçok oturumun toplu görünümü: "bağlantı sağlığım nasıl?" sorusuna
/// ekranda tek bakışta yanıt. VIN içermez; ham oturumlar cihazda kalır.
struct BleSessionQualitySummary: Equatable {
    let count: Int
    /// Oturum sürelerinin ortalaması (sn); veri yoksa nil.
    let averageDuration: Double?
    /// Oturum ortalama RSSI'larının ortalaması (dBm); veri yoksa nil.
    let averageRSSI: Double?
    /// Ortalaması −85 dBm'in altında kalan oturum sayısı (zayıf).
    let weakSessions: Int
    /// En sık görülen kopma nedeni; veri yoksa nil.
    let mostCommonEndReason: String?

    static func make(sessions: [BleSessionQuality]) -> BleSessionQualitySummary {
        guard !sessions.isEmpty else {
            return BleSessionQualitySummary(count: 0, averageDuration: nil,
                                            averageRSSI: nil, weakSessions: 0,
                                            mostCommonEndReason: nil)
        }
        let durations = sessions.map(\.duration)
        let rssiValues = sessions.compactMap(\.averageRSSI)
        let weak = rssiValues.filter { $0 < -85 }.count
        let reasons = Dictionary(grouping: sessions.map(\.endReason), by: { $0 })
            .mapValues(\.count)
        let common = reasons.max { $0.value < $1.value }?.key
        return BleSessionQualitySummary(
            count: sessions.count,
            averageDuration: durations.reduce(0, +) / Double(durations.count),
            averageRSSI: rssiValues.isEmpty
                ? nil
                : rssiValues.reduce(0, +) / Double(rssiValues.count),
            weakSessions: weak,
            mostCommonEndReason: common)
    }
}
