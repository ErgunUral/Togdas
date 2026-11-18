import Foundation

/// Son **imzalı** araç durumunun cihazda saklanan özeti.
///
/// Neden gerekli: BLE oturumları kısa (ölçülen 3–60 sn) ve telefon–araç
/// sinyali zayıf; canlı veri çoğu zaman yok. Kullanıcı kilit/bagaj/sürüş
/// durumunu "hiç yok" yerine **son bilinen** olarak görmeli — ama tarih
/// yazılarak, taze gibi sunulmadan.
///
/// Dürüstlük sınırları:
/// - Her metin yaş taşır ("Kilitli · 2 saat önce"); 90 sn altı canlı sayılır.
/// - 24 saatten eski kayıt **yüklenmez** (bayat iddia taşınmaz).
/// - Kayıt yoksa `nil` döner; çağıran "Bilinmiyor" der, değer uydurulmaz.
/// - VIN yalnız yerel anahtarın içinde; görünür metne girmez.
struct VehicleStateSnapshot: Codable, Equatable {
    /// Ham imzalı değerler (1 kilitli / 2 kilit açık).
    let locked: Int?
    let trunkAjar: Int?
    let powerState: Int?
    /// İmzalı telemetrinin alındığı an (cihaz saati).
    let observedAt: Date

    /// 24 saatten eski kayıt gösterilmez.
    static let maximumAge: TimeInterval = 24 * 3600
    /// Bu sürenin altı "canlı" sayılır; yaş yazılmaz (imzalı telemetri ~30 sn).
    static let freshInterval: TimeInterval = 90

    var isLocked: Bool? {
        switch locked {
        case 1: return true
        case 2: return false
        default: return nil
        }
    }

    var isTrunkAjar: Bool? { trunkAjar.map { $0 == 1 } }

    func age(now: Date = Date()) -> TimeInterval {
        max(0, now.timeIntervalSince(observedAt))
    }

    func isExpired(now: Date = Date()) -> Bool {
        age(now: now) > Self.maximumAge
    }

    /// "Kilitli" / "Kilitli · 2 saat önce" / nil (değer yok ya da süresi geçmiş).
    func lockText(now: Date = Date()) -> String? {
        guard let isLocked else { return nil }
        return text(isLocked ? "Kilitli" : "Kilit açık", now: now)
    }

    /// "Açık" / "Kapalı" (+ yaş).
    func trunkText(now: Date = Date()) -> String? {
        guard let isTrunkAjar else { return nil }
        return text(isTrunkAjar ? "Açık" : "Kapalı", now: now)
    }

    /// "Hazır" yalnız `powerState == 4` imzalı değerinden gelir.
    func driveText(now: Date = Date()) -> String? {
        guard let powerState else { return nil }
        return text(powerState == 4 ? "Hazır" : "Hazır değil", now: now)
    }

    private func text(_ value: String, now: Date) -> String? {
        guard !isExpired(now: now) else { return nil }
        guard age(now: now) >= Self.freshInterval else { return value }
        return "\(value) · \(LastSeenSummary.relative(observedAt, now))"
    }
}

/// Diskteki son durum özeti: VIN başına tek kayıt, JSON.
enum VehicleStateSnapshotStore {
    static func key(vin: String) -> String { "toqdas.state.snapshot.v1.\(vin)" }

    static func save(_ telemetry: BleTelemetry, vin: String,
                     defaults: UserDefaults = .standard) {
        let snapshot = VehicleStateSnapshot(
            locked: telemetry.locked,
            trunkAjar: telemetry.trunkAjar,
            powerState: telemetry.powerState,
            observedAt: telemetry.receivedAt
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key(vin: vin))
    }

    /// Süresi geçmiş kayıt `nil` döner ve diskten silinir (bayat veri taşınmaz).
    static func load(vin: String, defaults: UserDefaults = .standard,
                     now: Date = Date()) -> VehicleStateSnapshot? {
        guard let data = defaults.data(forKey: key(vin: vin)),
              let snapshot = try? JSONDecoder().decode(VehicleStateSnapshot.self, from: data) else {
            return nil
        }
        guard !snapshot.isExpired(now: now) else {
            defaults.removeObject(forKey: key(vin: vin))
            return nil
        }
        return snapshot
    }

    static func clear(vin: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(vin: vin))
    }
}
