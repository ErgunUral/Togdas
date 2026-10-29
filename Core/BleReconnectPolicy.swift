import Foundation

/// BLE bağlantısı koptuğunda ne yapılacağına karar veren saf kural kümesi.
///
/// `BleLinkCoordinator` içindeki karar mantığı buradan okunur; böylece
/// görev/Combine karmaşası olmadan birim test edilebilir. Politika yalnızca
/// *karar* üretir: durum yazma, kayıt ve `ble.start` çağrısı koordinatörde kalır.
struct BleReconnectPolicy {
    static let maxAttempts = 8
    static let pairingMaxAttempts = 30
    static let pairingInterval: TimeInterval = 20
    static let stableInterval: TimeInterval = 60
    static let foregroundCooldown: TimeInterval = 3
    static let maxDelay: TimeInterval = 15

    /// Kopma bildiriminde koordinatörün uygulayacağı tek eylem.
    enum Action: Equatable {
        /// İlk "bağlı değil" yayını: kopma sayılmaz.
        case ignore
        /// Onarım gerekiyor; yalnızca durum metni gösterilir.
        case repair(String)
        /// Araç anahtarı yok; seyrek eşleştirme denemesi planlanır.
        case pairingWait
        /// Eşleştirme denemeleri tükendi; kullanıcıya gerekçe gösterilir.
        case pairingExhausted(String)
        /// Kullanıcıya yalnızca durum metni gösterilir, bağlanma denenmez.
        case showStatus(String)
        /// Radyo kapalı: sayaç tüketilmez, radyo açılınca yeniden bağlanılır.
        case waitForRadio(String)
        /// Geri çekilmeli yeniden bağlanma planlanır.
        case reconnect(delay: TimeInterval, attempt: Int)
        /// Deneme sınırı aşıldı.
        case stopped(String)
    }

    /// 1,5 · 2^(n-1) sn; en fazla 15 sn.
    static func backoffDelay(attempt: Int) -> TimeInterval {
        guard attempt > 0 else { return 0 }
        return min(pow(2.0, Double(attempt - 1)) * 1.5, maxDelay)
    }

    static func action(
        connectedBefore: Bool,
        awaitingConnection: Bool,
        needsRepair: Bool,
        repairStatus: String,
        pairingRequired: Bool,
        autoConnectEnabled: Bool,
        radioAvailable: Bool,
        radioFailureStatus: String?,
        attempts: Int,
        pairingAttempts: Int
    ) -> Action {
        // Combine aboneliği mevcut değeri hemen yayınlar; ilk kopma sayılmaz.
        guard connectedBefore || awaitingConnection else { return .ignore }
        if needsRepair { return .repair(repairStatus) }
        if pairingRequired {
            guard pairingAttempts < pairingMaxAttempts else {
                return .pairingExhausted(
                    "Araç eşleştirmesi tamamlanmadı. Araç ekranından eşleştirmeyi başlatıp yeniden deneyin."
                )
            }
            return .pairingWait
        }
        guard autoConnectEnabled else {
            return connectedBefore ? .ignore : .showStatus("")
        }
        guard radioAvailable else {
            return .waitForRadio(radioFailureStatus ?? "Bluetooth kapalı")
        }
        guard attempts < maxAttempts else {
            return .stopped(
                "Otomatik yeniden bağlanma durdu (\(maxAttempts) deneme). Araç yakınında Bluetooth'u kapatıp açıp yeniden deneyin."
            )
        }
        let attempt = attempts + 1
        return .reconnect(delay: backoffDelay(attempt: attempt), attempt: attempt)
    }

    /// Uygulama öne geldiğinde bekleyen geri çekilme atlanmalı mı?
    static func shouldRetryOnForeground(
        autoConnectEnabled: Bool,
        radioAvailable: Bool,
        stateDisconnectedOrFailed: Bool,
        sinceLastStart: TimeInterval?,
        hasPendingTimerOrDisconnected: Bool
    ) -> Bool {
        guard autoConnectEnabled, radioAvailable, stateDisconnectedOrFailed else { return false }
        if let sinceLastStart, sinceLastStart < foregroundCooldown { return false }
        return hasPendingTimerOrDisconnected
    }
}
