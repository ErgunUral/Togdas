import CoreLocation
import MapKit
import SwiftUI
import UIKit

struct ChargingStation: Identifiable {
    let id: String
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D
    let distance: CLLocationDistance
    let item: MKMapItem

    var distanceText: String {
        distance < 1000 ? "\(Int(distance.rounded())) m" : String(format: "%.1f km", distance / 1000)
    }
}

/// Kullanıcı konumunu tek seferlik ister; izin verilmezse uygulama çökmez.
final class NearbyLocation: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var location: CLLocation?
    @Published var status: CLAuthorizationStatus = .notDetermined
    @Published var error: String?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            status = manager.authorizationStatus
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        status = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        location = last
        error = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        self.error = error.localizedDescription
    }
}

/// Apple Maps üzerinden yakındaki Trugo / elektrikli araç şarj istasyonlarını arar.
/// İstasyon verisi Togg'un özel servisi değil, Apple Maps arama sonuçlarıdır.
struct ChargingStationsView: View {
    @StateObject private var location = NearbyLocation()
    @State private var stations: [ChargingStation] = []
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.0, longitude: 35.0),
        span: MKCoordinateSpan(latitudeDelta: 8, longitudeDelta: 8)
    )
    @State private var busy = false
    @State private var error: String?
    @State private var searched = false

    var body: some View {
        ZStack {
            ToggTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    permissionState
                    if !stations.isEmpty { mapCard }
                    if busy {
                        ProgressView().tint(ToggTheme.teal).padding(24)
                    }
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(ToggTheme.pink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if searched && stations.isEmpty && !busy && error == nil && canUseLocation {
                        Text("Yakında şarj istasyonu bulunamadı. Arama yarıçapı yaklaşık 40 km.")
                            .font(.footnote).foregroundStyle(ToggTheme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(stations) { station in
                        stationCard(station)
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Şarj İstasyonları")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { location.request() }
        .onReceive(location.$location) { newValue in
            guard let newValue, !searched else { return }
            searched = true
            region = MKCoordinateRegion(
                center: newValue.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
            )
            Task { await search(around: newValue) }
        }
    }

    private var canUseLocation: Bool {
        location.status == .authorizedWhenInUse || location.status == .authorizedAlways
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(ToggTheme.teal.opacity(0.2)).frame(width: 40, height: 40)
                Image(systemName: "bolt.car.fill")
                    .font(.system(size: 18)).foregroundStyle(ToggTheme.teal)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Yakındaki Şarj İstasyonları")
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                Text("Apple Maps araması • Trugo ve EV şarj noktaları")
                    .font(.system(size: 11)).foregroundStyle(ToggTheme.muted)
                    .lineLimit(2)
            }
            Spacer()
            Button { location.request() } label: {
                Image(systemName: "location.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(ToggTheme.teal)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(ToggTheme.surfaceVariant))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .toggCardBackground(20)
    }

    @ViewBuilder
    private var permissionState: some View {
        if location.status == .denied || location.status == .restricted {
            VStack(alignment: .leading, spacing: 10) {
                Label("Konum izni kapalı", systemImage: "location.slash.fill")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                Text("Yakındaki istasyonları listelemek için Ayarlar'dan konum iznini aç.")
                    .font(.caption).foregroundStyle(ToggTheme.muted)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Ayarları aç")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(.black)
                        .padding(.horizontal, 14).frame(height: 36)
                        .background(Capsule().fill(ToggTheme.teal))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .toggCardBackground(18)
        }
    }

    private var mapCard: some View {
        Map(coordinateRegion: $region, showsUserLocation: true, annotationItems: stations) { station in
            MapAnnotation(coordinate: station.coordinate) {
                ZStack {
                    Circle().fill(ToggTheme.teal).frame(width: 26, height: 26)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(.black)
                }
            }
        }
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(ToggTheme.outline.opacity(0.6), lineWidth: 0.5))
    }

    private func stationCard(_ station: ChargingStation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(station.name)
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                        .lineLimit(2)
                    if !station.address.isEmpty {
                        Text(station.address)
                            .font(.system(size: 11)).foregroundStyle(ToggTheme.muted)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 6)
                Text(station.distanceText)
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(ToggTheme.teal)
            }
            HStack(spacing: 8) {
                Button {
                    station.item.openInMaps(launchOptions: [
                        MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
                    ])
                } label: {
                    Label("Yol tarifi", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(.black)
                        .frame(maxWidth: .infinity).frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 10).fill(ToggTheme.teal))
                }
                .buttonStyle(.plain)

                Button {
                    station.item.openInMaps()
                } label: {
                    Label("Haritada aç", systemImage: "map")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 10).fill(ToggTheme.surfaceVariant))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .toggCardBackground(18)
    }

    // MARK: - Arama

    private func search(around location: CLLocation) async {
        busy = true
        error = nil
        defer { busy = false }
        var found: [MKMapItem] = []
        for query in ["Trugo şarj istasyonu", "elektrikli araç şarj istasyonu"] {
            if let items = try? await localSearch(query, around: location) {
                found.append(contentsOf: items)
            }
        }
        var seen = Set<String>()
        var result: [ChargingStation] = []
        for item in found {
            guard let name = item.name, !name.isEmpty else { continue }
            let coordinate = item.placemark.coordinate
            let key = "\(name.lowercased())-\(Int(coordinate.latitude * 1000))-\(Int(coordinate.longitude * 1000))"
            guard seen.insert(key).inserted else { continue }
            let address = [item.placemark.thoroughfare, item.placemark.locality]
                .compactMap { $0 }.joined(separator: ", ")
            let distance = location.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            result.append(ChargingStation(
                id: key, name: name, address: address,
                coordinate: coordinate, distance: distance, item: item
            ))
        }
        stations = Array(result.sorted { $0.distance < $1.distance }.prefix(30))
        if stations.isEmpty { error = nil }
    }

    private func localSearch(_ query: String, around location: CLLocation) async throws -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: 40_000,
            longitudinalMeters: 40_000
        )
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems
    }
}
