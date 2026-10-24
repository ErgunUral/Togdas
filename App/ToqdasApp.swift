import SwiftUI

@MainActor
final class GarageModel: ObservableObject {
    @Published var vehicles: [Vehicle] = []
    @Published var signedIn = false
    @Published var busy = false
    @Published var error: String?
    @Published var selectedVin: String? = UserDefaults.standard.string(forKey: "toqdas.selectedVin")
    let api = ToggAPI()
    let loginCoordinator = LoginCoordinator()
    let watch = WatchLink()
    let ble = BleConnection()

    init() {
        do { signedIn = try api.hasSession() }
        catch { self.error = error.localizedDescription }
    }

    func login() async {
        guard !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let result = try await loginCoordinator.login()
            try await api.login(code: result.code, verifier: result.verifier)
            signedIn = true
            try await load()
        } catch { self.error = error.localizedDescription }
    }

    private func load() async throws {
        vehicles = try await api.vehicles()
        if let selectedVin, !vehicles.contains(where: { $0.vin == selectedVin }) {
            self.selectedVin = vehicles.first?.vin
        } else if selectedVin == nil {
            selectedVin = vehicles.first?.vin
        }
        if let selectedVin { UserDefaults.standard.set(selectedVin, forKey: "toqdas.selectedVin") }
        watch.publish(names: vehicles.map(\.title))
    }

    var selectedVehicle: Vehicle? {
        vehicles.first { $0.vin == selectedVin } ?? vehicles.first
    }

    func select(_ vehicle: Vehicle) {
        selectedVin = vehicle.vin
        UserDefaults.standard.set(vehicle.vin, forKey: "toqdas.selectedVin")
    }

    func refresh() async {
        guard signedIn, !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do { try await load() }
        catch { self.error = error.localizedDescription }
    }

    func logout() {
        do {
            try api.logout()
            vehicles = []
            signedIn = false
            watch.publish(names: [])
        } catch { self.error = error.localizedDescription }
    }
}

@main
struct ToqdasApp: App {
    @StateObject private var model = GarageModel()

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-seedCertificate"),
           arguments.indices.contains(index + 1) {
            CertificateCache.seed(base64: arguments[index + 1])
        }
    }

    var body: some Scene {
        WindowGroup { GarageView(model: model).environmentObject(model.ble) }
    }
}

struct GarageView: View {
    @ObservedObject var model: GarageModel

    var body: some View {
        NavigationStack {
            Group {
                if !model.signedIn {
                    LoginView(model: model)
                } else if let vehicle = model.selectedVehicle {
                    DashboardView(model: model, vehicle: vehicle).id(vehicle.vin)
                } else {
                    emptyGarage
                }
            }
            .background(ToggTheme.background.ignoresSafeArea())
            .task {
                if model.signedIn && model.vehicles.isEmpty { await model.refresh() }
            }
        }
        .preferredColorScheme(.dark)
        .tint(ToggTheme.teal)
    }

    private var emptyGarage: some View {
        ZStack {
            ToggTheme.background.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "car.side.fill")
                    .font(.system(size: 60)).foregroundStyle(ToggTheme.teal)
                Text("Araç listesi boş")
                    .font(.title3.bold()).foregroundStyle(.white)
                Text("Araçlarınız yüklendiğinde burada görünecek.")
                    .font(.footnote).foregroundStyle(ToggTheme.muted)
                Button("Yenile") { Task { await model.refresh() } }
                    .buttonStyle(.borderedProminent).disabled(model.busy)
                if model.busy { ProgressView().tint(ToggTheme.teal) }
                if let error = model.error {
                    Text(error).font(.footnote).foregroundStyle(ToggTheme.pink)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(24)
        }
    }
}

