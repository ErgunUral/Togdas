import Foundation

/// Lastik basıncı değerlendirme politikası.
///
/// Eşikler kullanıcı tarafından ayarlanabilir (varsayılan düşük eşik 30 PSI).
/// Eksik ölçüm "0 PSI" olarak yorumlanmaz; uyarı üretmez, arayüzde "—" gösterilir.
struct TirePressurePolicy: Equatable {
    /// Bu değerin altındaki basınçlar uyarı üretir (PSI).
    var lowThresholdPSI: Double
    /// Bu değerin altındaki basınçlar kritik kabul edilir (PSI).
    var criticalThresholdPSI: Double

    static let minimumAllowedThreshold = 20.0
    static let maximumAllowedThreshold = 40.0

    static let `default` = TirePressurePolicy(lowThresholdPSI: 30, criticalThresholdPSI: 26)

    init(lowThresholdPSI: Double, criticalThresholdPSI: Double) {
        let clamped = min(max(lowThresholdPSI, Self.minimumAllowedThreshold), Self.maximumAllowedThreshold)
        self.lowThresholdPSI = clamped
        self.criticalThresholdPSI = min(criticalThresholdPSI, clamped - 1)
    }

    enum Severity: Equatable {
        case critical
        case low
    }

    struct Alert: Equatable {
        let position: TirePosition
        let pressurePSI: Double
        let severity: Severity
    }

    /// Ölçümü olan ve eşiğin altında kalan lastikler.
    func alerts(for tires: [TireReading]) -> [Alert] {
        tires.compactMap { tire in
            guard let psi = tire.pressurePSI, psi.isFinite, psi > 0 else { return nil }
            guard psi < lowThresholdPSI else { return nil }
            return Alert(position: tire.position, pressurePSI: psi,
                         severity: psi < criticalThresholdPSI ? .critical : .low)
        }
    }

    func severity(for tire: TireReading) -> Severity? {
        alerts(for: [tire]).first?.severity
    }

    var summaryText: String {
        "Uyarı eşiği \(Int(lowThresholdPSI.rounded())) PSI, kritik \(Int(criticalThresholdPSI.rounded())) PSI."
    }
}

/// Eşiklerin kalıcı saklandığı yer (global — VIN'den bağımsız).
final class TirePressureSettings {
    private let defaults: UserDefaults
    private static let lowKey = "toqdas.tire.lowThreshold"
    private static let criticalKey = "toqdas.tire.criticalThreshold"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var policy: TirePressurePolicy {
        get {
            let low = defaults.object(forKey: Self.lowKey) as? Double
                ?? TirePressurePolicy.default.lowThresholdPSI
            let critical = defaults.object(forKey: Self.criticalKey) as? Double
                ?? TirePressurePolicy.default.criticalThresholdPSI
            return TirePressurePolicy(lowThresholdPSI: low, criticalThresholdPSI: critical)
        }
        set {
            defaults.set(newValue.lowThresholdPSI, forKey: Self.lowKey)
            defaults.set(newValue.criticalThresholdPSI, forKey: Self.criticalKey)
        }
    }
}
