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
