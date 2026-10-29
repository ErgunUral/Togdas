import Foundation

enum ProximityAutoOffPolicy {
    static let allowedMinutes = 1...1440

    static func deadline(startedAt: Date, durationMinutes: Int) -> Date? {
        guard allowedMinutes.contains(durationMinutes) else { return nil }
        return startedAt.addingTimeInterval(Double(durationMinutes) * 60)
    }

    static func isExpired(_ deadline: Date, now: Date) -> Bool {
        now >= deadline
    }
}

enum ProximityProfile: String, CaseIterable, Identifiable, Hashable {
    case balanced, fast, aggressive, predictive, kalman

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced: return "Dengeli"
        case .fast: return "Hızlı"
        case .aggressive: return "Agresif"
        case .predictive: return "Öngörülü"
        case .kalman: return "Kalman"
        }
    }

    var explanation: String {
        switch self {
        case .balanced: return "İki kararlı ölçüm; önerilen başlangıç profili."
        case .fast: return "Tek ölçümle tepki; sinyal dalgalanmasında yanlış tetiklenebilir."
        case .aggressive: return "Tek ölçüm ve dar eşik; en hızlı, yanlış tetikleme olasılığı daha yüksek."
        case .predictive: return "Sinyal yönünü hesaba katar; uzaklaşma/yaklaşmayı biraz erken algılayabilir."
        case .kalman: return "RSSI gürültüsünü filtreler; tepki daha yumuşak olabilir."
        }
    }

    var requiredSamples: Int {
        switch self {
        case .fast, .aggressive: return 1
        case .balanced, .predictive, .kalman: return 2
        }
    }

    var thresholdMargin: Int {
        switch self {
        case .balanced, .predictive, .kalman: return 3
        case .fast: return 2
        case .aggressive: return 1
        }
    }

    /// Faster polling uses more BLE reads and therefore more battery.
    var pollInterval: TimeInterval {
        switch self {
        case .fast, .aggressive: return 1
        case .balanced, .predictive, .kalman: return 2
        }
    }
}

enum ProximityRSSIPolicy {
    /// Rejects delayed/out-of-order samples using the selected GATT polling cadence.
    static func isFresh(sampledAt: Date, now: Date, profile: ProximityProfile) -> Bool {
        let age = now.timeIntervalSince(sampledAt)
        return age >= 0 && age <= max(1.5, profile.pollInterval * 1.5)
    }
}

/// RSSI ölçümlerinden araç başı ve araçtan ayrılma eşikleri türetir.
struct ProximityCalibration: Equatable {
    let nearSample: Int
    let farSample: Int

    static let minimumSeparation = 14
    var isValid: Bool {
        nearSample > farSample && nearSample - farSample >= Self.minimumSeparation
    }

    var nearThreshold: Int? {
        thresholdMargin(3, near: true)
    }

    var farThreshold: Int? {
        thresholdMargin(3, near: false)
    }

    func nearThreshold(margin: Int) -> Int? {
        thresholdMargin(margin, near: true)
    }

    func farThreshold(margin: Int) -> Int? {
        thresholdMargin(margin, near: false)
    }

    private func thresholdMargin(_ margin: Int, near: Bool) -> Int? {
        guard isValid else { return nil }
        let midpoint = Double(nearSample + farSample) / 2
        return near
            ? Int(floor(midpoint + Double(margin)))
            : Int(ceil(midpoint - Double(margin)))
    }
}

/// İki ardışık RSSI örneğiyle yakın/uzak geçişini filtreler.
struct ProximityGate: Equatable {
    enum Presence: Equatable { case unknown, near, far }
    enum Transition: Equatable { case approached, departed }

    let calibration: ProximityCalibration
    let profile: ProximityProfile
    private(set) var presence: Presence = .unknown
    private var nearCount = 0
    private var farCount = 0
    private var previousRSSI: Int?
    private var kalmanEstimate: Double?
    private var kalmanVariance = 8.0
    private var requiresFarBeforeApproach = false

    var isAwaitingFarBaseline: Bool { requiresFarBeforeApproach }

    init(calibration: ProximityCalibration, profile: ProximityProfile = .balanced) {
        self.calibration = calibration
        self.profile = profile
    }

    mutating func update(rssi: Int) -> Transition? {
        guard calibration.isValid,
              let nearThreshold = calibration.nearThreshold(margin: profile.thresholdMargin),
              let farThreshold = calibration.farThreshold(margin: profile.thresholdMargin) else { return nil }

        let sample = filteredRSSI(rssi)

        if sample >= nearThreshold {
            farCount = 0
            guard !requiresFarBeforeApproach else {
                nearCount = 0
                return nil
            }
            nearCount += 1
            guard nearCount >= profile.requiredSamples, presence != .near else { return nil }
            presence = .near
            return .approached
        }

        if sample <= farThreshold {
            farCount += 1
            nearCount = 0
            guard farCount >= profile.requiredSamples, presence != .far else { return nil }
            let previous = presence
            presence = .far
            if requiresFarBeforeApproach {
                requiresFarBeforeApproach = false
                return nil
            }
            // Uygulama etkinleştirildiğinde ilk ölçüm uzaksa durum belirlenir,
            // ancak ayrılma eylemi yalnızca yakında görüldükten sonra tetiklenir.
            return previous == .near ? .departed : nil
        }

        nearCount = 0
        farCount = 0
        return nil
    }

    private mutating func filteredRSSI(_ value: Int) -> Int {
        defer { previousRSSI = value }
        switch profile {
        case .balanced, .fast, .aggressive:
            return value
        case .predictive:
            guard let previousRSSI else { return value }
            let delta = max(-6, min(6, value - previousRSSI))
            return value + Int((Double(delta) * 0.5).rounded())
        case .kalman:
            guard let estimate = kalmanEstimate else {
                kalmanEstimate = Double(value)
                return value
            }
            kalmanVariance += 2.0
            let gain = kalmanVariance / (kalmanVariance + 8.0)
            let updated = estimate + gain * (Double(value) - estimate)
            kalmanVariance *= (1 - gain)
            kalmanEstimate = updated
            return Int(updated.rounded())
        }
    }

    mutating func reset() {
        presence = .unknown
        nearCount = 0
        farCount = 0
        previousRSSI = nil
        kalmanEstimate = nil
        kalmanVariance = 8.0
        requiresFarBeforeApproach = false
    }

    /// New authenticated BLE session must establish a fresh far baseline before
    /// an approach can trigger automatic unlocking.
    mutating func requireFreshCycle() {
        reset()
        requiresFarBeforeApproach = true
    }
}
