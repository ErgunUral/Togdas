import Foundation

/// VIN bazlı sürüş istatistikleri (aylık km, enerji ve maliyet).
///
/// Km, günlük odometer okumalarının farkından hesaplanır. Her gün için günün
/// ilk ve son okuması saklanır; böylece aynı gün içinde birden çok okuma
/// geldiğinde ay başındaki mesafe kaybolmaz.
///
/// Enerji tüketimi ölçülebiliyorsa batarya yüzdesi farkından hesaplanır:
/// `kWh = Δ% × 88,5 kWh / 100`. Şarj nedeniyle yüzde artan aralıklar
/// (ve anormal sıçramalar) hesaba katılmaz. Yeterli ölçüm yoksa 17 kWh/100 km
/// varsayılanı kullanılır ve bu durum arayüzde belirtilir.
struct DrivingStats: Equatable {
    let month: String // "2026-10"
    let km: Double
    let estimatedKWh: Double
    let estimatedCostTRY: Double
    /// Ay içinde kaç gün veri var.
    let daysWithData: Int
    /// Kullanılan tüketim (kWh/100 km).
    let consumptionKWhPer100km: Double
    /// Tüketim gerçek batarya ölçümünden mi, varsayılan mı?
    let consumptionIsMeasured: Bool

    static let defaultConsumptionKWhPer100km: Double = 17
    static let batteryCapacityKWh: Double = 88.5
    static let pricePerKWhTRY: Double = 10

    static func make(
        month: String,
        km: Double,
        daysWithData: Int,
        consumptionKWhPer100km: Double? = nil
    ) -> DrivingStats {
        let consumption = consumptionKWhPer100km ?? defaultConsumptionKWhPer100km
        let kwh = km * consumption / 100
        return DrivingStats(
            month: month,
            km: km,
            estimatedKWh: kwh,
            estimatedCostTRY: kwh * pricePerKWhTRY,
            daysWithData: daysWithData,
            consumptionKWhPer100km: consumption,
            consumptionIsMeasured: consumptionKWhPer100km != nil
        )
    }
}

final class DrivingStatsStore {
    private let vin: String
    private let defaults: UserDefaults
    private var key: String { "toqdas.drivingStats.\(vin)" }

    /// Geriye dönük kaç gün tutulur.
    static let retentionDays = 90
    /// Ölçülen tüketimin güvenilir sayılması için gereken en az km.
    static let minimumMeasuredKm: Double = 20
    /// İki okuma arasında kabul edilen en büyük deşarj (%).
    static let maximumPlausibleDischargePercent = 60.0

    init(vin: String, defaults: UserDefaults = .standard) {
        self.vin = vin
        self.defaults = defaults
    }

    private struct Record: Codable {
        let date: String // "2026-10-29"
        var firstOdometer: Double
        var lastOdometer: Double
        var firstBatteryPercent: Double?
        var lastBatteryPercent: Double?
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
    func record(odometer: Double, batteryPercent: Double? = nil, on date: Date = Date()) {
        guard odometer.isFinite, odometer >= 0 else { return }
        let battery = batteryPercent.flatMap { $0.isFinite && (0...100).contains($0) ? $0 : nil }
        let day = Self.dayString(date)
        var list = records

        if let idx = list.firstIndex(where: { $0.date == day }) {
            list[idx].lastOdometer = odometer
            if let battery { list[idx].lastBatteryPercent = battery }
        } else {
            list.append(Record(
                date: day,
                firstOdometer: odometer,
                lastOdometer: odometer,
                firstBatteryPercent: battery,
                lastBatteryPercent: battery
            ))
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
        return .make(
            month: month,
            km: km,
            daysWithData: monthRecords.count,
            consumptionKWhPer100km: measuredConsumption(in: monthRecords)
        )
    }

    /// Son 7 günün km'si (bugün dahil).
    func last7DaysKm(asOf date: Date = Date()) -> Double {
        let days = (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: date) }
            .map { Self.dayString($0) }
        let filtered = records.filter { days.contains($0.date) }.sorted { $0.date < $1.date }
        guard let first = filtered.first, let last = filtered.last else { return 0 }
        return max(0, last.lastOdometer - first.lastOdometer)
    }

    /// Son 7 günün ölçülen tüketimi (kWh/100 km), güvenilir değilse nil.
    func last7DaysConsumption(asOf date: Date = Date()) -> Double? {
        let days = (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: date) }
            .map { Self.dayString($0) }
        return measuredConsumption(in: records.filter { days.contains($0.date) }.sorted { $0.date < $1.date })
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }

    /// Ardışık kayıtlar arasında deşarj edilen enerjiyi toplar.
    /// Şarj (yüzde artışı) ve mantıksız sıçramalar atlanır.
    private func measuredConsumption(in orderedRecords: [Record]) -> Double? {
        guard !orderedRecords.isEmpty else { return nil }
        var energyKWh: Double = 0
        var km: Double = 0

        for record in orderedRecords {
            guard let startPercent = record.firstBatteryPercent,
                  let endPercent = record.lastBatteryPercent else { continue }
            let deltaPercent = startPercent - endPercent
            let deltaKm = record.lastOdometer - record.firstOdometer
            guard deltaKm > 0, deltaPercent > 0, deltaPercent <= Self.maximumPlausibleDischargePercent else { continue }
            energyKWh += deltaPercent * DrivingStats.batteryCapacityKWh / 100
            km += deltaKm
        }

        for (previous, current) in zip(orderedRecords, orderedRecords.dropFirst()) {
            guard let startPercent = previous.lastBatteryPercent,
                  let endPercent = current.firstBatteryPercent else { continue }
            let deltaPercent = startPercent - endPercent
            let deltaKm = current.firstOdometer - previous.lastOdometer
            guard deltaKm > 0, deltaPercent > 0, deltaPercent <= Self.maximumPlausibleDischargePercent else { continue }
            energyKWh += deltaPercent * DrivingStats.batteryCapacityKWh / 100
            km += deltaKm
        }

        guard km >= Self.minimumMeasuredKm, energyKWh > 0 else { return nil }
        let consumption = energyKWh / km * 100
        guard consumption.isFinite, consumption > 0, consumption < 100 else { return nil }
        return consumption
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
