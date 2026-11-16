import Foundation

/// Canlı şarj gözlemi: yüzde/menzil telemetrisinden oturum süresi,
/// gözlemlenen doluluk hızı ve tahmini bitiş üretir.
///
/// Dürüstlük sınırları (resmi uygulamadaki iki tuzaktan kaçınmak için):
/// - kWh/kW telemetrisi gelmediği için **enerji gösterilmez**; hız, yüzde
///   değişiminin eğiminden hesaplanır ve arayüzde "gözlemlenen" etiketi taşır.
/// - "Kalan süre" ile "tahmini bitiş" **tek tabandan** hesaplanır: aynı hız
///   değerini kullanırlar, asla çelişmezler.
/// - Oturum yalnız uygulama açıkken ve telemetri gelirken ölçülür; arka
///   planda ölçüm yapılmadığı arayüzde belirtilir.
/// - VIN yalnız depolama anahtarında kullanılır; gösterim metinlerinde yok.
struct ChargingSample: Codable, Equatable {
    let at: TimeInterval
    let percent: Double
}

struct ChargingLastSession: Codable, Equatable {
    let startedAt: TimeInterval
    let endedAt: TimeInterval
    let lastPercent: Double?
}

struct ChargingSessionRecord: Codable, Equatable {
    var charging: Bool = false
    var startedAt: TimeInterval?
    var samples: [ChargingSample] = []
    var last: ChargingLastSession?

    static let empty = ChargingSessionRecord()
}

/// Arayüze gitmek için üretilmiş tek anlık durum; hesaplama `liveView`'da.
struct ChargingLiveState: Equatable {
    let charging: Bool
    /// Aktif oturumun başlangıcı; şarj yoksa nil.
    let startedAt: TimeInterval?
    /// Son 15 dakikadaki gözlemlenen yüzde hızı (%/dk); ölçülemediyse nil.
    let percentPerMinute: Double?
    let lastSession: ChargingLastSession?
}

enum ChargingStateClassifier {
    /// Ham sunucu değerinden aktif şarj kararı. "Planlı", "tamamlandı" ve
    /// "şarj etmiyor" aktif şarj sayılmaz.
    static func isCharging(_ raw: String?) -> Bool {
        guard let raw else { return false }
        let lower = raw.lowercased()
        if lower.contains("not") { return false }
        if lower.contains("finish") || lower.contains("complete") { return false }
        if lower.contains("schedule") { return false }
        return lower.contains("charg")
    }
}

enum ChargingSessionTracker {
    /// Yeni gözlemi oturum kaydına işler: başlangıç, örnek birikimi ve
    /// oturum bitişi (son oturum özetine dönüş).
    static func updated(_ record: ChargingSessionRecord, charging: Bool,
                        percent: Double?, at: Date,
                        maxSamples: Int = 40) -> ChargingSessionRecord {
        var result = record
        if charging {
            if !record.charging || record.startedAt == nil {
                result.startedAt = at.timeIntervalSince1970
                result.samples = []
            }
            result.charging = true
            if let percent {
                result.samples.append(ChargingSample(at: at.timeIntervalSince1970, percent: percent))
                if result.samples.count > maxSamples {
                    result.samples.removeFirst(result.samples.count - maxSamples)
                }
            }
        } else if record.charging {
            result.last = ChargingLastSession(
                startedAt: record.startedAt ?? at.timeIntervalSince1970,
                endedAt: at.timeIntervalSince1970,
                lastPercent: percent)
            result.charging = false
            result.startedAt = nil
            result.samples = []
        }
        return result
    }

    /// Son `window` saniyedeki yüzde örneklerinin en küçük kareler eğimi,
    /// %/dk olarak. Ölçüm için en az iki örnek ve en az `minSpan` yayılım
    /// gerekir; eğim gürültü eşiğinin altındaysa nil döner (0 gösterilmez).
    static func rate(in samples: [ChargingSample], now: Date = Date(),
                     minSpan: TimeInterval = 180, window: TimeInterval = 900) -> Double? {
        let cutoff = now.timeIntervalSince1970 - window
        let recent = samples.filter { $0.at >= cutoff && $0.percent >= 0 }
        guard recent.count >= 2,
              let first = recent.first, let last = recent.last,
              last.at - first.at >= minSpan else { return nil }

        let count = Double(recent.count)
        let meanX = recent.reduce(0.0) { $0 + $1.at } / count
        let meanY = recent.reduce(0.0) { $0 + $1.percent } / count
        var covariance = 0.0
        var variance = 0.0
        for sample in recent {
            covariance += (sample.at - meanX) * (sample.percent - meanY)
            variance += (sample.at - meanX) * (sample.at - meanX)
        }
        guard variance > 0 else { return nil }
        let perMinute = (covariance / variance) * 60
        return perMinute > 0.02 ? perMinute : nil
    }

    /// Arayüzün tükettiği anlık durum. Hız yalnız aktif şarjda hesaplanır.
    static func liveView(record: ChargingSessionRecord,
                         now: Date = Date()) -> ChargingLiveState {
        let rate = record.charging ? rate(in: record.samples, now: now) : nil
        return ChargingLiveState(
            charging: record.charging,
            startedAt: record.charging ? record.startedAt : nil,
            percentPerMinute: rate,
            lastSession: record.last)
    }
}

/// VIN başına kalıcı oturum kaydı (`toqdas.charging.session.<vin>`).
/// Yükleme kaydın devamını sağlar: uygulama açılıp kapansa da başlangıç
/// zamanı korunur; ancak ölçüm yine yalnız telemetri gelirken ilerler.
struct ChargingSessionStore {
    static func sessionKey(_ vin: String) -> String { "toqdas.charging.session.\(vin)" }
    static func lastKey(_ vin: String) -> String { "toqdas.charging.last.\(vin)" }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load(vin: String) -> ChargingSessionRecord {
        guard !vin.isEmpty,
              let data = defaults.data(forKey: Self.sessionKey(vin)),
              let record = try? JSONDecoder().decode(ChargingSessionRecord.self, from: data) else {
            return .empty
        }
        return record
    }

    func save(_ record: ChargingSessionRecord, vin: String) {
        guard !vin.isEmpty,
              let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: Self.sessionKey(vin))
    }

    func clear(vin: String) {
        guard !vin.isEmpty else { return }
        defaults.removeObject(forKey: Self.sessionKey(vin))
    }
}
