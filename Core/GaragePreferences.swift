import Foundation

/// `UserDefaults` yerine enjekte edilebilen basit anahtar-değer deposu.
/// Testlerde bellek içi sahte depo kullanılır; üretimde `UserDefaults.standard`.
protocol KeyValueStore: AnyObject {
    func string(forKey key: String) -> String?
    func bool(forKey key: String) -> Bool
    func set(_ value: Any?, forKey key: String)
    func removeObject(forKey key: String)
}

extension UserDefaults: KeyValueStore {}

/// Garaj tercihleri: seçili araç ve otomatik bağlantı izni.
///
/// Daha önce bu anahtarlar `GarageModel`, `BleLinkCoordinator` ve
/// `ProximityDetectionMonitor` içinde ayrı ayrı string olarak yazılıyordu.
/// Tek yerde toplanınca anahtar yazımı hataları ve test edilemeyen
/// `UserDefaults.standard` bağımlılığı ortadan kalkar.
struct GaragePreferences {
    static let selectedVinKey = "toqdas.selectedVin"
    static let keepConnectedKey = "toqdas.ble.keepConnected"

    static func proximityKey(for vin: String) -> String { "toqdas.proximity.enabled.\(vin)" }

    private let store: KeyValueStore

    init(store: KeyValueStore = UserDefaults.standard) {
        self.store = store
    }

    var selectedVin: String? {
        get { store.string(forKey: Self.selectedVinKey) }
        nonmutating set {
            if let newValue { store.set(newValue, forKey: Self.selectedVinKey) }
            else { store.removeObject(forKey: Self.selectedVinKey) }
        }
    }

    /// Kullanıcı "bağlı tut" dedi mi?
    var keepConnected: Bool {
        store.bool(forKey: Self.keepConnectedKey)
    }

    func proximityEnabled(for vin: String) -> Bool {
        guard !vin.isEmpty else { return false }
        return store.bool(forKey: Self.proximityKey(for: vin))
    }

    func setProximityEnabled(_ enabled: Bool, for vin: String) {
        guard !vin.isEmpty else { return }
        store.set(enabled, forKey: Self.proximityKey(for: vin))
    }

    /// Otomatik bağlanma izni: "bağlı tut" veya bu araç için yakınlık açık.
    func autoConnectEnabled(for vin: String) -> Bool {
        guard !vin.isEmpty else { return false }
        return keepConnected || proximityEnabled(for: vin)
    }
}
