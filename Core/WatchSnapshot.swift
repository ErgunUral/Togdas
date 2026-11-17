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
    /// "Son görülme": BLE/bulut iletişiminin en yenisinin göreceli metni
    /// ("3 dakika önce · BLE"). Telefon tarafında `LastSeenSummary` ile
    /// üretilir; hiç iletişim yoksa nil (saat "—" gösterir, 0 yazmaz).
    let lastSeenText: String?
    /// Son BLE oturum kalitesinin tek satır özeti ("8 oturum · 2 zayıf ·
    /// ort −93 dBm"). Oturum kaydı yoksa nil.
    let sessionQualityText: String?
    /// Canlı şarj gözlemi: aktif oturum + kullanıcı hedefi. Saat, hedefe
    /// ulaşıldığında yerel bildirim/haptik üretir (oturum başına bir kez;
    /// dedupe anahtarı oturum başlangıcını içerir, VIN içermez).
    let chargingActive: Bool?
    let chargingTargetPercent: Int?
    let chargingStartedAt: TimeInterval?

    private enum CodingKeys: String, CodingKey {
        case vin, vehicleName, locked, doorCount, openDoors, trunkAjar, powerState
        case ready, bleState, updatedAt, telemetryAge
        case batteryPercent, rangeKM, outsideTemperatureC
        case auxiliaryBatteryPercent, odometerKM, chargingState, proximityEnabled
        case recovering, lastCommandText
        case lastSeenText, sessionQualityText
        case chargingActive, chargingTargetPercent, chargingStartedAt
    }

    init(vin: String, vehicleName: String, locked: Bool?, doorCount: Int, openDoors: Int,
         trunkAjar: Bool?, powerState: Int?, ready: Bool, bleState: String,
         updatedAt: TimeInterval, telemetryAge: TimeInterval?,
         batteryPercent: Double?, rangeKM: Double?, outsideTemperatureC: Double?,
         auxiliaryBatteryPercent: Double? = nil, odometerKM: Double? = nil,
         chargingState: String? = nil, proximityEnabled: Bool = false,
         recovering: Bool? = nil, lastCommandText: String? = nil,
         lastSeenText: String? = nil, sessionQualityText: String? = nil,
         chargingActive: Bool? = nil, chargingTargetPercent: Int? = nil,
         chargingStartedAt: TimeInterval? = nil) {
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
        self.lastSeenText = lastSeenText
        self.sessionQualityText = sessionQualityText
        self.chargingActive = chargingActive
        self.chargingTargetPercent = chargingTargetPercent
        self.chargingStartedAt = chargingStartedAt
    }

    init(from decoder: Decoder) throws {        let c = try decoder.container(keyedBy: CodingKeys.self)
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
        lastSeenText = try c.decodeIfPresent(String.self, forKey: .lastSeenText)
        sessionQualityText = try c.decodeIfPresent(String.self, forKey: .sessionQualityText)
        chargingActive = try c.decodeIfPresent(Bool.self, forKey: .chargingActive)
        chargingTargetPercent = try c.decodeIfPresent(Int.self, forKey: .chargingTargetPercent)
        chargingStartedAt = try c.decodeIfPresent(TimeInterval.self, forKey: .chargingStartedAt)
    }
}

// MARK: - Complication köprüsü ve gönderim darboğazı parmak izleri

extension WatchSnapshot {
    /// Complication app group'una yazılacak VIN'siz kopya. İlke iPhone
    /// widget deposuyla aynıdır ("VIN bu depoya yazılmaz"): complication
    /// yalnız gösterim verisi taşır, VIN gerekmez ve ekranda gösterilmez.
    /// Saat uygulamasının kendi cache'i (`WatchLink`, standart UserDefaults)
    /// gerçek VIN'i korur — komut isteği eşleştirmesi ona ihtiyaç duyar.
    var complicationCopy: WatchSnapshot {
        WatchSnapshot(vin: "", vehicleName: vehicleName, locked: locked,
                      doorCount: doorCount, openDoors: openDoors, trunkAjar: trunkAjar,
                      powerState: powerState, ready: ready, bleState: bleState,
                      updatedAt: updatedAt, telemetryAge: telemetryAge,
                      batteryPercent: batteryPercent, rangeKM: rangeKM,
                      outsideTemperatureC: outsideTemperatureC,
                      auxiliaryBatteryPercent: auxiliaryBatteryPercent,
                      odometerKM: odometerKM, chargingState: chargingState,
                      proximityEnabled: proximityEnabled, recovering: recovering,
                      lastCommandText: lastCommandText)
    }
}

