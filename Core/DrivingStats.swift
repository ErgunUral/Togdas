import Foundation

/// VIN bazlı sürüş istatistikleri (aylık km ve tahmini enerji maliyeti).
///
/// Km, günlük odometer okumalarının farkından hesaplanır. Her gün için günün
/// ilk ve son okuması saklanır; böylece aynı gün içinde birden çok okuma
/// geldiğinde ay başındaki mesafe kaybolmaz.
/// Maliyet tahmini 17 kWh/100 km ve 10 ₺/kWh varsayımıyla yapılır (kayıp yok).
struct DrivingStats: Equatable {
    let month: String // "2026-10"
    let km: Double
    let estimatedKWh: Double
    let estimatedCostTRY: Double
    /// Ay içinde kaç gün veri var.
    let daysWithData: Int

    static let consumptionKWhPer100km: Double = 17
    static let pricePerKWhTRY: Double = 10

    static func make(month: String, km: Double, daysWithData: Int) -> DrivingStats {
        let kwh = km * consumptionKWhPer100km / 100
        return DrivingStats(
            month: month,
            km: km,
            estimatedKWh: kwh,
            estimatedCostTRY: kwh * pricePerKWhTRY,
            daysWithData: daysWithData
        )
    }
}

final class DrivingStatsStore {
    private let vin: String
    private let defaults: UserDefaults
    private var key: String { "toqdas.drivingStats.\(vin)" }

    /// Geriye dönük kaç gün tutulur.
    static let retentionDays = 90

    init(vin: String, defaults: UserDefaults = .standard) {
        self.vin = vin
        self.defaults = defaults
    }

    private struct Record: Codable {
        let date: String // "2026-10-29"
        var firstOdometer: Double
        var lastOdometer: Double
    }

    private var records: [Record] {
        get {
            guard let data = defaults.data(forKey: key) else { return [] }
            return (try? JSONDecoder().decode([Record].self, from: data)) ?? []
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: key)
        }
    }

    /// Yeni odometer okuması geldiğinde çağrılır; günün ilk/son okuması güncellenir.
    func record(odometer: Double, on date: Date = Date()) {
        guard odometer.isFinite, odometer >= 0 else { return }
        let day = Self.dayString(date)
        var list = records

        if let idx = list.firstIndex(where: { $0.date == day }) {
            list[idx].lastOdometer = odometer
        } else {
            list.append(Record(date: day, firstOdometer: odometer, lastOdometer: odometer))
        }

        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.retentionDays, to: date) ?? date
        let cutoffDay = Self.dayString(cutoff)
        list = list.filter { $0.date >= cutoffDay }
        records = list
    }

    /// Belirtilen ayın istatistikleri.
    func monthlyStats(for date: Date = Date()) -> DrivingStats {
        let month = Self.monthString(date)
        let monthRecords = records
            .filter { $0.date.hasPrefix(month) }
            .sorted { $0.date < $1.date }

        guard let first = monthRecords.first, let last = monthRecords.last else {
            return .make(month: month, km: 0, daysWithData: 0)
        }
        let km = max(0, last.lastOdometer - first.firstOdometer)
        return .make(month: month, km: km, daysWithData: monthRecords.count)
    }

    /// Son 7 günün km'si (bugün dahil).
    func last7DaysKm(asOf date: Date = Date()) -> Double {
        let days = (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: date) }
            .map { Self.dayString($0) }
        let filtered = records.filter { days.contains($0.date) }.sorted { $0.date < $1.date }
        guard let first = filtered.first, let last = filtered.last else { return 0 }
        return max(0, last.lastOdometer - first.firstOdometer)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }

    private static func dayString(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    private static func monthString(_ date: Date) -> String {
        monthFormatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM"
        return f
    }()
}
