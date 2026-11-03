import Foundation

/// 12 V akü (auxiliary) yüzdesinden **sağlık uyarısı** üretir.
///
/// Kural: araç durma halinde 12 V akü %25'in altındaysa kritik,
/// %40'ın altındaysa uyarı sayılır. Eşikler sabittir; araca göre
/// öğrenme/uyarlama yapılmaz (tutarlılık invariant'ı).
///
/// Kasıtlı sınırlar:
/// - Eksik/geçersiz telemetri (nil, sonsuz, 0–100 dışı) değerlendirilmez →
///   `nil` döner; bu, ekranda "—" olarak "bilgi yok" rutininden ayrı
///   tutulur. "Bilgi yok" asla uyarıya dönüştürülmez.
/// - Gerçek 0 değeri bilgidir (akü ölçümü sıfır olabilir); `nil` ile
///   karıştırılmaz ve kritik uyarı üretir.
/// - Yüzdeler tamsayıya yuvarlanarak gösterilir; metreye/menzile çevrim
///   yapılmaz.
struct AuxiliaryBatteryAssessment: Equatable {
    enum Severity: Equatable {
        case critical
        case warning
    }

    let percent: Int
    let severity: Severity

    var isCritical: Bool { severity == .critical }
}

enum AuxiliaryBatteryPolicy {
    /// Bu değerin **altında veya eşit**se kritik uyarı.
    static let criticalPercent = 25
    /// Bu değerin altında veya eşitse (kritik değilse) uyarı.
    static let warningPercent = 40

    static func assess(_ percent: Double?) -> AuxiliaryBatteryAssessment? {
        guard let percent, percent.isFinite, percent >= 0, percent <= 100 else { return nil }
        let rounded = Int(percent.rounded())
        if rounded <= criticalPercent {
            return AuxiliaryBatteryAssessment(percent: rounded, severity: .critical)
        }
        if rounded <= warningPercent {
            return AuxiliaryBatteryAssessment(percent: rounded, severity: .warning)
        }
        return nil
    }
}
