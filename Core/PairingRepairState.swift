import Foundation

/// Onarım gereksiniminin oturumlar arası kaydı.
///
/// Neden gerekli: `pairing_lost` sonrası uygulama kapanıp açılınca durum
/// unutuluyor, otomatik bağlanma aynı iOS hatasına çarpıyordu. Kayıt
/// tutulduğunda uygulama açılışta onarım modunda başlar; kilidi yalnız
/// kullanıcı eylemi açar.
struct PairingRepairState: Codable, Equatable {
    let detectedAt: TimeInterval
    let reason: String
}

struct PairingRepairStore {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func key(_ vin: String) -> String { "toqdas.pairing.repair.\(vin)" }

    func load(vin: String) -> PairingRepairState? {
        guard let data = defaults.data(forKey: Self.key(vin)) else { return nil }
        return try? JSONDecoder().decode(PairingRepairState.self, from: data)
    }

    func save(_ state: PairingRepairState, vin: String) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.key(vin))
    }

    func clear(vin: String) {
        defaults.removeObject(forKey: Self.key(vin))
    }
}
