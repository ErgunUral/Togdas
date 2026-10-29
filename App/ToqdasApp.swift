import SwiftUI
import Combine
import UIKit
import WidgetKit

@MainActor
final class GarageModel: ObservableObject {
    @Published var vehicles: [Vehicle] = []
    @Published var signedIn = false
    @Published var busy = false
    @Published var error: String?
    @Published var linkStatus = ""
    @Published var silentRecovery = false
    @Published var selectedVin: String? = UserDefaults.standard.string(forKey: "toqdas.selectedVin")
    let api = ToggAPI()
    let loginCoordinator = LoginCoordinator()
    let watch = WatchLink()
    let ble = BleConnection()
    let proximityMonitor: ProximityDetectionMonitor
    let link: BleLinkCoordinator
    let geofence = GeofenceManager()
    private var watchCancellables = Set<AnyCancellable>()
    private var cloudBatteryPercent: Double?
    private var cloudRangeKM: Double?
    private var cloudOutsideTemperatureC: Double?
    private var cloudAuxiliaryBatteryPercent: Double?
    private var cloudOdometerKM: Double?
    private var cloudChargingState: String?
    private var cloudUpdatedAt: Date?
    private var cloudFetchTask: Task<Void, Never>?
    private var lastWidgetReloadAt = Date.distantPast

