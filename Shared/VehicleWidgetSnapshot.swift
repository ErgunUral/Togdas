import Foundation

/// WidgetKit'in uygulama ile paylaştığı salt okunur, hassas olmayan araç özeti.
/// VIN, oturum token'ı, sertifika ve anahtar malzemesi bu depoya yazılmaz.
struct VehicleWidgetSnapshot: Codable, Equatable {
    let vehicleName: String
    let locked: Bool?
    let batteryPercent: Double?
    let rangeKM: Double?
    /// Bu ayın gerçek şarj harcaması; kayıt yoksa nil. Tahmin yazılmaz.
    let monthlyChargeSpendTRY: Double?
    let bleReady: Bool
    let bleUpdatedAt: Date?
    let cloudUpdatedAt: Date?
    let savedAt: Date
    /// Son bilinen toplam kilometre; önbellekte yoksa nil. Tahmin yazılmaz.
    var odometerKM: Double?
    /// Son bilinen dış sıcaklık (°C); önbellekte yoksa nil.
    var outsideTemperatureC: Double?
    /// Son bilinen 12 V akü yüzdesi; bulut verisi yoksa nil ("—" gösterilir).
    /// Eşik kararı widget'ta AuxiliaryBatteryPolicy ile verilir; bu alan
    /// yalnızca ham değer taşır.
    var auxiliaryBatteryPercent: Double?
    /// Garajdaki araç sayısı; tek araçsa gizlenir, gizlilik için VIN/iskelet yok.
    var vehicleCount: Int?

    static let appGroup = "group.com.toqdas.ios"
    static let storageKey = "toqdas.widget.snapshot.v1"
    static let widgetKind = "ToqdasVehicleStatusWidget"

    var lockDataIsStale: Bool {
        guard let bleUpdatedAt else { return true }
        return Date().timeIntervalSince(bleUpdatedAt) > 5 * 60
    }

    var displayBattery: String {
        guard let batteryPercent, batteryPercent.isFinite else { return "—" }
        return "\(Int(batteryPercent.rounded()))%"
    }

    var displayRange: String {
        guard let rangeKM, rangeKM.isFinite else { return "—" }
        return "\(Int(rangeKM.rounded())) km"
    }

    /// 12 V akü metni: Android .57 widget paritesi ("—%" / "%X").
    /// Eksik veri asla 0 gösterilmez.
    var displayAuxiliaryBattery: String {
        guard let auxiliaryBatteryPercent, auxiliaryBatteryPercent.isFinite,
              auxiliaryBatteryPercent >= 0, auxiliaryBatteryPercent <= 100 else {
            return "—%"
        }
        return "%\(Int(auxiliaryBatteryPercent.rounded()))"
    }

    var displayChargeSpend: String {
        guard let monthlyChargeSpendTRY, monthlyChargeSpendTRY.isFinite, monthlyChargeSpendTRY >= 0 else {
            return "—"
        }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        let text = formatter.string(from: NSNumber(value: monthlyChargeSpendTRY)) ?? "—"
        return "\(text) ₺"
    }

    var displayLock: String {
        guard !lockDataIsStale else { return "Veri eski" }
        switch locked {
        case true: return "Kilitli"
        case false: return "Kilit açık"
        case nil: return "—"
        }
    }

    var displayOdometer: String {
        guard let odometerKM, odometerKM.isFinite, odometerKM >= 0 else { return "— km" }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.maximumFractionDigits = 0
        let text = formatter.string(from: NSNumber(value: odometerKM.rounded())) ?? "—"
        return "\(text) km"
    }

    /// Eksik veri "—" kuralı; gerçek 0°C değeri "0°C" kalır.
    var displayOutsideTemperature: String {
        guard let outsideTemperatureC, outsideTemperatureC.isFinite, outsideTemperatureC >= -60, outsideTemperatureC <= 60 else {
            return "—°C"
        }
        return "\(Int(outsideTemperatureC.rounded()))°C"
    }

    /// Tek araçta sayı gürültüdür; yalnız çoklu garajda gösterilir.
    var displayVehicleCountBadge: String? {
        guard let vehicleCount, vehicleCount > 1 else { return nil }
        return "\(vehicleCount) araç"
    }

    /// Veri yaşı rozeti. Öncelik canlı/kaydedilmiş BLE kilit bilgisi; BLE yoksa
    /// bulut telemetri zamanı kullanılır. Hiç veri yoksa "—"/bilgi yok kuralı
    /// burada da geçerlidir: 0 veya sahte tazelik yazılmaz.
    var freshnessText: String {
        if let bleUpdatedAt {
            if lockDataIsStale { return "Son BLE: \(time(bleUpdatedAt))" }
            return bleReady ? "Canlı BLE · \(time(bleUpdatedAt))" : "Son BLE · \(time(bleUpdatedAt))"
        }
        if let cloudUpdatedAt { return "Bulut · \(time(cloudUpdatedAt))" }
        return "Kilit bilgisi yok"
    }

    /// Widget ailesine göre renk: yalnızca canlı BLE yeşildir; bulut verisi
    /// tazelik taslağı vermez, turuncu ile "canlı değil" sinyali korunur.
    var freshnessIsLive: Bool {
        bleReady && !lockDataIsStale
    }

    private func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

enum VehicleWidgetSnapshotStore {
    static func save(_ snapshot: VehicleWidgetSnapshot) {
        guard let defaults = UserDefaults(suiteName: VehicleWidgetSnapshot.appGroup),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: VehicleWidgetSnapshot.storageKey)
    }

    static func load() -> VehicleWidgetSnapshot? {
        guard let data = UserDefaults(suiteName: VehicleWidgetSnapshot.appGroup)?
            .data(forKey: VehicleWidgetSnapshot.storageKey) else { return nil }
        return try? JSONDecoder().decode(VehicleWidgetSnapshot.self, from: data)
    }

    static func clear() {
        UserDefaults(suiteName: VehicleWidgetSnapshot.appGroup)?
            .removeObject(forKey: VehicleWidgetSnapshot.storageKey)
    }
}
