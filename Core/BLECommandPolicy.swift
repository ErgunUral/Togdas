import Foundation

/// Central safety gate for every actuator command, regardless of UI origin.
enum BLECommandPolicy {
    static let telemetryFreshness: TimeInterval = 15

    static func rejectionReason(
        code: UInt8,
        linkReady: Bool,
        telemetry: BleTelemetry?,
        now: Date = Date()
    ) -> String? {
        guard linkReady else { return "Dijital anahtar hazır değil; komut gönderilmedi." }
        guard let telemetry else { return "İmzalı araç durumu yok; komut gönderilmedi." }
        let age = now.timeIntervalSince(telemetry.receivedAt)
        guard age >= 0, age < telemetryFreshness else {
            return "Araç durumu 15 saniyeden eski; komut gönderilmedi."
        }
        if (code == 1 || code == 2), telemetry.isLocked == nil {
            return "Kilit durumu bilinmiyor; kilit komutu gönderilmedi."
        }
        return nil
    }
}
