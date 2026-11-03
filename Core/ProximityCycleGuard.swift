import Foundation

/// Uzak↔geri-yaklaşma döngüsü guard'ı: Android `1.0.24.57` oto kilit akışıyla
/// eşleşen, test edilebilir karar çekirdeği.
///
/// Neden gerekli: iOS'ta yakınlık geçişi (`ProximityGate`) yalnız
/// yakın/uzak eşiklerini üretiyor; açma kararı her `approached` sinyalinde
/// tekrar verilebiliyordu. Android akışta üç koruma var:
/// - açma **tek biletlir**: bir yaklaşmada yalnız bir açma komutu;
///   yeni açma için teyitli uzaklaşma + yeni yaklaşma gerekir,
/// - **30 sn belirsizlik guard'ı**: geçersiz/eski ölçüm ya da belirsiz geçiş
///   bileti iptal eder; bekleme bitse bile *yeni* bir yaklaşma gelmeden
///   ters açma yapılmaz,
/// - guard sadece karar verir; komutun gerçek sonucu imzalı telemetriyle
///   doğrulanmaya devam eder.
///
/// Bu tip komut göndermez, ağ çağırmaz; `ProximityAction` döndürür.
struct ProximityCycleGuard: Equatable {
    enum Action: Equatable {
        case sendUnlock
        case deny(reason: String)
    }

    /// Android: "belirsiz geçiş koruması · 30sn".
    static let ambiguityHoldInterval: TimeInterval = 30

    /// Bu döngüde teyitli uzaklaşma görüldü mü? (yeni yaklaşma kanıtı için ön koşul)
    private(set) var farSeenInCycle = false
    /// Tek kullanımlık açma bileti.
    private(set) var unlockTicket = false
    /// Belirsizlik sonrası 30 sn bekleme sınırı.
    private(set) var holdUntil: Date?

    mutating func noteDepartureConfirmed(now: Date) {
        farSeenInCycle = true
        unlockTicket = false
        holdUntil = nil
    }

    /// Eski/invalid ölçüm veya belirsiz geçiş; açma gönderimi başarısızsa da
    /// çağrılır ("girişim kullanıldı; sonuç bekleniyor").
    mutating func noteAmbiguity(now: Date) {
        unlockTicket = false
        holdUntil = now.addingTimeInterval(Self.ambiguityHoldInterval)
    }

    /// Bilet kullanıldı: yeni açma için teyitli uzaklaşma + yeni yaklaşma şart.
    mutating func noteUnlockIssued() {
        unlockTicket = false
        farSeenInCycle = false
    }

    /// Gate bir `approached` teyidi verdi; açma kararını ver.
    mutating func decideApproach(now: Date) -> Action {
        if let holdUntil, now < holdUntil {
            return .deny(reason: "Belirsiz geçiş guard'ı 30 sn açmayı bekletiyor.")
        }
        guard farSeenInCycle else {
            return .deny(reason: "Yeni uzak-geri yaklaşma kanıtı gerekli; açma gönderilmedi.")
        }
        guard !unlockTicket else {
            return .deny(reason: "Bu yaklaşmada açma zaten gönderildi.")
        }
        unlockTicket = true
        return .sendUnlock
    }
}
