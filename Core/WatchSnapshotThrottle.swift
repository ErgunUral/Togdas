import Foundation

/// Saate gönderilen snapshot darboğazı. WCSession application context her
/// yazım saat tarafında uyanma/widget zaman çizelgesi tazelenmesi yaratır;
/// değer değişmedikçe gönderim yapılmaz. Gösterim değerleri değişse bile
/// minimum aralık (30 sn) korunur; **önemli** alanlar (bağlantı durumu,
/// komut sonucu) değişirse darboğaza takılmadan hemen gider.
///
/// Parmak izleri çağıran taraf tarafından üretilir (WatchSnapshot
/// extension'ı); bu tip yalnızca kararı verir ve saf/test edilebilir kalır.
struct WatchSnapshotThrottle {
    static let minimumInterval: TimeInterval = 30

    private(set) var lastFingerprint: String?
    private(set) var lastImportantFingerprint: String?
    private(set) var lastSentAt: Date?

    /// İlk çağrı her zaman gönderir.
    mutating func shouldSend(now: Date, fingerprint: String, importantFingerprint: String) -> Bool {
        if importantFingerprint != lastImportantFingerprint {
            lastImportantFingerprint = importantFingerprint
            lastFingerprint = fingerprint
            lastSentAt = now
            return true
        }
        guard fingerprint != lastFingerprint else { return false }
        if let lastSentAt, now.timeIntervalSince(lastSentAt) < Self.minimumInterval { return false }
        lastFingerprint = fingerprint
        lastSentAt = now
        return true
    }
}
