import Foundation

/// Komut kapısının tipli reddetme nedeni. UI ve tanı katmanı metin ayrıştırmak
/// yerine bu değeri kullanabilir.
enum BLECommandRejection: Equatable, Sendable {
    case linkNotReady
    case telemetryMissing
    case telemetryStale
    case lockStateUnknown

    var message: String {
        switch self {
        case .linkNotReady:
            return "Dijital anahtar hazır değil; komut gönderilmedi."
        case .telemetryMissing:
            return "İmzalı araç durumu yok; komut gönderilmedi."
        case .telemetryStale:
            return "Araç durumu 15 saniyeden eski; komut gönderilmedi."
        case .lockStateUnknown:
            return "Kilit durumu bilinmiyor; kilit komutu gönderilmedi."
        }
    }

    var diagnosticCode: String {
        switch self {
        case .linkNotReady: return "link_not_ready"
        case .telemetryMissing: return "telemetry_missing"
        case .telemetryStale: return "telemetry_stale"
        case .lockStateUnknown: return "lock_state_unknown"
        }
    }
}

/// Central safety gate for every actuator command, regardless of UI origin.
enum BLECommandPolicy {
    static let telemetryFreshness: TimeInterval = 15

    static func rejection(
        code: UInt8,
        linkReady: Bool,
        telemetry: BleTelemetry?,
        now: Date = Date()
    ) -> BLECommandRejection? {
        guard linkReady else { return .linkNotReady }
        guard let telemetry else { return .telemetryMissing }
        let age = now.timeIntervalSince(telemetry.receivedAt)
        guard age >= 0, age < telemetryFreshness else { return .telemetryStale }
        if (code == 1 || code == 2), telemetry.isLocked == nil { return .lockStateUnknown }
        return nil
    }

    static func rejectionReason(
        code: UInt8,
        linkReady: Bool,
        telemetry: BleTelemetry?,
        now: Date = Date()
    ) -> String? {
        rejection(code: code, linkReady: linkReady, telemetry: telemetry, now: now)?.message
    }
}