extension WatchSnapshot {
    /// Saate gönderim kararında kullanılan gösterim parmak izi.
    /// Zaman damgaları (`updatedAt`, `telemetryAge`) bilinçli dışarıda:
    /// sürekli değişirler ve darboğaz kararını sürüklerler.
    var displayFingerprint: String {
        var parts: [String] = []
        parts.append(vin)
        parts.append(vehicleName)
        parts.append(locked.map { String($0) } ?? "n")
        parts.append(String(doorCount))
        parts.append(String(openDoors))
        parts.append(trunkAjar.map { String($0) } ?? "n")
        parts.append(powerState.map { String($0) } ?? "n")
        parts.append(String(ready))
        parts.append(bleState)
        parts.append(batteryPercent.map { String($0) } ?? "n")
        parts.append(rangeKM.map { String($0) } ?? "n")
        parts.append(outsideTemperatureC.map { String($0) } ?? "n")
        parts.append(auxiliaryBatteryPercent.map { String($0) } ?? "n")
        parts.append(odometerKM.map { String($0) } ?? "n")
        parts.append(chargingState ?? "n")
        parts.append(String(proximityEnabled))
        parts.append(recovering.map { String($0) } ?? "n")
        parts.append(lastCommandText ?? "n")
        parts.append(lastSeenText ?? "n")
        parts.append(sessionQualityText ?? "n")
        parts.append(chargingActive.map { String($0) } ?? "n")
        parts.append(chargingTargetPercent.map { String($0) } ?? "n")
        return parts.joined(separator: "|")
    }

    /// Darboğaza takılmadan hemen gönderilmesini gerektiren alanların
    /// parmak izi: bağlantı/komut durumu anında gitmeli.
    var importantFingerprint: String {
        var parts: [String] = []
        parts.append(String(ready))
        parts.append(bleState)
        parts.append(lastCommandText ?? "n")
        parts.append(recovering.map { String($0) } ?? "n")
        return parts.joined(separator: "|")
    }
}

extension WatchSnapshot {
    /// Saatte gösterilen verinin "bayat" sayılma eşiği. Saat uygulaması
    /// kendi tazelemesi için daha kısa eşik kullanır; complication bu
    /// süreden sonra veriyi "eski" olarak işaretler.
    static let staleAfter: TimeInterval = 3_600

    static func isStale(updatedAt: TimeInterval?, now: Date = Date(),
                        after: TimeInterval = staleAfter) -> Bool {
        guard let updatedAt else { return true }
        return now.timeIntervalSince1970 - updatedAt > after
    }
}


/// Saatten gelen yakınlık otomasyonu anahtar isteği: **araç komutu
/// değildir** — yaklaşma/uzaklaşma otomasyonunun uygulama içi anahtarı
/// yönetilir. BLE READY/telemetri şartı istemez; açmak hiçbir komut
/// göndermez, yalnız gelecekteki otomatik kararları etkinleştirir.
/// Metinler VIN içermez (gizlilik invariant'ı).
enum WatchProximityAutomationAction: Equatable {
    case enable, disable

    /// Saat kanalındaki eylem adından çözümleme; bilinmeyen eylem nil.
    static func parse(_ raw: String) -> WatchProximityAutomationAction? {
        switch raw {
        case "proximityOn": return .enable
        case "proximityOff": return .disable
        default: return nil
        }
    }

    /// Saat kanalındaki eylem adı.
    var action: String { self == .enable ? "proximityOn" : "proximityOff" }

    /// Saatte onay diyaloğunda gösterilecek metin.
    var confirmationText: String {
        self == .enable
            ? "Yakınlık otomasyonu açılacak. Araç komutu göndermez; yaklaşma/uzaklaşma otomatik kararları etkinleşir."
            : "Yakınlık otomasyonu kapatılacak. Devam eden otomatik komut akışı durdurulur; araca komut gönderilmez."
    }

    /// Uygulama sonrası saat kanalına dönen dürüst yanıt metni.
    var resultText: String {
        self == .enable
            ? "Yakınlık otomasyonu açıldı; araç komutu gönderilmedi."
            : "Yakınlık otomasyonu kapatıldı; araca komut gönderilmedi."
    }
}
