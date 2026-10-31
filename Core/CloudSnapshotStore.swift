import Foundation

/// Son bilinen bulut telemetrisi özeti. Pano soğuk başlangıçta ağ yanıtı
/// gelmeden boş kalmamak için önceki değeri gösterir; eksik alan `nil` kalır,
/// gerçek 0 değeri korunur.
struct CloudSnapshot: Codable, Equatable {
    let batteryPercent: Double?
    let rangeKM: Double?
    let outsideTemperatureC: Double?
    let auxiliaryBatteryPercent: Double?
    let odometerKM: Double?
    let chargingState: String?
    let updatedAt: Date
}

/// VIN bazlı son bulut telemetrisi önbelleği.
///
/// Neden gerekli: soğuk başlıkta `GarageModel.cloud` boş başlıyordu; kullanıcı
/// ağ yanıtı gelene kadar "—" görüyordu ve araç değişince önceki aracın
/// değerleri yeni seçime taşınabiliyordu. Depo VIN anahtarlı olduğu için
/// seçim değişiminde doğru aracın son kaydı yüklenir, diğer VIN'e sızmaz.
/// Konum/koordinat ve kişisel veri saklanmaz; yalnız telemetri özeti.
final class CloudSnapshotStore {
    static let keyPrefix = "toqdas.cloudSnapshot."

    private let store: KeyValueStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(store: KeyValueStore = UserDefaults.standard) {
        self.store = store
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
    }

    static func key(for vin: String) -> String { keyPrefix + vin }

    func snapshot(for vin: String) -> CloudSnapshot? {
        guard !vin.isEmpty,
              let raw = store.string(forKey: Self.key(for: vin))?.data(using: .utf8)
        else { return nil }
        return try? decoder.decode(CloudSnapshot.self, from: raw)
    }

    func save(_ snapshot: CloudSnapshot, for vin: String) {
        guard !vin.isEmpty, let data = try? encoder.encode(snapshot) else { return }
        store.set(String(decoding: data, as: UTF8.self), forKey: Self.key(for: vin))
    }

    func clear(for vin: String) {
        guard !vin.isEmpty else { return }
        store.removeObject(forKey: Self.key(for: vin))
    }
}
