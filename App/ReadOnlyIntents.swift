import AppIntents
import Foundation

/// Salt okunur Siri/Shortcuts niyetleri.
///
/// Bu niyetler araç komutu göndermez, BLE bağlantısı kurmaz ve kilit/açma
/// akışını tetiklemez. Yalnız uygulamanın en son yayımladığı widget özetini ve
/// bu ayın önbelleğe alınmış gerçek şarj harcamasını okur; veri yoksa tahmin
/// üretmez. Yazma niyetleri `CarShortcuts.swift` içindedir.
struct VehicleStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Araç durumu"
    static var description = IntentDescription(
        "Pil, menzil ve kilit durumunu salt okunur gösterir; hiçbir komut göndermez."
    )
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snapshot = VehicleWidgetSnapshotStore.load() else {
            return .result(dialog: "Araç verisi yok. Toqdas'ı açıp bir kez yenileyin.")
        }

        let age = Date().timeIntervalSince(snapshot.savedAt)
        let freshness: String
        if age < 120 {
            freshness = "Az önce güncellendi."
        } else if age < 3_600 {
            freshness = "\(Int(age / 60)) dakika önce güncellendi."
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "tr_TR")
            formatter.dateFormat = "d MMM HH:mm"
            freshness = "Son güncelleme \(formatter.string(from: snapshot.savedAt)); güncel olmayabilir."
        }

        return .result(
            dialog: "\(snapshot.vehicleName): pil \(snapshot.displayBattery), menzil \(snapshot.displayRange), kilit \(snapshot.displayLock). \(freshness) Bu bilgi yalnız okuma içindir."
        )
    }
}

struct ChargingSpendIntent: AppIntent {
    static var title: LocalizedStringResource = "Bu ay şarj harcamam"
    static var description = IntentDescription(
        "Bu ayın gerçek şarj harcamasını ve varsa bütçe durumunu salt okunur söyler."
    )
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let vin = GaragePreferences().selectedVin else {
            return .result(dialog: "Önce Toqdas'ta bir araç seçin.")
        }
        let store = ChargingSpendStore(vin: vin)
        guard let snapshot = store.snapshot() else {
            return .result(
                dialog: "Bu ay için kayıtlı şarj harcaması yok. Seyahatname'de bu ayın şarjlarını açtığınızda güncellenir."
            )
        }

        let budget = store.budget()
        let limitText: String
        if budget.limitTRY > 0 {
            limitText = " Aylık bütçe \(ChargingBudget.money(budget.limitTRY)); \(budget.percentText) kullanıldı, \(ChargingBudget.money(budget.remainingTRY)) kaldı."
        } else {
            limitText = " Aylık bütçe belirlenmedi."
        }

        return .result(
            dialog: "Bu ay \(ChargingBudget.money(snapshot.amountTRY)) şarj harcaması var.\(limitText) Bu bilgi yalnız okuma içindir."
        )
    }
}
