import Foundation

/// GATT RSSI örneklerinden **kalibrasyon aralığı önerisi** üretir.
///
/// Amaç: kullanıcı manuel "yakında ölç / uzakta ölç" düğmelerine basmadan önce,
/// diyital anahtar bağlı ve RSSI akışı sürerken dolaşım sırasında
/// kararlı yakın/uzak kümeleri gözlemleyip uygun aralığı önermek.
///
/// Kümeler: son `requiredRuns` örnek `clusterTolerance` (±dBm) içindeyse
/// kararlı küme sayılır; değer tekil ölçümde değil, kararlı ortalama dalga
/// üstünden değerlendirilir.
///
/// Kasıtlı sınırlar:
/// - Bu tip öneride kalmaz: kalibrasyonu **kendisi yazmaz**, otomasyonu
///   **kendisi etkinleştirmez**; dönüşte yalnız `nearSample`/`farSample`
///   çıkar. Onay `DashboardView` kalibrasyon akışından geçer.
/// - Tek öneri: yeni öneri için `reset()` gerektirir; bildirim spam'i engellenir.
/// - "Uygun aralık" tanımı `ProximityCalibration.minimumSeparation`
///   (≥14 dBm) ile aynıdır; mesafe (metre) iddiası içermez.
struct ProximityAutoCalibrationSuggester: Equatable {
    struct Suggestion: Equatable {
        let nearSample: Int
        let farSample: Int

        var separation: Int { nearSample - farSample }
        var isValid: Bool { nearSample - farSample >= ProximityCalibration.minimumSeparation }
    }

    /// Kararlı küme için gereken ardışık örnek sayısı (2 sn poll → ~10 sn).
    static let requiredRuns = 5
    /// Aynı kümede sayılacak maksimum sapma (±dBm).
    static let clusterTolerance = 2

    struct Candidate: Equatable {
        let mean: Int
        let sampleCount: Int
    }

    private var run: [Int] = []
    /// Gözlenen en güçlü (yakın) kararlı küme ortalaması.
    private(set) var strongCandidate: Candidate?
    /// Gözlenen en zayıf (uzak) kararlı küme ortalaması.
    private(set) var weakCandidate: Candidate?
    private var issued = false

    mutating func feed(_ rssi: Int) -> Suggestion? {
        maintainRun(rssi: rssi)

        if run.count >= Self.requiredRuns {
            let candidate = Self.mean(run)
            updateStrongAndWeak(from: candidate)
        }

        guard !issued,
              let strong = strongCandidate,
              let weak = weakCandidate,
              strong.mean - weak.mean >= ProximityCalibration.minimumSeparation else {
            return nil
        }
        issued = true
        return Suggestion(nearSample: strong.mean, farSample: weak.mean)
    }

    /// Yeni bir gözlem turu: kom/oran kayıtlı kalibrasyon etkisinin hemen
    /// akabinde yeniden öneri üretebilmek için sıfırlanır.
    mutating func reset() {
        run = []
        strongCandidate = nil
        weakCandidate = nil
        issued = false
    }

    private mutating func maintainRun(rssi: Int) {
        if run.isEmpty {
            run = [rssi]
            return
        }
        let currentMean = Self.mean(run)
        if abs(rssi - currentMean) <= Self.clusterTolerance {
            run.append(rssi)
        } else {
            run = [rssi]
        }
    }

    private mutating func updateStrongAndWeak(from mean: Int) {
        if strongCandidate == nil {
            // İlk kararlı kümenin yönü tek başına belirsizdir; ikinci küme
            // yönü belirler (yukarı ~ yakın, aşağı ~ uzak).
            strongCandidate = Candidate(mean: mean, sampleCount: run.count)
            return
        }
        if let currentStrong = strongCandidate, mean > currentStrong.mean {
            strongCandidate = Candidate(mean: mean, sampleCount: run.count)
            return
        }
        if let currentStrong = strongCandidate,
           mean < currentStrong.mean,
           mean < (weakCandidate?.mean ?? Int.max) {
            weakCandidate = Candidate(mean: mean, sampleCount: run.count)
        }
    }

    private static func mean(_ values: [Int]) -> Int {
        values.isEmpty ? 0 : Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }
}
