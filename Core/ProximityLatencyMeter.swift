import Foundation

/// Yakınlık döngüsü gecikme ölçümü (Android `1.0.24.57` paritesi:
/// yaklaşma tanı/latency raporu, iOS karşılığı).
///
/// Yalnızca yerel olarak ölçülebilecek kanıtları ölçer:
/// - döngü tabanı (etkinleştirme, uzaklaşma teyidi veya fresh cycle sıfırlaması)
///   → yaklaşma **kararına** kadar geçen süre (ms) ve bu pencere içinde
///   gate'e beslenen güncel örnek sayısı,
/// - profilin beklenen karar penceresi (gerekli örnek sayısı × RSSI aralığı).
///
/// Kasıtlı sınırlar:
/// - Araç tarafı ACK süresini ölçmez; "ACK fiziksel teyit değil" ilkesi geçerlidir.
/// - Arka planda iOS uyanma sıklığını kendisi belirlediğinden arka plan
///   gecikmesi raporlanmaz; bu sayaç yalnızca ön plandaki karar akışını ölçer.
/// - Taban yoksa gecikme `nil` kalır; arayüzde "—" gösterilir, asla 0 yazılmaz.
struct ProximityLatencyMeter: Equatable {
    struct Reading: Codable, Equatable, Identifiable {
        let id: UUID
        let at: Date
        /// Döngü tabanından karara kadar geçen süre; taban yoksa `nil`.
        let cycleLatencyMs: Int?
        /// Karara kadar beslenen güncel örnek sayısı.
        let samples: Int

        /// Profilin beklenen karar penceresi (gerekli örnek × poll aralığı), sn.
        static func expectedInterval(for profile: ProximityProfile) -> TimeInterval {
            Double(profile.requiredSamples) * profile.pollInterval
        }
    }

    /// Yakınlık döngüsünün taban zamanı; `nil` → taban yok, gecikme bilinmez.
    private(set) var baselineAt: Date?
    /// Tabandan bu yana gate'e beslenen örnek sayısı.
    private(set) var samplesSinceBaseline = 0

    mutating func noteBaseline(now: Date) {
        baselineAt = now
        samplesSinceBaseline = 0
    }

    mutating func noteSample() {
        samplesSinceBaseline += 1
    }

    /// Yaklaşma kararı anındaki ölçüm. Kararı okur, sayaç sıfırlamaz:
    /// taban yeni uzaklaşma teyidiyle yenilenir.
    mutating func noteApproachDecision(now: Date) -> Reading {
        Reading(
            id: UUID(),
            at: now,
            cycleLatencyMs: baselineAt.map { Self.latencyMs(from: $0, to: now) },
            samples: samplesSinceBaseline
        )
    }

    /// Uzaklaşma teyidi yeni bir döngü tabanı kurar.
    mutating func noteDepartureDecision(now: Date) {
        noteBaseline(now: now)
    }

    static func latencyMs(from start: Date, to end: Date) -> Int {
        let interval = end.timeIntervalSince(start)
        return max(0, Int((interval * 1000).rounded()))
    }
}
