import Foundation

/// 12 V akü günlük geçmişi (Android `aux_history_<vin>_<tarih>` paritesi).
///
/// Gün başına **en güncel** ölçüm saklanır; daha eski zamanlı aynı gün
/// kaydı yok sayılır. Eksik gün gösterimde `—` olur ("bilgi yok" ≠ uyarı,
/// ≠ 0); gerçek 0 değeri `%0` olarak korunur.
///
/// Kasıtlı sınırlar:
/// - Yüzde aralığı dışı (0–100) ve sonlu olmayan değerler kaydedilmez.
/// - En fazla `maxSamples` gün tutulur; eskiden silinir.
/// - Mesafe/trend iddiası taşımaz: bu ham günlük değerlerdir.
struct AuxiliaryBatteryHistory: Codable, Equatable {
    struct Sample: Codable, Equatable {
        let day: String
        let percent: Int
        let recordedAt: Date
    }

    private(set) var samples: [Sample] = []

    /// Android tarafı da günlük kaba tutar; 30 gün makul bir üst sınırdır.
    static let maxSamples = 30

    /// Kayıt: aynı günün daha yeni ölçümü eskisini değiştirir; daha eski
    /// zamanlı kayıt mevcutsa `false` döner (geriye yazım engellenir).
    mutating func record(percent: Double?, on date: Date, calendar: Calendar = .current) -> Bool {
        guard let percent, percent.isFinite, percent >= 0, percent <= 100 else { return false }
        let day = Self.dayKey(for: date, calendar: calendar)
        let sample = Sample(day: day, percent: Int(percent.rounded()), recordedAt: date)
        if let index = samples.firstIndex(where: { $0.day == day }) {
            guard samples[index].recordedAt <= sample.recordedAt else { return false }
            samples[index] = sample
        } else {
            samples.append(sample)
        }
        samples.sort { $0.day < $1.day }
        if samples.count > Self.maxSamples {
            samples.removeFirst(samples.count - Self.maxSamples)
        }
        return true
    }

    /// Son `count` günün gösterim değerleri **eskiden yeniye** (bugün dahil).
    /// Kaydı olmayan gün `—` döner.
    func displayValues(count: Int, today: Date, calendar: Calendar = .current) -> [String] {
        let days = (0..<max(1, count)).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let keys = days.map { Self.dayKey(for: $0, calendar: calendar) }
        return Array(
            keys
                .map { key -> String in
                    guard let sample = samples.last(where: { $0.day == key }) else { return "—" }
                    return "%\(sample.percent)"
                }
                .reversed()
        )
    }

    /// Son `count` günün sayısal değerleri eskiden yeniye (bugün dahil);
    /// kaydı olmayan gün `nil` döner (gösterimde "—", asla 0 değil).
    /// Gerçek 0 değeri `0.0` olarak korunur.
    func numericValues(count: Int, today: Date, calendar: Calendar = .current) -> [Double?] {
        let days = (0..<max(1, count)).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let keys = days.map { Self.dayKey(for: $0, calendar: calendar) }
        return Array(
            keys
                .map { key -> Double? in
                    guard let sample = samples.last(where: { $0.day == key }) else { return nil }
                    return Double(sample.percent)
                }
                .reversed()
        )
    }

    /// "2026-11-11" biçimli gün anahtarı; yerel takvim günü esas alınır.
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}
