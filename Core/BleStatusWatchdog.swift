import Foundation

/// Bağlantı sonrası ilk telemetri bekleme gözcüsü (Android .57 `j4` paritesi).
///
/// İki etiket üretir:
/// - `stale_telemetry_reconnect`: telemetri geldi ama yaşı 15 sn'yi aştı —
///   veri bayat; yeniden bağlanma gerekçesi.
/// - `first_status_timeout`: bağlantı kuruldu, ilk durum 15 sn içinde gelmedi.
///
/// Etiketler **yalnız gösterim/günlük amaçlıdır**: davranış kararı
/// `BleReconnectPolicy`'de kalır; gözcü kendiliğinden bağlantı kapatmaz.
/// Aynı bekleme oturumu (`session`) değişmedikçe başlangıç zamanı korunur;
/// oturum değişince sayaçlar sıfırlanır (Android `f804a != j` dalı).
struct BleStatusWatchdog {
    /// Telemetri bu yaştan bayat sayılır (Android 15000 ms).
    static let staleThreshold: TimeInterval = 15
    /// İlk durum bu sürede gelmezse zaman aşımı (Android 15000 ms).
    static let firstStatusTimeout: TimeInterval = 15
    /// Android `b()` eşiği: üçüncü denemede `true` döner.
    static let attemptLimit = 3

    private var session: Int = -1
    private var startedAt: Date = .distantPast
    private var attempts = 0

    init() {}

    mutating func reset() {
        session = -1
        startedAt = .distantPast
        attempts = 0
    }

    /// Bekleme oturumu başlatır; aynı oturum yeniden çağrılırsa sayaçlar korunur.
    mutating func begin(session newSession: Int, now: Date = Date()) {
        guard session != newSession else { return }
        session = newSession
        startedAt = now
        attempts = 0
    }

    /// Android `b()`: her çağrı deneme sayacını artırır; eşik dolunca `true`.
    mutating func recordAttempt() -> Bool {
        attempts += 1
        return attempts >= Self.attemptLimit
    }

    /// Etiket: telemetri varsa yaş eşiği, yoksa ilk durum zaman aşımı.
    /// Etiket yoksa boş metin döner (Android davranışı).
    mutating func reason(
        session newSession: Int,
        now: Date = Date(),
        telemetryAge: TimeInterval?
    ) -> String {
        if session != newSession {
            session = newSession
            startedAt = now
            attempts = 0
        }
        if let telemetryAge {
            return telemetryAge > Self.staleThreshold
                ? "stale_telemetry_reconnect" : ""
        }
        return now.timeIntervalSince(startedAt) >= Self.firstStatusTimeout
            ? "first_status_timeout" : ""
    }
}