struct VehicleDetail: View {
    let vehicle: Vehicle
    let api: ToggAPI
    @State private var result = ""
    @State private var telemetry: VehicleTelemetry?
    @State private var receivedAt: Date?
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "car.side.fill")
                    .font(.system(size: 90)).foregroundStyle(.teal)
                    .frame(maxWidth: .infinity).padding(.vertical, 24)
                Text(vehicle.title).font(.largeTitle.bold())
                Text(vehicle.plate.isEmpty ? vehicle.vin : vehicle.plate).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    metric("Batarya", value: telemetry?.batteryPercent, unit: "%", icon: "battery.100percent")
                    metric("Tahmini menzil", value: telemetry?.rangeKM, unit: "km", icon: "road.lanes")
                }
                if let percent = telemetry?.batteryPercent {
                    ProgressView(value: percent, total: 100).tint(.teal)
                        .accessibilityLabel("Batarya yüzde \(Int(percent.rounded()))")
                }
                if let auxiliary = telemetry?.auxiliaryBatteryPercent {
                    Label("12 V akü: %\(Int(auxiliary.rounded()))", systemImage: "bolt.batteryblock")
                        .font(.subheadline)
                }
                if let receivedAt {
                    Text("Son sorgu: \(receivedAt.formatted(date: .omitted, time: .standard))")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Servis verisi gecikmeli olabilir. Bu saat, verinin araçta ölçüldüğü zaman değildir.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Label("Kilit durumu henüz okunmuyor", systemImage: "lock.questionmark")
                    .font(.subheadline).foregroundStyle(.secondary)
                NavigationLink("Bluetooth komutlar (kilit, bagaj, sürüş)") {
                    CommandView(vehicle: vehicle, api: api)
                }
                Button { Task { await refresh() } } label: {
                    Label("Araç bilgilerini yenile", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).disabled(busy)
                if busy { ProgressView() }
                if let error { Text(error).foregroundStyle(.red) }
                if !result.isEmpty {
                    DisclosureGroup("Teknik servis yanıtı") {
                        Text(result).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                }
                NavigationLink("Servis kartı") { ServiceView(vehicle: vehicle, api: api) }
                NavigationLink("Destek notları (ticket ID gerekli)") {
                    TicketNotesView(ticketId: "", api: api)
                }
            }.padding().frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Araç bilgileri")
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private func metric(_ title: String, value: Double?, unit: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value.map { "\($0.formatted(.number.precision(.fractionLength(0)))) \(unit)" } ?? "—")
                .font(.title2.bold()).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding().background(.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
    }

    @MainActor
    private func refresh() async {
        guard !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let response = try await api.details(for: vehicle)
            let parsed = try VehicleTelemetry(data: Data(response.utf8))
            try Task.checkCancellation()
            result = response
            telemetry = parsed
            receivedAt = Date()
        } catch is CancellationError {
            return
        } catch { self.error = error.localizedDescription }
    }
}

struct DiscoveryView: View {
    @StateObject private var bluetooth = BluetoothDiscovery()
    @Environment(\.scenePhase) private var phase
    var body: some View {
        List {
            Text(bluetooth.status)
            Button(bluetooth.scanning ? "Durdur" : "Araç servisini tara") {
                bluetooth.scanning ? bluetooth.stop() : bluetooth.start()
            }.disabled(bluetooth.activeDeviceID != nil)
            ForEach(bluetooth.devices) { device in
                Button { bluetooth.connect(to: device.id) } label: {
                    VStack(alignment: .leading) {
                        Text(device.name)
                        Text("Tarama: \(device.rssi) dBm • Bağlanmak için dokun").font(.caption)
                    }
                }.disabled(bluetooth.activeDeviceID != nil)
            }
            if bluetooth.activeDeviceID != nil {
                Section("Bağlantı tanısı") {
                    ForEach(bluetooth.channels, id: \.self) { Text($0).font(.caption) }
                    if let rssi = bluetooth.connectionRSSI { Text("Bağlantı sinyali: \(rssi) dBm") }
                    Button("Sinyali yenile") { bluetooth.refreshRSSI() }.disabled(!bluetooth.discoveryComplete)
                    Button("Bağlantıyı kes", role: .destructive) { bluetooth.disconnect() }
                }
            }
            Text("Bu tarama yakın cihazları gösterir; sahiplik veya mesafe kanıtı değildir.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .navigationTitle("Bluetooth")
        .onDisappear { bluetooth.shutdown() }
        .onChange(of: phase) { if $0 == .background { bluetooth.shutdown() } }
    }
}
