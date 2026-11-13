import Foundation

/// Yakınlık kalibrasyonunun eskime politikası.
///
/// Neden gerekli: eşikler bir kez kaydedilip yıllarca kalıyordu; kılıf,
/// araç içi konum veya telefon değişimi RSSI tabanını kaydırabilir ve
/// otomasyon sessizce yanlış çalışabilir. Uyarı **bilgilendirmedir**:
/// otomasyonu kapatmaz, komut göndermez.
///
/// Kasıtlı sınırlar:
/// - Hiç kalibrasyon yoksa (`savedAt == nil`) eskime uyarısı verilmez;
///   "hiç yapılmadı" ayrı bir durumdur (kart zaten ölçüm ister).
/// - Gün hesabı çağıranın takvimiyle yapılır (yerel gün sınırı).
enum ProximityCalibrationAge {
    static let refreshIntervalDays = 30

    static func daysSince(_ savedAt: Date, now: Date = Date(),
                          calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: savedAt)
        let end = calendar.startOfDay(for: now)
        return max(0, calendar.dateComponents([.day], from: start, to: end).day ?? 0)
    }

    static func needsRefresh(_ savedAt: Date?, now: Date = Date(),
                             calendar: Calendar = .current) -> Bool {
        guard let savedAt else { return false }
        return daysSince(savedAt, now: now, calendar: calendar) >= refreshIntervalDays
    }

    static func message(days: Int) -> String {
        "Kalibrasyon \(days) gün önce yapıldı. Kılıf/konum değiştiyse sinyal kayabilir; yenilemek için yeniden ölçüm al."
    }
}
