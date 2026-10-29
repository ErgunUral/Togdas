import Foundation

/// Aylık şarj bütçesi: kullanıcının belirlediği limite göre harcama durumu.
///
/// Harcama tutarı sunucudan gelen gerçek şarj toplamıdır; tahmin edilmez.
/// Bütçe yalnızca bir uyarı eşiğidir, ödeme veya otomatik kesinti değildir.
struct ChargingBudget: Equatable {
    static let maximumLimitTRY: Double = 50_000
    static let warningRatio: Double = 0.8

    let limitTRY: Double
    let spentTRY: Double

    init(limitTRY: Double, spentTRY: Double) {
        self.limitTRY = limitTRY.isFinite ? min(max(0, limitTRY), Self.maximumLimitTRY) : 0
        self.spentTRY = spentTRY.isFinite ? max(0, spentTRY) : 0
    }

    enum Status: Equatable {
        case unset
        case normal
        case nearLimit
        case exceeded
    }

    var status: Status {
        guard limitTRY > 0 else { return .unset }
        if spentTRY > limitTRY { return .exceeded }
        if spentTRY >= limitTRY * Self.warningRatio { return .nearLimit }
        return .normal
    }

    /// 0...1 arası; limit yoksa 0.
    var ratio: Double {
        guard limitTRY > 0 else { return 0 }
        return min(spentTRY / limitTRY, 1)
    }

    var remainingTRY: Double {
        max(0, limitTRY - spentTRY)
    }

    var percentText: String {
        guard limitTRY > 0 else { return "—" }
        return "\(Int((spentTRY / limitTRY * 100).rounded()))%"
    }

    var message: String {
        switch status {
        case .unset:
            return "Aylık bütçe belirlenmedi. Limit seçerek harcamayı izleyebilirsiniz."
        case .normal:
            return "Bütçenin \(percentText)'i kullanıldı; \(Self.money(remainingTRY)) kaldı."
        case .nearLimit:
            return "Bütçenin \(percentText)'i kullanıldı; \(Self.money(remainingTRY)) kaldı."
        case .exceeded:
            return "Aylık bütçe \(Self.money(spentTRY - limitTRY)) aşıldı."
        }
    }

    /// Bildirim eşiği: 100 aşıldı, 80 yaklaşıldı, 0 yok.
    var notificationThreshold: Int {
        switch status {
        case .unset, .normal: return 0
        case .nearLimit: return 80
        case .exceeded: return 100
        }
    }

    /// Türkçe biçim: binlik ayırıcı nokta, kuruş yok.
    static func money(_ value: Double) -> String {
        let rounded = Int(max(0, value).rounded())
        let digits = String(rounded)
        var grouped = ""
        for (index, character) in digits.reversed().enumerated() {
            if index > 0, index % 3 == 0 { grouped.append(".") }
            grouped.append(character)
        }
        return String(grouped.reversed()) + " ₺"
    }
}

/// Aylık şarj harcaması önbelleği ve bütçe limiti (VIN bazlı).
///
/// Sunucu harcamayı yalnız Seyahatname açıldığında verir; pano kartı bu
/// önbelleği gösterir. Ay değişince eski tutar sıfırlanır.
final class ChargingSpendStore {
    struct Snapshot: Equatable {
        let month: String
        let amountTRY: Double
        let updatedAt: Date
    }

    private let vin: String
    private let defaults: UserDefaults

    init(vin: String, defaults: UserDefaults = .standard) {
        self.vin = vin
        self.defaults = defaults
    }

    private var snapshotKey: String { "toqdas.chargingBudget.spent.\(vin)" }
    private var limitKey: String { "toqdas.chargingBudget.limit.\(vin)" }
    private var notifyKey: String { "toqdas.chargingBudget.notified.\(vin)" }

    static func monthString(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }

    func snapshot(for date: Date = Date()) -> Snapshot? {
        guard let data = defaults.data(forKey: snapshotKey),
              let decoded = try? JSONDecoder().decode([String: SnapshotValue].self, from: data),
              let stored = decoded["value"] else { return nil }
        guard stored.month == Self.monthString(date) else { return nil }
        return Snapshot(month: stored.month, amountTRY: stored.amount,
                        updatedAt: Date(timeIntervalSince1970: stored.updatedAt))
    }

    /// Gerçek şarj harcamasını kaydeder. Aynı ay için daha düşük bir değer
    /// gelirse (sayfalama/eksik yanıt) mevcut değer korunur.
    func record(amountTRY: Double, month: String = ChargingSpendStore.monthString(), at: Date = Date()) {
        guard amountTRY.isFinite, amountTRY >= 0 else { return }
        let value = SnapshotValue(month: month, amount: max(amountTRY, snapshot(for: at)?.amountTRY ?? 0),
                                  updatedAt: at.timeIntervalSince1970)
        if let data = try? JSONEncoder().encode(["value": value]) {
            defaults.set(data, forKey: snapshotKey)
        }
    }

    func monthlyLimit() -> Double {
        defaults.double(forKey: limitKey)
    }

    func setMonthlyLimit(_ value: Double) {
        let clamped = value.isFinite ? min(max(0, value), ChargingBudget.maximumLimitTRY) : 0
        defaults.set(clamped, forKey: limitKey)
    }

    func budget(for date: Date = Date()) -> ChargingBudget {
        ChargingBudget(limitTRY: monthlyLimit(), spentTRY: snapshot(for: date)?.amountTRY ?? 0)
    }

    /// Aynı ay içinde aynı eşik için yalnız bir bildirim gönderilir.
    func lastNotifiedThreshold(for month: String = ChargingSpendStore.monthString()) -> Int {
        guard let stored = defaults.dictionary(forKey: notifyKey),
              stored["month"] as? String == month else { return 0 }
        return stored["threshold"] as? Int ?? 0
    }

    func markNotified(threshold: Int, month: String = ChargingSpendStore.monthString()) {
        defaults.set(["month": month, "threshold": threshold], forKey: notifyKey)
    }

    func clear() {
        defaults.removeObject(forKey: snapshotKey)
        defaults.removeObject(forKey: limitKey)
        defaults.removeObject(forKey: notifyKey)
    }

    private struct SnapshotValue: Codable {
        let month: String
        let amount: Double
        let updatedAt: TimeInterval
    }
}
