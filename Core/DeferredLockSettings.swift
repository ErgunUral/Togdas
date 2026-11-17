import Foundation

/// Uzaklaşınca kilitleme biletinin VIN bazlı kalıcılığı.
///
/// Neden: bilet bellekte tutulurken uygulama askıya alınır/sonlandırılırsa
/// sessizce kayboluyordu; kullanıcı "bilet kurdum" sanıp kilitlenmemiş araçla
/// kalıyordu. Yalnız son tarih saklanır; karar `DeferredLockTicket.decide`'da
/// kalır (burada eşik/kural yok).
///
/// Kasıtlı sınırlar:
/// - VIN yalnız anahtarda geçer, metinlere/loglara yazılmaz.
/// - Süresi geçmiş kayıt okunurken temizlenmez; çağıran karar verir.
struct DeferredLockSettings {
    let store: KeyValueStore

    static func deadlineKey(_ vin: String) -> String { "toqdas.deferredLock.deadline.\(vin)" }

    func deadline(vin: String) -> Date? {
        store.object(forKey: Self.deadlineKey(vin)) as? Date
    }

    func setDeadline(_ deadline: Date?, vin: String) {
        store.set(deadline, forKey: Self.deadlineKey(vin))
    }

    /// Saklanan son tarihi bilete çevirir; süresi dolmuşsa nil döner ve
    /// kaydı temizler.
    func restoredTicket(vin: String, now: Date = Date()) -> DeferredLockTicket? {
        guard let saved = deadline(vin: vin) else { return nil }
        guard saved > now else {
            setDeadline(nil, vin: vin)
            return nil
        }
        let armedAt = saved.addingTimeInterval(-DeferredLockTicket.duration)
        return DeferredLockTicket(armedAt: armedAt)
    }
}
