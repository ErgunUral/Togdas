import Foundation

struct WatchSnapshot: Codable {
    let vin: String
    let vehicleName: String
    let locked: Bool?
    let doorCount: Int
    let openDoors: Int
    let trunkAjar: Bool?
    let powerState: Int?
    let ready: Bool
    let bleState: String
    let updatedAt: TimeInterval
    let telemetryAge: TimeInterval?
    /// Togg bulut telemetrisi. Sunucu döndürmediyse nil; saat 0 göstermez.
    let batteryPercent: Double?
    let rangeKM: Double?
    let outsideTemperatureC: Double?
    let auxiliaryBatteryPercent: Double?
    let odometerKM: Double?
    /// Ham sunucu değeri ("Charging" vb.); saat yalnızca "charging" eşleşmesine rozet basar.
    let chargingState: String?
    /// Panodaki yakınlık otomasyonu ayarı; saatte yalnızca durum gösterilir.
    let proximityEnabled: Bool
    /// Telefon oturumu sessizce yeniden kuruyorsa saat "yeniden bağlanıyor" der.
    let recovering: Bool?
    /// iPhone'daki son komut sonucunun gösterim metni; 24 saatten eski
    /// kayıt iPhone tarafında süzülür (widget kuralı). VIN/içerik ayrıntısı
    /// yazılmaz; yalnız etiket + doğrulama durumu + saat.
    let lastCommandText: String?

    private enum CodingKeys: String, CodingKey {
        case vin, vehicleName, locked, doorCount, openDoors, trunkAjar, powerState
        case ready, bleState, updatedAt, telemetryAge
        case batteryPercent, rangeKM, outsideTemperatureC
        case auxiliaryBatteryPercent, odometerKM, chargingState, proximityEnabled
        case recovering, lastCommandText
    }

    init(vin: String, vehicleName: String, locked: Bool?, doorCount: Int, openDoors: Int,
         trunkAjar: Bool?, powerState: Int?, ready: Bool, bleState: String,
         updatedAt: TimeInterval, telemetryAge: TimeInterval?,
         batteryPercent: Double?, rangeKM: Double?, outsideTemperatureC: Double?,
         auxiliaryBatteryPercent: Double? = nil, odometerKM: Double? = nil,
         chargingState: String? = nil, proximityEnabled: Bool = false,
         recovering: Bool? = nil, lastCommandText: String? = nil) {
        self.vin = vin
        self.vehicleName = vehicleName
        self.locked = locked
        self.doorCount = doorCount
        self.openDoors = openDoors
        self.trunkAjar = trunkAjar
        self.powerState = powerState
        self.ready = ready
        self.bleState = bleState
        self.updatedAt = updatedAt
        self.telemetryAge = telemetryAge
        self.batteryPercent = batteryPercent
        self.rangeKM = rangeKM
        self.outsideTemperatureC = outsideTemperatureC
        self.auxiliaryBatteryPercent = auxiliaryBatteryPercent
        self.odometerKM = odometerKM
        self.chargingState = chargingState
        self.proximityEnabled = proximityEnabled
        self.recovering = recovering
        self.lastCommandText = lastCommandText
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        vin = try c.decode(String.self, forKey: .vin)
        vehicleName = try c.decode(String.self, forKey: .vehicleName)
        locked = try c.decodeIfPresent(Bool.self, forKey: .locked)
        doorCount = try c.decodeIfPresent(Int.self, forKey: .doorCount) ?? 0
        openDoors = try c.decodeIfPresent(Int.self, forKey: .openDoors) ?? 0
        trunkAjar = try c.decodeIfPresent(Bool.self, forKey: .trunkAjar)
        powerState = try c.decodeIfPresent(Int.self, forKey: .powerState)
        ready = try c.decodeIfPresent(Bool.self, forKey: .ready) ?? false
        bleState = try c.decodeIfPresent(String.self, forKey: .bleState) ?? ""
        updatedAt = try c.decodeIfPresent(TimeInterval.self, forKey: .updatedAt) ?? 0
        telemetryAge = try c.decodeIfPresent(TimeInterval.self, forKey: .telemetryAge)
        batteryPercent = try c.decodeIfPresent(Double.self, forKey: .batteryPercent)
        rangeKM = try c.decodeIfPresent(Double.self, forKey: .rangeKM)
        outsideTemperatureC = try c.decodeIfPresent(Double.self, forKey: .outsideTemperatureC)
        auxiliaryBatteryPercent = try c.decodeIfPresent(Double.self, forKey: .auxiliaryBatteryPercent)
        odometerKM = try c.decodeIfPresent(Double.self, forKey: .odometerKM)
        chargingState = try c.decodeIfPresent(String.self, forKey: .chargingState)
        proximityEnabled = try c.decodeIfPresent(Bool.self, forKey: .proximityEnabled) ?? false
        recovering = try c.decodeIfPresent(Bool.self, forKey: .recovering)
        lastCommandText = try c.decodeIfPresent(String.self, forKey: .lastCommandText)
    }
}
