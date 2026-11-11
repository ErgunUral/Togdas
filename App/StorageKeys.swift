import Foundation

/// Tüm `toqdas.*` UserDefaults anahtar biçimlerinin **tek kaynağı**.
///
/// Neden gerekli: anahtar biçimleri birden fazla dosyada kopyalanmıştı
/// (ör. `toqdas.proximity.near.<vin>` hem DashboardView hem
/// ProximityDetectionMonitor'da elle yazılıyordu). Yazım hatası sessiz
/// veri kaybı yaratır; biçimler artık yalnız burada tanımlı.
/// VIN'li anahtarlar araç değişince otomatik ayrışır; anahtar metni
/// loglanmaz (VIN anahtar adında olsa da tanı günlüğüne yazılmaz).
enum StorageKeys {
    // MARK: VIN'li anahtarlar

    static func climateTarget(_ vin: String) -> String { "toqdas.climateTarget.\(vin)" }
    static func proximityEnabled(_ vin: String) -> String { "toqdas.proximity.enabled.\(vin)" }
    static func proximityNear(_ vin: String) -> String { "toqdas.proximity.near.\(vin)" }
    static func proximityFar(_ vin: String) -> String { "toqdas.proximity.far.\(vin)" }
    static func proximityProfile(_ vin: String) -> String { "toqdas.proximity.profile.\(vin)" }
    static func proximityAutoOffEnabled(_ vin: String) -> String { "toqdas.proximity.autoOff.enabled.\(vin)" }
    static func proximityAutoOffMinutes(_ vin: String) -> String { "toqdas.proximity.autoOff.minutes.\(vin)" }
    static func proximityAutoOffCustom(_ vin: String) -> String { "toqdas.proximity.autoOff.custom.\(vin)" }
    static func proximityAutoOffDeadline(_ vin: String) -> String { "toqdas.proximity.autoOff.deadline.\(vin)" }
    static func auxiliaryHistory(_ vin: String) -> String { "toqdas.aux.history.\(vin)" }
    /// 12 V bildirim tekniği: ciddiyet başına günde bir kez (`critical`/`warning`).
    static func auxiliaryNotified(_ vin: String, severity: String) -> String { "toqdas.auxbattery.notified.\(vin).\(severity)" }
    /// Lastik bildirim tekniği: pozisyon × ciddiyet başına günde bir kez.
    static func tireNotified(_ vin: String, position: String, severity: String) -> String { "toqdas.tire.notified.\(vin).\(position).\(severity)" }
    /// Bakım bildirim tekniği: bakım maddesi başına günde bir kez.
    static func maintenanceNotified(_ vin: String, itemID: UUID) -> String { "toqdas.maintenance.notify.\(vin).\(itemID.uuidString)" }

    // MARK: Global anahtarlar

    static let theme = "toqdas.theme"
    static let dashboardLayout = "toqdas.dashboardLayout"
    static let chargeCapacityKWh = "toqdas.chargeCapacityKWh"
    static let chargePricePerKWh = "toqdas.chargePricePerKWh"
    static let epdkFetchedAt = "toqdas.epdk.fetchedAt"
    static let epdkNextFetchAt = "toqdas.epdk.nextFetchAt"
}
