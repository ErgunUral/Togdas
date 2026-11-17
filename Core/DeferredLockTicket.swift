import Foundation

/// Uzaklaşınca kilitleme bileti.
///
/// Neden: araç, dijital anahtar (telefon) güçlü sinyaldeyken kilit komutunu
/// onaylıyor (ack) ama uygulamıyor. Ölçüm (2026-11-17, araç başı): yakın
/// RSSI −57…−84 aralığında 7/7 kilit denemesi reddedildi; uzak −88…−97
/// aralığında 6/6 uygulandı ve imzalı telemetriyle doğrulandı.
///
/// Bilet, kullanıcı kilidi araç yanında verdiğinde tek komutu **sinyal
/// zayıfladığı an** göndermek için kullanılır. Tip saftır: karar üretir,
/// I/O yapmaz; durum yazımı çağıranda kalır.
struct DeferredLockTicket: Equatable {
    /// Biletin üst sınırı: bu süre içinde sinyal zayıflamazsa komut gitmez.
    static let duration: TimeInterval = 600
    /// Telemetri yaşı sınırı: eski kilit durumuna göre komut gönderilmez.
    static let telemetryFreshness: TimeInterval = 15

    let armedAt: Date
    let deadline: Date

    init(armedAt: Date = Date(), duration: TimeInterval = DeferredLockTicket.duration) {
        self.armedAt = armedAt
        self.deadline = armedAt.addingTimeInterval(duration)
    }

    enum Decision: Equatable {
        case send
        case wait
        /// İptal gerekçesi kullanıcıya gösterilecek metindir.
        case cancel(String)
    }

    /// Örnekler biletin ömrü boyunca beslenir; `.send` en fazla bir kez
    /// üretilmelidir (çağıran biletliği temizler).
    func decide(
        rssi: Int?,
        now: Date = Date(),
        isLocked: Bool?,
        telemetryAge: TimeInterval?,
        recentLock: Bool
    ) -> Decision {
        if now >= deadline {
            return .cancel("Bilet süresi doldu; kilitleme gönderilmedi.")
        }
        if isLocked == true {
            return .cancel("Araç zaten kilitli; bilet kapandı.")
        }
        if recentLock {
            return .cancel("Kilitleme yeni gönderildi; çift komut engellendi.")
        }
        guard let rssi, rssi <= BleReconnectPolicy.weakSignalThreshold else {
            return .wait
        }
        guard let telemetryAge, telemetryAge < Self.telemetryFreshness else {
            return .wait
        }
        guard isLocked == false else { return .wait }
        return .send
    }
}
