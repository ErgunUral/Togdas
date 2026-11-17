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

/// Kilit onayı metinleri. Dürüstlük kuralı: araç **zaten** hedef durumdaysa
/// "kilitlendi" denmez; komut onaylandı ama durumun değişmediği söylenir.
/// (Sahada gözlenen vaka: araç kendi kendine kilitlenmişken gelen kilitle
/// komutu ack alıyor, kullanıcı "kilitlemedi" sanıyordu.)
enum LockAckNarration {
    struct Texts: Equatable {
        let event: String
        let detail: String
        let note: String?
    }

    static func texts(targetLocked: Bool, wasAlreadyInTarget: Bool) -> Texts {
        if wasAlreadyInTarget {
            return Texts(
                event: targetLocked
                    ? "Araç zaten kilitliydi; komut onaylandı."
                    : "Araç zaten kilit açıktı; komut onaylandı.",
                detail: "Araç zaten hedef durumdaydı; durum değişmedi.",
                note: targetLocked ? "araç zaten kilitliydi" : "araç zaten açıktı"
            )
        }
        return Texts(
            event: "Araç komutu onayladı; kilit durumu hedef değerle eşleşiyor.",
            detail: "Kilit durumu telemetriyle doğrulandı.",
            note: nil
        )
    }
}

/// Saatten gelen komut isteğinin yaşam süresi.
///
/// - Canlı kanal (`sendMessage`): iPhone uygulaması ön planda; yanıt anında
///   gelir, ömür kısa tutulur (15 sn).
/// - Kuyruklu kanal (`transferUserInfo`): iPhone arka plandayken istek tek
///   kez bırakılır; iletim birkaç saniye gecikebilir, bu yüzden ömür 30 sn.
///   Kuyruk **retry değildir**: süresi dolan istek araç tarafında dürüstçe
///   reddedilir, komut "eski niyet"le çalışmaz.
enum WatchCommandPolicy {
    static let directLifetime: TimeInterval = 15
    static let queuedLifetime: TimeInterval = 30
    static let maxLifetime: TimeInterval = queuedLifetime
}
