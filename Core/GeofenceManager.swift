import CoreLocation
import Foundation

/// Ev/iş geofence otomasyonu. Bölgeye girince açma, çıkınca kilitleme tetikler.
/// Komutlar BLE READY ve taze telemetri koşuluna tabidir; uygulama arka planda
/// uyandırılabilir (location background mode).
final class GeofenceManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let homeRegionId = "toqdas.home"
    private let manager = CLLocationManager()
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var homeCoordinate: CLLocationCoordinate2D?
    @Published var enabled = false

    var onEnterHome: (() -> Void)?
    var onExitHome: (() -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.allowsBackgroundLocationUpdates = true
        manager.pausesLocationUpdatesAutomatically = true
        if let lat = UserDefaults.standard.object(forKey: "toqdas.geofence.homeLat") as? Double,
           let lon = UserDefaults.standard.object(forKey: "toqdas.geofence.homeLon") as? Double {
            homeCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        enabled = UserDefaults.standard.bool(forKey: "toqdas.geofence.enabled")
    }

    func requestAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    func setHomeToCurrentLocation() {
        manager.requestLocation()
    }

    func applyHomeCoordinate(_ coordinate: CLLocationCoordinate2D) {
        homeCoordinate = coordinate
        UserDefaults.standard.set(coordinate.latitude, forKey: "toqdas.geofence.homeLat")
        UserDefaults.standard.set(coordinate.longitude, forKey: "toqdas.geofence.homeLon")
        if enabled { startMonitoring() }
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        UserDefaults.standard.set(value, forKey: "toqdas.geofence.enabled")
        if value { startMonitoring() } else { stopMonitoring() }
    }

    private func startMonitoring() {
        guard let coord = homeCoordinate else { return }
        stopMonitoring()
        let region = CLCircularRegion(center: coord, radius: 100, identifier: Self.homeRegionId)
        region.notifyOnEntry = true
        region.notifyOnExit = true
        manager.startMonitoring(for: region)
    }

    private func stopMonitoring() {
        for region in manager.monitoredRegions where region.identifier == Self.homeRegionId {
            manager.stopMonitoring(for: region)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedAlways, enabled { startMonitoring() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let last = locations.last, homeCoordinate == nil {
            applyHomeCoordinate(last.coordinate)
        }
    }

    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier == Self.homeRegionId else { return }
        onEnterHome?()
    }

    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier == Self.homeRegionId else { return }
        onExitHome?()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}