    init() {
        proximityMonitor = ProximityDetectionMonitor(ble: ble)
        link = BleLinkCoordinator(ble: ble, api: api)
        do { signedIn = try api.hasSession() }
        catch { self.error = error.localizedDescription }

        if let selectedVin {
            // Eski sürümlerden kalan geçici paylaşılan anahtar kayıtlarını temizle.
            SharedKeyRequestStore.cleanupStaleState(vin: selectedVin)
            proximityMonitor.configure(vin: selectedVin)
            link.configure(vin: selectedVin, isShared: false)
        }

        geofence.onEnterHome = { [weak self] in
            Task { @MainActor in guard self?.ble.state.isReady == true else { return }; _ = self?.ble.unlock() }
        }
        geofence.onExitHome = { [weak self] in
            Task { @MainActor in guard self?.ble.state.isReady == true else { return }; _ = self?.ble.lock() }
        }

        // Arka plan yakınlık algısı: yalnızca izleme; komut göndermez.
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor in self?.proximityMonitor.appDidEnterBackground() }
            }
            .store(in: &watchCancellables)
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.proximityMonitor.appWillEnterForeground()
                    self?.link.handleForeground()
                }
            }
            .store(in: &watchCancellables)
        ble.$rssi
            .sink { [weak self] value in
                guard let value else { return }
                Task { @MainActor in self?.proximityMonitor.feed(rssi: value) }
            }
            .store(in: &watchCancellables)
        $selectedVin
            .sink { [weak self] vin in
                guard let vin else { return }
                Task { @MainActor in
                    self?.proximityMonitor.configure(vin: vin)
                    SharedKeyRequestStore.cleanupStaleState(vin: vin)
                    let shared = self?.selectedVehicle?.isShared ?? false
                    self?.link.configure(vin: vin, isShared: shared)
                    self?.publishWidgetSnapshot()
                }
            }
            .store(in: &watchCancellables)

        // Bağlantı yaşam döngüsü panorama bağlı değil: kopmada yeniden bağlanma
        // ve önbellekli sertifikayla otomatik kimlik doğrulama burada yürür.
        ble.$state
            .dropFirst()
            .removeDuplicates(by: { $0.description == $1.description })
            .sink { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    if state.isReady { LockConfirmationSound.playConnectedTone() }
                    self.link.handle(state: state)
                }
            }
            .store(in: &watchCancellables)
        link.$status
            .sink { [weak self] value in
                Task { @MainActor in self?.linkStatus = value }
            }
            .store(in: &watchCancellables)
        link.$silentRecovery
            .sink { [weak self] value in
                Task { @MainActor in self?.silentRecovery = value }
            }
            .store(in: &watchCancellables)

        watch.commandHandler = { [weak self] request, reply in
            guard let self else {
                reply(WatchCommandResult(id: request.id, status: "unavailable",
                                         message: "Uygulama hazır değil.",
                                         at: Date().timeIntervalSince1970))
                return
            }
            self.handleWatchCommand(request, reply: reply)
        }

        ble.$telemetry
            .throttle(for: .seconds(3), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in
                Task { @MainActor in self?.publishWatchSnapshot() }
            }
            .store(in: &watchCancellables)

        ble.$state
            .removeDuplicates(by: { $0.description == $1.description })
            .sink { [weak self] _ in
                Task { @MainActor in self?.publishWatchSnapshot() }
            }
            .store(in: &watchCancellables)
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
        if let selectedVin {
            UserDefaults.standard.set(selectedVin, forKey: "toqdas.selectedVin")
            SharedKeyRequestStore.cleanupStaleState(vin: selectedVin)
            link.configure(vin: selectedVin, isShared: selectedVehicle?.isShared ?? false)
            link.startIfDesired()
        }
        watch.publish(names: vehicles.map(\.title))
        publishWatchSnapshot()
        refreshCloudIfStale()
    }

    /// Pano yenilemesi bulut telemetrisini saate de yazar. Eksik alan nil kalır.
    func noteCloudTelemetry(_ telemetry: VehicleTelemetry) {
        cloudBatteryPercent = telemetry.batteryPercent
        cloudRangeKM = telemetry.rangeKM
        cloudOutsideTemperatureC = telemetry.outsideTemperatureC
        cloudAuxiliaryBatteryPercent = telemetry.auxiliaryBatteryPercent
        cloudOdometerKM = telemetry.odometerKM
        cloudChargingState = telemetry.chargingState
        cloudUpdatedAt = telemetry.vehicleUpdatedAt ?? Date()
        publishWatchSnapshot()
    }

    private func refreshCloudIfStale() {
        guard signedIn, let vin = selectedVin,
              let vehicle = vehicles.first(where: { $0.vin == vin }) else { return }
        if let cloudUpdatedAt, Date().timeIntervalSince(cloudUpdatedAt) < 120 { return }
        guard cloudFetchTask == nil else { return }
        cloudFetchTask = Task { [weak self] in
            defer { Task { @MainActor in self?.cloudFetchTask = nil } }
            guard let self else { return }
            do {
                let response = try await self.api.details(for: vehicle)
                let parsed = try VehicleTelemetry(data: Data(response.utf8))
                self.noteCloudTelemetry(parsed)
            } catch {
                return
            }
        }
    }

    var selectedVehicle: Vehicle? {
        vehicles.first { $0.vin == selectedVin } ?? vehicles.first
    }

    func select(_ vehicle: Vehicle) {
        selectedVin = vehicle.vin
        UserDefaults.standard.set(vehicle.vin, forKey: "toqdas.selectedVin")
        link.configure(vin: vehicle.vin, isShared: vehicle.isShared)
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
            publishWidgetSnapshot()
        } catch { self.error = error.localizedDescription }
    }

    // MARK: - Saat köprüsü

    /// Saatten gelen kilit isteğini doğrular ve BLE komutuna çevirir.
    /// Saat "kilitlendi" mesajı almaz; onay yalnızca imzalı telemetriden gelir.
    private func handleWatchCommand(_ request: WatchCommandRequest,
                                    reply: @escaping (WatchCommandResult) -> Void) {
        let now = Date().timeIntervalSince1970
        func reject(_ message: String) {
            reply(WatchCommandResult(id: request.id, status: "rejected", message: message, at: now))
        }
        guard !request.isExpired,
              request.createdAt <= now + 1,
              now - request.createdAt <= 15,
              request.expiresAt >= request.createdAt,
              request.expiresAt - request.createdAt <= 15 else {
            return reject("İstek zaman aşımına uğradı veya geçersiz; yeniden deneyin.")
        }
        guard request.vin == selectedVin else {
            return reject("Seçili araç eşleşmiyor.")
        }
        let labels: [String: String] = ["lock": "Kilit", "unlock": "Açma",
                                       "trunkOpen": "Bagaj açma", "trunkClose": "Bagaj kapama"]
        guard let label = labels[request.action] else {
            return reject("Bagaj/cam komutları Watch'tan doğrulanana kadar kapalı.")
        }
        guard ble.canSendVehicleCommands else {
            return reject("READY ve 15 saniyeden yeni, kilit durumu bilinen imzalı telemetri gerekli.")
        }
        let accepted: Bool
        switch request.action {
        case "lock": accepted = ble.lock()
        case "unlock": accepted = ble.unlock()
        case "trunkOpen": accepted = ble.trunkOpen()
        case "trunkClose": accepted = ble.trunkClose()
        default: accepted = false
        }
        guard accepted else {
            return reject(ble.lastEvent.isEmpty ? "Komut BLE katmanında reddedildi." : ble.lastEvent)
        }
        reply(WatchCommandResult(id: request.id, status: "forwarded",
                                 message: "\(label) isteği araca iletildi; taze telemetriyle doğrulama bekleniyor.",
                                 at: now))
        publishWatchSnapshot()
    }

    @MainActor
    func handleShortcutCommand(_ action: String) {
        guard ble.state.isReady else { return }
        switch action {
        case "lock": _ = ble.lock()
        case "unlock": _ = ble.unlock()
        case "trunkOpen": _ = ble.trunkOpen()
        case "trunkClose": _ = ble.trunkClose()
        default: break
        }
    }

    private func publishWatchSnapshot() {
        publishWidgetSnapshot()
        guard let vin = selectedVin,
              let vehicle = vehicles.first(where: { $0.vin == vin }) else { return }
        let telemetry = ble.telemetry
        let age = telemetry.map { Date().timeIntervalSince($0.receivedAt) }
        watch.publish(snapshot: WatchSnapshot(
            vin: vin,
            vehicleName: vehicle.title,
            locked: telemetry?.isLocked,
            doorCount: telemetry?.doors.count ?? 0,
            openDoors: telemetry?.doors.filter { $0 != 0 }.count ?? 0,
            trunkAjar: telemetry.map { $0.trunkAjar != 0 },
            powerState: telemetry?.powerState,
            ready: ble.state.isReady,
            bleState: ble.state.description,
            updatedAt: Date().timeIntervalSince1970,
            telemetryAge: age,
            batteryPercent: cloudBatteryPercent,
            rangeKM: cloudRangeKM,
            outsideTemperatureC: cloudOutsideTemperatureC,
            auxiliaryBatteryPercent: cloudAuxiliaryBatteryPercent,
            odometerKM: cloudOdometerKM,
            chargingState: cloudChargingState,
            proximityEnabled: UserDefaults.standard.bool(forKey: "toqdas.proximity.enabled.\(vin)"),
            recovering: link.silentRecovery
        ))
        refreshCloudIfStale()
    }

    /// Widget'e yalnızca gösterim için araç adı ve telemetri özeti yazar.
    /// Kimlik bilgileri ve dijital anahtar verileri App Group'a aktarılmaz.
    private func publishWidgetSnapshot() {
        guard let vin = selectedVin,
              let vehicle = vehicles.first(where: { $0.vin == vin }) else {
            VehicleWidgetSnapshotStore.clear()
            reloadWidgetIfNeeded()
            return
        }

        VehicleWidgetSnapshotStore.save(VehicleWidgetSnapshot(
            vehicleName: vehicle.title,
            locked: ble.telemetry?.isLocked,
            batteryPercent: cloudBatteryPercent,
            rangeKM: cloudRangeKM,
            bleReady: ble.state.isReady,
            bleUpdatedAt: ble.telemetry?.receivedAt,
            cloudUpdatedAt: cloudUpdatedAt,
            savedAt: Date()
        ))
        reloadWidgetIfNeeded()
    }

    /// WidgetKit yenilemelerini uygulama içi BLE telemetrisinden daha seyrek
    /// ister; iOS yine de kendi pil/yenileme politikasını uygular.
    private func reloadWidgetIfNeeded() {
        guard Date().timeIntervalSince(lastWidgetReloadAt) >= 60 else { return }
        lastWidgetReloadAt = Date()
        WidgetCenter.shared.reloadTimelines(ofKind: VehicleWidgetSnapshot.widgetKind)
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
        WindowGroup { GarageView(model: model).environmentObject(model.ble)
            .onOpenURL { url in
                guard url.scheme == "toqdas", url.host == "command",
                      let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
                      let action = comps.queryItems?.first(where: { $0.name == "action" })?.value else { return }
                model.handleShortcutCommand(action)
            } }
    }
}

struct GarageView: View {
    @ObservedObject var model: GarageModel
    @AppStorage("toqdas.theme") private var themeName = ToggThemeStyle.togg.rawValue

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
            .background((ToggThemeStyle(rawValue: themeName)?.backgroundColor ?? ToggTheme.background).ignoresSafeArea())
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
                        if device.name.hasPrefix("My T-SAS") {
                            Text("My T-SAS adayı; VIN-ad eşleşmesi ve servis UUID'leri yalnızca tanı amaçlıdır.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
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
            Section("Tanı") {
                Text("Bu tarama yalnızca yakın BLE cihazlarını gösterir. My T-SAS adı ve servis UUID'leri sahiplik veya yetkilendirme kanıtı değildir. VIN-ad eşleşmesi, bond durumu ve servis UUID'leri yalnızca tanı amaçlıdır.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Bu tarama yakın cihazları gösterir; sahiplik veya mesafe kanıtı değildir.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .navigationTitle("Bluetooth")
        .onDisappear { bluetooth.shutdown() }
        .onChange(of: phase) { if $0 == .background { bluetooth.shutdown() } }
    }
}
