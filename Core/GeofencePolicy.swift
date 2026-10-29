import Foundation

/// Geofence otomasyonunun açılabilmesi için gereken koşullar.
///
/// Amaç: kullanıcı anahtarı açtığında hiçbir şeyin sessizce olmamasını
/// engellemek. Önceden ev konumu yoksa ya da yalnızca "uygulama açıkken" konum
/// izni varsa `startMonitoring` sessizce hiçbir şey yapmıyordu.
enum GeofencePermission: Equatable {
    case notDetermined
    case denied
    case restricted
    case whenInUse
    case always
}

enum GeofenceBlocker: Equatable {
    case missingHomeLocation
    case permissionNotDetermined
    case permissionDenied
    case permissionRestricted
    /// "Uygulama açıkken" izni arka planda bölge giriş/çıkışı almaz.
    case backgroundPermissionMissing
}

struct GeofenceReadiness: Equatable {
    let blocker: GeofenceBlocker?

    var canEnable: Bool { blocker == nil }

    var message: String {
        switch blocker {
        case .none:
            return "Hazır. Bölgeye girince açma, çıkınca kilitleme denenir."
        case .missingHomeLocation:
            return "Önce ev konumunu ayarlayın. Uygulama açıkken “Ev konumunu şu anki konuma ayarla” düğmesini kullanın."
        case .permissionNotDetermined:
            return "Konum izni verilmedi. Arka plan otomasyonu için “Her zaman” izni gerekir."
        case .permissionDenied:
            return "Konum izni reddedilmiş. Ayarlar > Toqdas > Konum bölümünden “Her zaman” seçin."
        case .permissionRestricted:
            return "Konum kullanımı bu cihazda kısıtlanmış (ör. Ebeveyn Denetimi). Geofence kullanılamaz."
        case .backgroundPermissionMissing:
            return "Yalnızca “Uygulama açıkken” izni var; arka planda bölge algılanmaz. Ayarlar’dan “Her zaman” seçin."
        }
    }
}

enum GeofencePolicy {
    /// Bölge yarıçapı. Araç evin önünde park ediyorsa 100 m makul.
    static let radiusMeters: Double = 100
    static let minimumRadiusMeters: Double = 50
    static let maximumRadiusMeters: Double = 500

    static func readiness(
        hasHomeLocation: Bool,
        permission: GeofencePermission
    ) -> GeofenceReadiness {
        switch permission {
        case .restricted:
            return GeofenceReadiness(blocker: .permissionRestricted)
        case .denied:
            return GeofenceReadiness(blocker: .permissionDenied)
        case .notDetermined:
            return GeofenceReadiness(blocker: .permissionNotDetermined)
        case .whenInUse:
            return GeofenceReadiness(blocker: .backgroundPermissionMissing)
        case .always:
            return GeofenceReadiness(blocker: hasHomeLocation ? nil : .missingHomeLocation)
        }
    }

    static func clampedRadius(_ value: Double) -> Double {
        guard value.isFinite else { return radiusMeters }
        return min(max(value, minimumRadiusMeters), maximumRadiusMeters)
    }

    /// Aynı konum ve yarıçapta bölge zaten izleniyorsa yeniden başlatmayı önler.
    static func needsRestart(
        previousCoordinate: (latitude: Double, longitude: Double)?,
        previousRadius: Double,
        newCoordinate: (latitude: Double, longitude: Double)?,
        newRadius: Double
    ) -> Bool {
        guard let previousCoordinate else { return true }
        guard let newCoordinate else { return false }
        let coordinateChanged = abs(previousCoordinate.latitude - newCoordinate.latitude) > 0.00001
            || abs(previousCoordinate.longitude - newCoordinate.longitude) > 0.00001
        return coordinateChanged || abs(previousRadius - newRadius) > 0.5
    }
}
