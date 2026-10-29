import CoreLocation
import Foundation

/// Ev/iş geofence otomasyonu. Bölgeye girince açma, çıkınca kilitleme tetikler.
/// Komutlar BLE READY ve taze telemetri koşuluna tabidir; uygulama arka planda
/// uyandırılabilir (location background mode).
///
/// Hazır olma koşulları `GeofencePolicy` ile denetlenir; eksik izin/konum
/// durumunda anahtar sessizce açık kalmaz, nedeni `blockerMessage`'da yazar.
final class GeofenceManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let homeRegionId = "toqdas.home"
    private let manager = CLLocationManager()
    private let defaults: UserDefaults

    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var homeCoordinate: CLLocationCoordinate2D?
    @Published private(set) var enabled = false
    @Published private(set) var isMonitoring = false
    /// Son konum hatası; kullanıcıya gösterilir.
    @Published private(set) var lastError: String?
    @Published private(set) var radiusMeters: Double = GeofencePolicy.radiusMeters

    var onEnterHome: (() -> Void)?
    var onExitHome: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        manager.delegate = self
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = true
        if let lat = defaults.object(forKey: "toqdas.geofence.homeLat") as? Double,
           let lon = defaults.object(forKey: "toqdas.geofence.homeLon") as? Double {
            homeCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        if let savedRadius = defaults.object(forKey: "toqdas.geofence.radius") as? Double {
            radiusMeters = GeofencePolicy.clampedRadius(savedRadius)
        }
        authorizationStatus = manager.authorizationStatus
        enabled = defaults.bool(forKey: "toqdas.geofence.enabled")
        if enabled { startMonitoring() }
    }

    var permission: GeofencePermission {
        switch authorizationStatus {
        case .authorizedAlways: return .always
        case .authorizedWhenInUse: return .whenInUse
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    var readiness: GeofenceReadiness {
        GeofencePolicy.readiness(hasHomeLocation: homeCoordinate != nil, permission: permission)
    }

    var blockerMessage: String? {
        readiness.blocker == nil ? nil : readiness.message
    }

    func requestAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    func setHomeToCurrentLocation() {
        lastError = nil
        switch permission {
        case .denied, .restricted:
            lastError = "Konum izni olmadan ev konumu alınamaz."
            return
        case .notDetermined:
            requestAuthorization()
            return
        case .whenInUse, .always:
            manager.requestLocation()
        }
    }

    func clearHomeLocation() {
        homeCoordinate = nil
        defaults.removeObject(forKey: "toqdas.geofence.homeLat")
        defaults.removeObject(forKey: "toqdas.geofence.homeLon")
        stopMonitoring()
        setEnabled(false)
    }

    func applyHomeCoordinate(_ coordinate: CLLocationCoordinate2D) {
        homeCoordinate = coordinate
        defaults.set(coordinate.latitude, forKey: "toqdas.geofence.homeLat")
        defaults.set(coordinate.longitude, forKey: "toqdas.geofence.homeLon")
        if enabled { startMonitoring(force: true) }
    }

    func setRadius(_ value: Double) {
        let clamped = GeofencePolicy.clampedRadius(value)
        guard clamped != radiusMeters else { return }
        radiusMeters = clamped
        defaults.set(clamped, forKey: "toqdas.geofence.radius")
        if enabled { startMonitoring(force: true) }
    }

    /// Anahtarı açar. Hazır değilse açmaz ve `blockerMessage` nedeni söyler.
    @discardableResult
    func setEnabled(_ value: Bool) -> Bool {
        guard value else {
            enabled = false
            defaults.set(false, forKey: "toqdas.geofence.enabled")
            stopMonitoring()
            return true
        }
        guard readiness.canEnable else {
            enabled = false
            defaults.set(false, forKey: "toqdas.geofence.enabled")
            return false
        }
        enabled = true
        defaults.set(true, forKey: "toqdas.geofence.enabled")
        startMonitoring(force: true)
        return true
    }

    private func startMonitoring(force: Bool = false) {
        guard enabled, let coord = homeCoordinate else {
            isMonitoring = false
            return
        }
        guard permission == .always else {
            stopMonitoring()
            return
        }
        if !force, isMonitoring { return }
        stopMonitoring()
        let region = CLCircularRegion(center: coord, radius: radiusMeters, identifier: Self.homeRegionId)
        region.notifyOnEntry = true
        region.notifyOnExit = true
        manager.startMonitoring(for: region)
        isMonitoring = manager.monitoredRegions.contains { $0.identifier == Self.homeRegionId }
    }

    private func stopMonitoring() {
        for region in manager.monitoredRegions where region.identifier == Self.homeRegionId {
            manager.stopMonitoring(for: region)
        }
        isMonitoring = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedAlways, enabled {
            startMonitoring(force: true)
        } else if authorizationStatus != .authorizedAlways {
            // İzin geri alındıysa bölge izlemeyi bırak, anahtarı kapat.
            stopMonitoring()
            if enabled { setEnabled(false) }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        lastError = nil
        applyHomeCoordinate(last.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier == Self.homeRegionId else { return }
        onEnterHome?()
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier == Self.homeRegionId else { return }
        onExitHome?()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        lastError = "Konum alınamadı: \(error.localizedDescription)"
    }

    func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?,
                         withError error: Error) {
        isMonitoring = false
        lastError = "Bölge izleme başlatılamadı: \(error.localizedDescription)"
    }
}
