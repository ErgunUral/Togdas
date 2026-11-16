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

/// Tamamlanmış bir şarj oturumunun geçmiş girdisi. Enerji telemetrisi
/// olmadığı için yalnız yüzde, süre ve gözlemlenen hız taşır; kWh yok.
struct ChargingHistoryEntry: Codable, Equatable {
    let startedAt: TimeInterval
    let endedAt: TimeInterval
    /// Oturumdaki ilk yüzde örneği; telemetri hiç gelmediyse nil.
    let startPercent: Double?
    /// Oturum bitişindeki yüzde; bilinmiyorsa nil.
    let endPercent: Double?
    /// Oturum sonunda gözlemlenen doluluk hızı (%/dk); ölçülemediyse nil.
    let ratePerMinute: Double?
}

struct ChargingSessionRecord: Codable, Equatable {
    var charging: Bool = false
    var startedAt: TimeInterval?
    var samples: [ChargingSample] = []
    var last: ChargingLastSession?
    /// Tamamlanmış oturumların geçmişi (en yeni sonda); üst sınır tracker'da.
    var history: [ChargingHistoryEntry] = []

    static let empty = ChargingSessionRecord()

    init() {}

    // Eski kayıtlarda "history" anahtarı yok; decodeIfPresent ile korunurlar.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        charging = try container.decodeIfPresent(Bool.self, forKey: .charging) ?? false
        startedAt = try container.decodeIfPresent(TimeInterval.self, forKey: .startedAt)
        samples = try container.decodeIfPresent([ChargingSample].self, forKey: .samples) ?? []
        last = try container.decodeIfPresent(ChargingLastSession.self, forKey: .last)
        history = try container.decodeIfPresent([ChargingHistoryEntry].self, forKey: .history) ?? []
    }
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
                        maxSamples: Int = 40,
                        maxHistory: Int = 20) -> ChargingSessionRecord {
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
            let finished = ChargingLastSession(
                startedAt: record.startedAt ?? at.timeIntervalSince1970,
                endedAt: at.timeIntervalSince1970,
                lastPercent: percent)
            result.last = finished
            // Geçmiş girdisi örnekler silinmeden önce üretilir. Canlı kartın
            // 15 dakikalık penceresinden farklı olarak burada tüm oturumun
            // eğimi kullanılır (canlı pencere kısa oturumları eler); ölçüm
            // koşulları sağlanmazsa hız nil kalır, 0 gösterilmez.
            let entry = ChargingHistoryEntry(
                startedAt: finished.startedAt,
                endedAt: finished.endedAt,
                startPercent: record.samples.first?.percent,
                endPercent: percent,
                ratePerMinute: rate(in: record.samples, now: at,
                                    window: historyWindow))
            result.samples = []
            result.history.append(entry)
            if result.history.count > maxHistory {
                result.history.removeFirst(result.history.count - maxHistory)
            }
            result.charging = false
            result.startedAt = nil
        }
        return result
    }

    /// Geçmiş girdisindeki hız için örnek penceresi: bir oturumun tamamını
    /// kapsayacak kadar geniş (canlı karttaki 15 dakikalık pencereden farklı).
    static let historyWindow: TimeInterval = 7 * 24 * 3600

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


/// Şarj hedefi: kullanıcı seçimi (Kapalı / %50 / %80 / %90). Uygulama araca
/// durdurma komutu **göndermez**; hedefe ulaşıldığında yerel bildirim üretir
/// ve kullanıcıyı uygulamadan kontrol etmeye yönlendirir. Eksik yüzde
/// "ulaşıldı" üretmez; gerçek %100 korunur.
enum ChargingTargetPolicy {
    /// Seçenekler: nil = kapalı.
    static let options: [Int?] = [nil, 50, 80, 90]

    /// Hedefe kalan yüzde puanı; hedef yoksa veya yüzde bilinmiyorsa nil.
    /// Hedefin üzerine geçildiğinde 0 döner (eksi kalan gösterilmez).
    static func remaining(target: Int?, percent: Double?) -> Double? {
        guard let target, let percent, percent.isFinite else { return nil }
        return max(0, Double(target) - percent)
    }

    /// Hedefe ulaşıldı mı? Şarj aktifken çağrılır; bilinmeyen yüzde asla
    /// "ulaşıldı" sayılmaz.
    static func reached(target: Int?, percent: Double?) -> Bool {
        guard let target, let percent, percent.isFinite else { return false }
        return percent >= Double(target)
    }
}

/// VIN başına şarj hedefi saklaması (`toqdas.charging.target.<vin>`).
/// 0/anahtar yok = kapalı.
struct ChargingTargetStore {
    static func key(_ vin: String) -> String { "toqdas.charging.target.\(vin)" }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load(vin: String) -> Int? {
        guard !vin.isEmpty else { return nil }
        let value = defaults.integer(forKey: Self.key(vin))
        return value == 0 ? nil : value
    }

    func save(_ target: Int?, vin: String) {
        guard !vin.isEmpty else { return }
        if let target {
            defaults.set(target, forKey: Self.key(vin))
        } else {
            defaults.removeObject(forKey: Self.key(vin))
        }
    }
}
