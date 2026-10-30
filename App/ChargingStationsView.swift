import CoreLocation
import MapKit
import SwiftUI
import UIKit

/// Tek seferlik iPhone konumu yalnızca cihaz içinde mesafe/sıralama hesabında
/// kullanılır. Koordinat EPDK'ya gönderilmez ve istemci geocoding yapılmaz.
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

private struct VisibleEPDKStation: Identifiable {
    let station: EPDKStation
    let distanceKM: Double?
    var id: String { station.id }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude = station.latitude, let longitude = station.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var distanceText: String? {
        guard let distanceKM else { return nil }
        return distanceKM < 1
            ? "\(Int((distanceKM * 1_000).rounded())) m"
            : "\(TurkishFormat.decimal(distanceKM, digits: 1)) km"
    }

    var mapItem: MKMapItem? {
        guard let coordinate else { return nil }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = station.name
        return item
    }
}

private struct MappableEPDKStation: Identifiable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
}

struct ChargingStationsView: View {
    @StateObject private var location = NearbyLocation()
    @State private var catalog: EPDKCatalog?
    @State private var isLoading = false
    @State private var error: String?
    @State private var warning: String?
    @State private var searchText = ""
    @State private var connectorType = "ALL"
    @State private var radiusKM = 40.0
    @State private var nearbyOnly = true
    @State private var publicOnly = true
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.0, longitude: 35.0),
        span: MKCoordinateSpan(latitudeDelta: 8, longitudeDelta: 8)
    )

    private var visibleStations: [VisibleEPDKStation] {
        guard let catalog else { return [] }
        let origin = nearbyOnly ? location.location.map {
            (latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        } : nil
        return catalog.filtered(
            query: searchText,
            connectorType: connectorType,
            publicOnly: publicOnly,
            origin: origin,
            radiusKM: nearbyOnly ? radiusKM : 0,
            limit: 30
        ).map { VisibleEPDKStation(station: $0.station, distanceKM: $0.distanceKM) }
    }

    private var mappableStations: [MappableEPDKStation] {
        visibleStations.compactMap { item in
            guard let coordinate = item.coordinate else { return nil }
            return MappableEPDKStation(id: item.id, name: item.station.name, coordinate: coordinate)
        }
    }

    private var canUseLocation: Bool {
        location.status == .authorizedWhenInUse || location.status == .authorizedAlways
    }

    var body: some View {
        ZStack {
            ToggTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    header
                    searchAndFilters
                    sourceStatus
                    permissionState

                    if isLoading {
                        ProgressView("EPDK kataloğu alınıyor…")
                            .tint(ToggTheme.teal)
                            .padding(20)
                    }
                    if let error {
                        messageCard(error, color: ToggTheme.pink, icon: "exclamationmark.triangle.fill")
                    }
                    if let warning {
                        messageCard(warning, color: ToggTheme.orange, icon: "clock.fill")
                    }
                    if nearbyOnly && location.location == nil && !isLoading {
                        messageCard(
                            canUseLocation ? "Konum bekleniyor. İstersen tüm katalogda ada/adrese göre arayabilirsin." : "Yakın istasyonları sıralamak için konum izni gerekir. Konum cihazda kalır; EPDK'ya gönderilmez.",
                            color: ToggTheme.muted,
                            icon: "location.circle"
                        )
                    }
                    if !mappableStations.isEmpty && nearbyOnly { mapCard }
                    if !isLoading && !visibleStations.isEmpty {
                        Text("\(visibleStations.count) istasyon gösteriliyor · EPDK kayıt verisi")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(ToggTheme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if !isLoading, catalog != nil, !(nearbyOnly && location.location == nil) {
                        Text("Bu filtrelerle istasyon bulunamadı.")
                            .font(.footnote).foregroundStyle(ToggTheme.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(visibleStations) { station in stationCard(station) }
                }
                .padding(16)
            }
        }
        .navigationTitle("Şarj İstasyonları")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { location.request() }
        .onChange(of: location.location?.timestamp) { _ in
            guard let value = location.location else { return }
            region = MKCoordinateRegion(
                center: value.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
            )
        }
        .task { await loadCatalog() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(ToggTheme.teal.opacity(0.2)).frame(width: 40, height: 40)
                Image(systemName: "bolt.car.fill")
                    .font(.system(size: 18)).foregroundStyle(ToggTheme.teal)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("EPDK Şarj İstasyonları")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                Text("Türkiye kataloğu · anlık doluluk bilgisi içermez")
                    .font(.system(size: 10)).foregroundStyle(ToggTheme.muted)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            Button { location.request() } label: {
                Image(systemName: "location.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(ToggTheme.teal)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(ToggTheme.surfaceVariant))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Konumu yenile")

            Button { Task { await loadCatalog(forceRefresh: true) } } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(ToggTheme.surfaceVariant))
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .accessibilityLabel("EPDK kataloğunu yenile")
        }
        .padding(14)
        .toggCardBackground(18)
    }

    private var searchAndFilters: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(ToggTheme.muted)
                TextField("İstasyon, marka, işletmeci veya adres", text: $searchText)
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 11).fill(ToggTheme.surfaceVariant))

            HStack(spacing: 8) {
                Picker("Soket", selection: $connectorType) {
                    Text("AC + DC").tag("ALL")
                    Text("AC").tag("AC")
                    Text("DC").tag("DC")
                }
                .pickerStyle(.menu)
                .tint(ToggTheme.teal)

                if nearbyOnly {
                    Picker("Yarıçap", selection: $radiusKM) {
                        Text("5 km").tag(5.0)
                        Text("10 km").tag(10.0)
                        Text("25 km").tag(25.0)
                        Text("40 km").tag(40.0)
                        Text("100 km").tag(100.0)
                    }
                    .pickerStyle(.menu)
                    .tint(ToggTheme.teal)
                }
                Spacer(minLength: 0)
            }

            Toggle("Yalnız halka açık", isOn: $publicOnly)
                .font(.system(size: 11, weight: .medium))
                .tint(ToggTheme.teal)

            Toggle("Yakınımda · \(Int(radiusKM)) km", isOn: $nearbyOnly)
                .font(.system(size: 11, weight: .medium))
                .tint(ToggTheme.teal)
                .disabled(!nearbyOnly && location.location == nil && !canUseLocation)
        }
        .padding(14)
        .toggCardBackground(18)
    }

    @ViewBuilder
    private var sourceStatus: some View {
        if let catalog {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(ToggTheme.teal)
                Text("EPDK · \(catalog.stations.count.formatted()) kayıt · \(catalog.fetchedAt.formatted(date: .omitted, time: .shortened))")
                    .foregroundStyle(ToggTheme.muted)
                if catalog.isOlderThanOneDay {
                    Text("Eski katalog").foregroundStyle(ToggTheme.orange)
                }
            }
            .font(.system(size: 9, weight: .medium))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var permissionState: some View {
        if location.status == .denied || location.status == .restricted {
            VStack(alignment: .leading, spacing: 8) {
                Label("Konum izni kapalı", systemImage: "location.slash.fill")
                    .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                Text("Yakınlık filtresi için konum izni ver. İzin olmadan tüm katalogda metin araması kullanılabilir.")
                    .font(.caption2).foregroundStyle(ToggTheme.muted)
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Ayarları aç")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(.black)
                        .padding(.horizontal, 12).frame(height: 32)
                        .background(Capsule().fill(ToggTheme.teal))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .toggCardBackground(16)
        }
    }

    private var mapCard: some View {
        Map(coordinateRegion: $region, showsUserLocation: canUseLocation, annotationItems: mappableStations) { item in
            MapAnnotation(coordinate: item.coordinate) {
                ZStack {
                    Circle().fill(ToggTheme.teal).frame(width: 25, height: 25)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(.black)
                }
            }
        }
        .frame(height: 230)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(ToggTheme.outline.opacity(0.6), lineWidth: 0.5))
    }

    private func stationCard(_ item: VisibleEPDKStation) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.station.name)
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        .lineLimit(2)
                    if !item.station.brand.isEmpty {
                        Text(item.station.brand)
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(ToggTheme.teal)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if let distance = item.distanceText {
                    Text(distance).font(.system(size: 11, weight: .bold)).foregroundStyle(ToggTheme.teal)
                }
            }

            if !item.station.address.isEmpty {
                Text(item.station.address)
                    .font(.system(size: 10)).foregroundStyle(ToggTheme.muted)
                    .lineLimit(3)
            }
            if !item.station.operatorName.isEmpty {
                Text("İşletmeci: \(item.station.operatorName)")
                    .font(.system(size: 9)).foregroundStyle(ToggTheme.muted.opacity(0.9))
                    .lineLimit(2)
            }

            if item.station.connectors.isEmpty {
                Text("Soket bilgisi bulunmuyor")
                    .font(.system(size: 10)).foregroundStyle(ToggTheme.muted)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(item.station.connectors.prefix(4)) { connector in
                        Label(connector.displayText, systemImage: "poweroutlet.type.i")
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.85))
                    }
                    if item.station.connectors.count > 4 {
                        Text("+\(item.station.connectors.count - 4) soket daha")
                            .font(.system(size: 9)).foregroundStyle(ToggTheme.muted)
                    }
                }
            }

            HStack(spacing: 5) {
                Image(systemName: "questionmark.circle")
                Text("Anlık soket uygunluğu EPDK kataloğunda yer almıyor")
            }
            .font(.system(size: 9)).foregroundStyle(ToggTheme.muted)

            HStack(spacing: 8) {
                Button {
                    openInMaps(item, directions: true)
                } label: {
                    Label("Yol tarifi", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(.black)
                        .frame(maxWidth: .infinity).frame(height: 33)
                        .background(RoundedRectangle(cornerRadius: 9).fill(ToggTheme.teal))
                }
                .buttonStyle(.plain)
                .disabled(item.mapItem == nil)

                Button {
                    openInMaps(item, directions: false)
                } label: {
                    Label("Haritada aç", systemImage: "map")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 33)
                        .background(RoundedRectangle(cornerRadius: 9).fill(ToggTheme.surfaceVariant))
                }
                .buttonStyle(.plain)
                .disabled(item.mapItem == nil)
            }
        }
        .padding(13)
        .toggCardBackground(16)
    }

    private func openInMaps(_ station: VisibleEPDKStation, directions: Bool) {
        guard let item = station.mapItem else { return }
        if directions {
            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
        } else {
            item.openInMaps()
        }
    }

    private func messageCard(_ text: String, color: Color, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .toggCardBackground(14)
    }

    @MainActor
    private func loadCatalog(forceRefresh: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let result = try await EPDKStationService.shared.load(forceRefresh: forceRefresh)
            catalog = result.catalog
            warning = result.warning
        } catch {
            self.error = error.localizedDescription
        }
    }
}
