import SwiftUI

enum DashboardTab: String, CaseIterable, Identifiable {
    case overview, climate, charging, health

    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "Genel Bakış"
        case .climate: return "İklimlendirme"
        case .charging: return "Trugo Şarj"
        case .health: return "Araç Durumu"
        }
    }
    var icon: String {
        switch self {
        case .overview: return "car.side.fill"
        case .climate: return "snowflake"
        case .charging: return "bolt.car.fill"
        case .health: return "gauge.with.dots.needle.50percent"
        }
    }
}

private enum DashboardAlert: Identifiable {
    case notice(String)
    case confirm(DashboardCommand)

    var id: String {
        switch self {
        case .notice(let text): return "notice:" + text
        case .confirm(let command): return "confirm:" + command.rawValue
        }
    }
}

private enum DashboardCommand: String, Identifiable {
    case lock, unlock, trunkOpen, trunkClose, windowsOpen, windowsClose

    var id: String { rawValue }

    var detail: String {
        switch self {
        case .lock: return "Önce cam kapatma komutu, ardından kapı kilitleme komutu gönderilecek. Cam konumu doğrulanamıyor; çevrede engel olmadığından emin olun."
        case .unlock: return "Kapı kilitleri açılacak."
        case .trunkOpen: return "Arka bagaj açılacak."
        case .trunkClose: return "Arka bagaj kapatılacak."
        case .windowsOpen: return "Yan cam açma komutu gönderilecek. Cam konumu ayrıca doğrulanamayabilir; çevrede engel olmadığından emin olun."
        case .windowsClose: return "Yan cam kapatma komutu gönderilecek. Cam konumu ayrıca doğrulanamayabilir; çevrede engel olmadığından emin olun."
        }
    }
}

struct DashboardView: View {
    @ObservedObject var model: GarageModel
    let vehicle: Vehicle
    @AppStorage("toqdas.theme") private var themeName = ToggThemeStyle.togg.rawValue
    @AppStorage("toqdas.dashboardLayout") private var layoutName = DashboardLayoutStyle.classic.rawValue

    @EnvironmentObject private var ble: BleConnection

    @State private var tab: DashboardTab = .overview
    @State private var telemetry: VehicleTelemetry?
    @State private var updatedAt: Date?
    @State private var busy = false
    @State private var error: String?
    @State private var showCommands = false
    @State private var showDetail = false
    @State private var showDiscovery = false
    @State private var showService = false
    @State private var showExperience = false
    @State private var showStations = false
    @State private var showAccount = false
    @State private var authBusy = false
    @State private var alert: DashboardAlert?
    @State private var autoKeyStarted = false
    @State private var hasAuthenticatedBLE = false
    @State private var keepBLEConnected = false
    @State private var reconnectAttempts = 0
    @State private var reconnectTask: Task<Void, Never>?
    @State private var stableConnectionTask: Task<Void, Never>?
    @State private var proximityEnabled = false
    @State private var proximityProfile: ProximityProfile = .balanced
    @State private var proximityNearSample: Int?
    @State private var proximityFarSample: Int?
    @State private var proximityGate: ProximityGate?
    @State private var proximityRSSISamples: [Int] = []
    @State private var proximityStatus = "Ölçüm bekleniyor"
    @State private var showProximityConfirmation = false
    @State private var proximityAutoOffEnabled = false
    @State private var proximityAutoOffMinutes = 30
    @State private var proximityAutoOffCustomText = "30"
    @State private var proximityAutoOffDeadline: Date?
    @State private var proximityAutoOffStatus = ""
    @State private var proximityAutoOffTask: Task<Void, Never>?
    @State private var pendingAutoLockTask: Task<Void, Never>?
    @State private var awaitingProximityLockConfirmation = false
    @State private var lastLockSoundCount: Int?

    // Önizleme durumları (henüz araca bağlı değil)
    @State private var sentryMode = true
    @State private var valetMode = false
    @State private var ambientColor = ToggTheme.teal
    @State private var sunroofOpen = false
    @State private var climateOn = false
    @State private var climateKnown = false
    @State private var climateStatusAt: Date?
    @State private var climateBusy = false
    @State private var climateNote: String?
    @State private var climatePending: Bool?
    @State private var targetTemperature = 22.0
    @State private var chargeStartPercent = 20.0
    @State private var chargeTargetPercent = 80.0
    @State private var chargeStartInitialized = false
    @AppStorage("toqdas.chargeCapacityKWh") private var chargeCapacityKWh = 88.5
    @AppStorage("toqdas.chargePricePerKWh") private var chargePricePerKWh = 10.0

    private var battery: Int { Int((telemetry?.batteryPercent ?? 0).rounded()) }
    private var range: Int { Int((telemetry?.rangeKM ?? 0).rounded()) }
    private var chargeEstimate: ChargingEstimate {
        ChargingEstimate.calculate(
            capacityKWh: chargeCapacityKWh,
            startPercent: chargeStartPercent,
            targetPercent: chargeTargetPercent,
            pricePerKWh: chargePricePerKWh
        )
    }
    private var batteryColor: Color {
        if battery > 50 { return ToggTheme.green }
        if battery > 20 { return ToggTheme.orange }
        return ToggTheme.red
    }
    private var vehicleBadge: String { vehicle.model.isEmpty ? "T10X" : vehicle.model }
    private var chargingLabel: String {
        guard let raw = telemetry?.chargingState else { return "—" }
        let lower = raw.lowercased()
        if lower.contains("not") { return "Şarj etmiyor" }
        if lower.contains("finish") || lower.contains("complete") { return "Tamamlandı" }
        if lower.contains("charg") { return "Şarj ediyor" }
        if lower.contains("schedule") { return "Planlı" }
        return raw
    }

    private var climateTargetKey: String { "toqdas.climateTarget.\(vehicle.vin)" }
    private var proximityEnabledKey: String { "toqdas.proximity.enabled.\(vehicle.vin)" }
    private var proximityNearKey: String { "toqdas.proximity.near.\(vehicle.vin)" }
    private var proximityFarKey: String { "toqdas.proximity.far.\(vehicle.vin)" }
    private var proximityProfileKey: String { "toqdas.proximity.profile.\(vehicle.vin)" }
    private var proximityAutoOffEnabledKey: String { "toqdas.proximity.autoOff.enabled.\(vehicle.vin)" }
    private var proximityAutoOffMinutesKey: String { "toqdas.proximity.autoOff.minutes.\(vehicle.vin)" }
    private var proximityAutoOffCustomKey: String { "toqdas.proximity.autoOff.custom.\(vehicle.vin)" }
    private var proximityAutoOffDeadlineKey: String { "toqdas.proximity.autoOff.deadline.\(vehicle.vin)" }
    private var proximityCalibration: ProximityCalibration? {
        guard let near = proximityNearSample, let far = proximityFarSample else { return nil }
        return ProximityCalibration(nearSample: near, farSample: far)
    }
    private var climateTemperatureText: String { String(format: "%.1f°C", targetTemperature) }
    private var displayClimateOn: Bool { climatePending ?? climateOn }
    private var climateStatusFresh: Bool {
        guard climateKnown, let measuredAt = climateStatusAt else { return false }
        return Date().timeIntervalSince(measuredAt) < 90
    }

    var body: some View {
        ZStack {
            ToggTheme.background.ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        DashboardHeader(
                        email: model.api.accountEmail() ?? "Togg ID",
                        vehicle: vehicle,
                        badge: vehicleBadge,
                        connected: telemetry != nil,
                        updatedAt: updatedAt,
                        location: telemetry?.coordinateText,
                        busy: busy,
                        vehicles: model.vehicles,
                        selectedVin: vehicle.vin,
                        onSelectVehicle: { model.select($0) },
                        onRefresh: { Task { await refresh() } },
                        onOpenCommands: { showCommands = true },
                        onOpenService: { showService = true },
                        onOpenExperience: { showExperience = true },
                        onOpenAccount: { showAccount = true },
                        onOpenDetail: { showDetail = true },
                        onOpenDiscovery: { showDiscovery = true },
                        onLogout: { model.logout() },
                        themeName: $themeName,
                        layoutName: $layoutName
                    )

                    VehicleVisualCard(
                        battery: battery,
                        range: range,
                        batteryColor: batteryColor,
                        updatedAt: updatedAt,
                        lockState: ble.telemetry?.isLocked,
                        odometer: telemetry?.odometerKM,
                        outsideTemperature: telemetry?.outsideTemperatureC
                    )

                    switch tab {
                    case .overview: overviewTab
                    case .climate: climateTab
                    case .charging: chargingTab
                    case .health: healthTab
                    }

                    if let error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(ToggTheme.pink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
                .onAppear {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-scrollChargingCalculator") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            withAnimation { proxy.scrollTo("chargingCalculator", anchor: .top) }
                        }
                    }
                    #endif
                }
            }
        }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .toolbar(.hidden, for: .navigationBar)
        .task { await liveLoop() }
        .task { await climateLoop() }
        .task { await prefetchCertificate() }
        .task { loadProximitySettings() }
        .onReceive(ble.$state) { state in
            print("[BLE] state -> \(state.description)")
            handleBLEState(state)
        }
        .onReceive(ble.$rssi) { value in
            guard let value else { return }
            proximityRSSISamples.append(value)
            if proximityRSSISamples.count > 5 {
                proximityRSSISamples.removeFirst(proximityRSSISamples.count - 5)
            }
            processProximityRSSI(value)
        }
        .onReceive(ble.$lastEvent) { event in
            guard proximityEnabled,
                  event.contains("araç durumuyla doğrulandı") || event.contains("kilit değişikliği doğrulanamadı") else { return }
            proximityStatus = event
        }
        .onReceive(ble.$lockConfirmationCount) { count in
            guard let previous = lastLockSoundCount else {
                lastLockSoundCount = count
                return
            }
            guard count > previous else { return }
            lastLockSoundCount = count
            LockConfirmationSound.playDoubleBeep()
            if awaitingProximityLockConfirmation {
                awaitingProximityLockConfirmation = false
                pendingAutoLockTask?.cancel()
                pendingAutoLockTask = nil
                startProximityAutoOffTimer()
            }
        }
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-openDriveExperience") {
                showExperience = true
            }
            if ProcessInfo.processInfo.arguments.contains("-openChargingTab") {
                tab = .charging
            }
            if ProcessInfo.processInfo.arguments.contains("-autoDigitalKey"), ble.state.isDisconnected {
                keepBLEConnected = true
                ble.start(vin: vehicle.vin)
            }
        }
        #endif
        .onChange(of: targetTemperature) { value in
            UserDefaults.standard.set(value, forKey: climateTargetKey)
        }
        .onChange(of: proximityProfile) { profile in
            UserDefaults.standard.set(profile.rawValue, forKey: proximityProfileKey)
            if !proximityEnabled, let calibration = proximityCalibration, calibration.isValid {
                proximityGate = ProximityGate(calibration: calibration, profile: profile)
            }
        }
        .onChange(of: proximityAutoOffMinutes) { value in
            UserDefaults.standard.set(value, forKey: proximityAutoOffMinutesKey)
        }
        .onChange(of: proximityAutoOffCustomText) { value in
            if let minutes = Int(value), (1...1440).contains(minutes) {
                UserDefaults.standard.set(minutes, forKey: proximityAutoOffCustomKey)
            }
        }
        .onChange(of: telemetry?.batteryPercent) { value in
            guard !chargeStartInitialized, let value, value.isFinite else { return }
            chargeStartInitialized = true
            let start = min(100, max(0, value.rounded()))
            chargeStartPercent = start
            if chargeTargetPercent < start { chargeTargetPercent = start }
        }
        .onChange(of: chargeStartPercent) { value in
            if value > chargeTargetPercent { chargeTargetPercent = value }
        }
        .onChange(of: chargeTargetPercent) { value in
            if value < chargeStartPercent { chargeStartPercent = value }
        }
        .refreshable { await refresh() }
        .alert(item: $alert) { item in
            switch item {
            case .notice(let text):
                return Alert(
                    title: Text("Henüz bağlı değil"),
                    message: Text(text),
                    dismissButton: .default(Text("Tamam"))
                )
            case .confirm(let command):
                return Alert(
                    title: Text("Komut gönderilsin mi?"),
                    message: Text(command.detail),
                    primaryButton: .destructive(Text("Gönder")) { send(command) },
                    secondaryButton: .cancel(Text("Vazgeç"))
                )
            }
        }
        .confirmationDialog(
            "Yakınlık otomasyonu açılsın mı?",
            isPresented: $showProximityConfirmation,
            titleVisibility: .visible
        ) {
            Button("Etkinleştir", role: .destructive) { setProximityEnabled(true) }
            Button("Vazgeç", role: .cancel) { }
        } message: {
            Text("Uygulama ekrandayken iki kararlı RSSI ölçümüne göre kilidi otomatik açıp kilitleyebilir. Arka planda çalışması garanti edilmez.")
        }
        .sheet(isPresented: $showCommands) {
            NavigationStack {
                CommandView(vehicle: vehicle, api: model.api)
                    .environmentObject(ble)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Kapat") { showCommands = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showDiscovery) {
            NavigationStack {
                DiscoveryView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Kapat") { showDiscovery = false }
                        }
                    }
            }
        }
        .navigationDestination(isPresented: $showDetail) {
            VehicleDetail(vehicle: vehicle, api: model.api)
        }
        .navigationDestination(isPresented: $showService) {
            ServiceView(vehicle: vehicle, api: model.api)
        }
        .navigationDestination(isPresented: $showExperience) {
            DriveExperienceView(vehicle: vehicle, api: model.api)
        }
        .navigationDestination(isPresented: $showStations) {
            ChargingStationsView()
        }
        .navigationDestination(isPresented: $showAccount) {
            AccountCenterView(api: model.api)
        }
    }

    // MARK: - Sekmeler

    private var overviewTab: some View {
        let layout = DashboardLayoutStyle(rawValue: layoutName) ?? .classic
        return VStack(spacing: 16) {
            bleSecurityBanner
            bleCard
            if layout != .minimal { proximityCard }
            if layout == .sport { quickActions }
            if layout != .minimal {
                PremiumControlsSection(
                    sentryMode: $sentryMode,
                    valetMode: $valetMode,
                    ambientColor: $ambientColor,
                    sunroofOpen: $sunroofOpen,
                    onWindowCommand: requestWindowCommand
                )
            }
            if layout != .sport { quickActions }
            chargingOverviewLink
        }
    }

    private var climateTab: some View {
        VStack(spacing: 16) {
            ClimateCard(
                isOn: displayClimateOn,
                known: climateStatusFresh,
                temperature: $targetTemperature,
                busy: climateBusy,
                note: climateNote,
                onToggle: { Task { await toggleClimate() } },
                onApplyTemperature: { Task { await applyClimateTemperature() } }
            )
        }
    }

    private var chargingTab: some View {
        VStack(spacing: 16) {
            chargingCard
            chargingCalculator
            Button { showExperience = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 15)).foregroundStyle(ToggTheme.teal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Şarj ve Yolculuk Geçmişi")
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        Text("Togg Drive Experience kayıtları")
                            .font(.system(size: 10)).foregroundStyle(ToggTheme.muted)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(ToggTheme.muted)
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 16).fill(ToggTheme.surfaceVariant))
            }
            .buttonStyle(.plain)
            trugoStations
        }
    }

    private var healthTab: some View {
        VehicleHealthCard(
            auxiliaryBattery: telemetry?.auxiliaryBatteryPercent,
            tires: telemetry?.tires ?? [],
            insideTemperature: telemetry?.insideTemperatureC,
            brakeWarning: telemetry?.brakeWarning,
            engineWarning: telemetry?.engineWarning,
            driveMode: telemetry?.driveModeText,
            chargingState: chargingLabel,
            updatedAt: updatedAt
        )
    }

    // MARK: - Bluetooth

    private var bleCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(bleStatusColor.opacity(0.2)).frame(width: 38, height: 38)
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 17)).foregroundStyle(bleStatusColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bluetooth Dijital Anahtar")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    Text(ble.state.description)
                        .font(.system(size: 12)).foregroundStyle(ToggTheme.muted)
                }
                Spacer()
                Circle().fill(bleStatusColor).frame(width: 9, height: 9)
            }

            if !ble.lastEvent.isEmpty {
                Text(ble.lastEvent)
                    .font(.caption2).foregroundStyle(ToggTheme.muted).lineLimit(2)
            }

            if let rssi = ble.rssi {
                Text("Bağlantı sinyali: \(rssi) dBm")
                    .font(.system(size: 9)).foregroundStyle(ToggTheme.muted)
            }

            if ble.needsRepair {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Eşleşme sıfırlanmalı", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(ToggTheme.orange)
                    Text("Araç, iPhone'un eşleşme bilgisini sildi. iPhone'da Ayarlar > Bluetooth'tan aracı unut; araç ekranından telefonu kaldır. İki cihazı yeniden başlatıp buradan tekrar bağlan.")
                        .font(.system(size: 10)).foregroundStyle(ToggTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(ToggTheme.orange.opacity(0.12)))
            }

            if let telemetry = ble.telemetry {
                HStack(spacing: 10) {
                    statusPill(icon: telemetry.isLocked == false ? "lock.open.fill" : "lock.fill",
                               text: telemetry.lockText,
                               color: lockStatusColor(telemetry))
                    statusPill(icon: "car.side.rear.open",
                               text: telemetry.trunkAjar == 1 ? "Bagaj açık" : "Bagaj kapalı",
                               color: ToggTheme.teal)
                }

                if telemetry.hasDoorReadings {
                    HStack(spacing: 8) {
                        ForEach(0..<4, id: \.self) { index in
                            doorTile(index: index, open: telemetry.isDoorOpen(index) ?? false)
                        }
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: "power.circle.fill")
                        .font(.system(size: 13)).foregroundStyle(powerStateColor(telemetry))
                    Text("Güç durumu")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(ToggTheme.muted)
                    Spacer()
                    Text(telemetry.powerStateText)
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(powerStateColor(telemetry))
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 10).fill(ToggTheme.surfaceVariant))
            }

            HStack(spacing: 10) {
                Button { toggleConnection() } label: {
                    Label(connectTitle,
                          systemImage: ble.state.isDisconnected || ble.state.isFailed
                            ? "antenna.radiowaves.left.and.right" : "xmark.circle")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(RoundedRectangle(cornerRadius: 14).fill(ToggTheme.teal))
                }
                .buttonStyle(.plain)

                Button { Task { await authenticateBLE() } } label: {
                    HStack(spacing: 6) {
                        if authBusy {
                            ProgressView().tint(.white).scaleEffect(0.7)
                        } else {
                            Image(systemName: "key.fill")
                        }
                        Text(ble.state.isReady ? "Anahtar hazır" : "Sertifikayı sun")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(RoundedRectangle(cornerRadius: 14).fill(ToggTheme.surfaceVariant))
                }
                .buttonStyle(.plain)
                .disabled(!(ble.state.isCertificate || ble.state.isChallenge) || authBusy)
            }

            if !ble.phonePublicKeyHex.isEmpty || !ble.carPublicKeyHex.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    if !ble.phonePublicKeyHex.isEmpty {
                        Text("Telefon anahtarı: \(ble.phonePublicKeyHex.prefix(16))…")
                    }
                    if !ble.carPublicKeyHex.isEmpty {
                        Text("Araç anahtarı: \(ble.carPublicKeyHex.prefix(16))…")
                    }
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(ToggTheme.muted)
            }

            Button { showCommands = true } label: {
                HStack {
                    Text("Ayrıntılı komutlar ve kanallar")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 11))
                }
                .foregroundStyle(ToggTheme.teal)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .toggCardBackground()
    }

    private var proximityCard: some View {
        let calibration = proximityCalibration
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Yakınlıkla Kapı Kilidi", systemImage: "dot.radiowaves.left.and.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { proximityEnabled },
                    set: { enabled in
                        if enabled {
                            guard calibration?.isValid == true else {
                                proximityStatus = "Önce yakın ve uzak RSSI ölçümü yapın."
                                return
                            }
                            showProximityConfirmation = true
                        } else {
                            setProximityEnabled(false)
                        }
                    }
                ))
                .labelsHidden()
                .tint(ToggTheme.teal)
                .disabled(!proximityEnabled && calibration?.isValid != true)
            }

            Text(proximityStatus)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(proximityEnabled ? ToggTheme.teal : ToggTheme.muted)

            HStack(spacing: 10) {
                Button { captureProximitySample(isNear: true) } label: {
                    Label("Yakında ölç", systemImage: "figure.walk")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(RoundedRectangle(cornerRadius: 12).fill(ToggTheme.teal))
                }
                .buttonStyle(.plain)
                .disabled(proximityEnabled || !ble.state.isReady || ble.rssi == nil)

                Button { captureProximitySample(isNear: false) } label: {
                    Label("Uzakta ölç", systemImage: "figure.walk.departure")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(RoundedRectangle(cornerRadius: 12).fill(ToggTheme.surfaceVariant))
                }
                .buttonStyle(.plain)
                .disabled(proximityEnabled || !ble.state.isReady || ble.rssi == nil)
            }

            Picker("Tepki profili", selection: $proximityProfile) {
                ForEach(ProximityProfile.allCases) { profile in
                    Text(profile.title).tag(profile)
                }
            }
            .pickerStyle(.menu)
            .disabled(proximityEnabled)
            .tint(ToggTheme.teal)
            Text(proximityProfile.explanation)
                .font(.system(size: 10))
                .foregroundStyle(proximityProfile == .fast || proximityProfile == .aggressive
                                 ? ToggTheme.orange : ToggTheme.muted)

            Toggle("Kilit doğrulandıktan sonra otomasyonu kapat", isOn: Binding(
                get: { proximityAutoOffEnabled },
                set: { setProximityAutoOffEnabled($0) }
            ))
            .font(.system(size: 11, weight: .medium))
            .tint(ToggTheme.teal)

            if proximityAutoOffEnabled {
                Picker("Kapatma süresi", selection: $proximityAutoOffMinutes) {
                    Text("5 dakika").tag(5)
                    Text("15 dakika").tag(15)
                    Text("30 dakika").tag(30)
                    Text("45 dakika").tag(45)
                    Text("1 saat").tag(60)
                    Text("Özel").tag(0)
                }
                .pickerStyle(.menu)
                .tint(ToggTheme.teal)

                if proximityAutoOffMinutes == 0 {
                    HStack {
                        Text("Özel süre (dakika)")
                            .font(.system(size: 10)).foregroundStyle(ToggTheme.muted)
                        TextField("30", text: $proximityAutoOffCustomText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 72)
                    }
                }

                if !proximityAutoOffStatus.isEmpty {
                    Text(proximityAutoOffStatus)
                        .font(.system(size: 10))
                        .foregroundStyle(ToggTheme.muted)
                }
                Text("Sayaç ilk doğrulanmış otomatik kilitten sonra başlar. Süre dolunca araca komut gönderilmez; iOS uygulamayı arka planda askıya alırsa kapanma gecikebilir.")
                    .font(.system(size: 9))
                    .foregroundStyle(ToggTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let near = proximityNearSample, let far = proximityFarSample {
                Text("Yakın: \(near) dBm · Uzak: \(far) dBm")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(ToggTheme.muted)
                if let calibration, calibration.isValid,
                   let nearThreshold = calibration.nearThreshold(margin: proximityProfile.thresholdMargin),
                   let farThreshold = calibration.farThreshold(margin: proximityProfile.thresholdMargin) {
                    Text("Açma eşiği ≥ \(nearThreshold) dBm · Kilitleme eşiği ≤ \(farThreshold) dBm")
                        .font(.system(size: 10))
                        .foregroundStyle(ToggTheme.muted)
                } else {
                    Text("Ölçümler arasında en az 14 dB fark olmalı; aynı telefon konumuyla yeniden ölçün.")
                        .font(.system(size: 10))
                        .foregroundStyle(ToggTheme.orange)
                }
            } else {
                Text("Önce araç yanında, sonra araçtan birkaç metre uzakta ölçüm alın.")
                    .font(.system(size: 10))
                    .foregroundStyle(ToggTheme.muted)
            }

            Text("Yalnızca uygulama ekrandayken çalışır. Kilit komutları için araç bağlantısının ve güncel araç durumunun hazır olması gerekir.")
                .font(.system(size: 10))
                .foregroundStyle(ToggTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text("Tepki profilleri iOS RSSI örnekleme hızına göre uyarlanmıştır; Android filtresinin birebir kopyası değildir.")
                .font(.system(size: 9))
                .foregroundStyle(ToggTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .toggCardBackground()
    }

    @ViewBuilder
    private var bleSecurityBanner: some View {
        if ble.state.isReady,
           let state = ble.telemetry,
           Date().timeIntervalSince(state.receivedAt) < 15,
           let warning = state.securityWarning {
            VStack(alignment: .leading, spacing: 5) {
                Label("Araç güvenlik uyarısı", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(ToggTheme.pink)
                Text(warning)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Uyarı güncel, imzalı BLE araç durumuna dayanıyor.")
                    .font(.system(size: 10))
                    .foregroundStyle(ToggTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(ToggTheme.pink.opacity(0.14)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(ToggTheme.pink.opacity(0.35), lineWidth: 1))
        }
    }

    private var bleStatusColor: Color {
        if ble.state.isReady { return ToggTheme.green }
        if ble.state.isFailed { return ToggTheme.pink }
        if ble.state.isDisconnected { return ToggTheme.muted }
        return ToggTheme.orange
    }

    private var connectTitle: String {
        if ble.state.isDisconnected { return "Araç servisine bağlan" }
        if ble.state.isFailed { return "Yeniden bağlan" }
        return "Bağlantıyı kes"
    }

    private func statusPill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11))
            Text(text).font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(color.opacity(0.15)))
    }

    private func doorTile(index: Int, open: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: open ? "door.left.hand.open" : "door.left.hand.closed")
                .font(.system(size: 14)).foregroundStyle(open ? ToggTheme.pink : ToggTheme.green)
            Text("Kapı \(index + 1)")
                .font(.system(size: 9, weight: .semibold)).foregroundStyle(ToggTheme.muted)
            Text(open ? "Açık" : "Kapalı")
                .font(.system(size: 10, weight: .bold)).foregroundStyle(open ? ToggTheme.pink : ToggTheme.green)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(ToggTheme.surfaceVariant))
    }

    private func lockStatusColor(_ telemetry: BleTelemetry) -> Color {
        switch telemetry.isLocked {
        case true: return ToggTheme.green
        case false: return ToggTheme.pink
        case nil: return ToggTheme.muted
        }
    }

    private func powerStateColor(_ telemetry: BleTelemetry) -> Color {
        switch telemetry.powerState {
        case 4: return ToggTheme.green
        case 3: return ToggTheme.orange
        case 2: return ToggTheme.teal
        default: return ToggTheme.muted
        }
    }

    private func toggleConnection() {
        if ble.state.isDisconnected || ble.state.isFailed {
            reconnectTask?.cancel()
            reconnectTask = nil
            reconnectAttempts = 0
            autoKeyStarted = false
            keepBLEConnected = true
            ble.start(vin: vehicle.vin)
        } else {
            keepBLEConnected = false
            reconnectTask?.cancel()
            reconnectTask = nil
            stableConnectionTask?.cancel()
            stableConnectionTask = nil
            ble.disconnect()
        }
    }

    @MainActor
    private func loadProximitySettings() {
        if let savedProfile = UserDefaults.standard.string(forKey: proximityProfileKey),
           let profile = ProximityProfile(rawValue: savedProfile) {
            proximityProfile = profile
        }
        proximityAutoOffEnabled = UserDefaults.standard.bool(forKey: proximityAutoOffEnabledKey)
        if UserDefaults.standard.object(forKey: proximityAutoOffMinutesKey) != nil {
            proximityAutoOffMinutes = UserDefaults.standard.integer(forKey: proximityAutoOffMinutesKey)
        }
        if let custom = UserDefaults.standard.object(forKey: proximityAutoOffCustomKey) as? Int {
            proximityAutoOffCustomText = String(custom)
        }
        proximityAutoOffDeadline = UserDefaults.standard.object(forKey: proximityAutoOffDeadlineKey) as? Date
        if !proximityAutoOffEnabled {
            proximityAutoOffDeadline = nil
            UserDefaults.standard.removeObject(forKey: proximityAutoOffDeadlineKey)
        }
        proximityNearSample = UserDefaults.standard.object(forKey: proximityNearKey) as? Int
        proximityFarSample = UserDefaults.standard.object(forKey: proximityFarKey) as? Int
        let requested = UserDefaults.standard.bool(forKey: proximityEnabledKey)
        if requested, proximityAutoOffEnabled,
           let deadline = proximityAutoOffDeadline,
           ProximityAutoOffPolicy.isExpired(deadline, now: Date()) {
            UserDefaults.standard.set(false, forKey: proximityEnabledKey)
            UserDefaults.standard.removeObject(forKey: proximityAutoOffDeadlineKey)
            proximityAutoOffDeadline = nil
            proximityEnabled = false
            proximityAutoOffStatus = "Süre doldu; otomasyon kapatıldı, komut gönderilmedi."
            proximityStatus = proximityAutoOffStatus
            return
        }
        guard requested, let calibration = proximityCalibration, calibration.isValid else {
            proximityEnabled = false
            ble.setProximityRSSIPollInterval(nil)
            UserDefaults.standard.set(false, forKey: proximityEnabledKey)
            proximityStatus = "Ölçüm bekleniyor"
            return
        }
        proximityEnabled = true
        proximityGate = ProximityGate(calibration: calibration, profile: proximityProfile)
        ble.setProximityRSSIPollInterval(proximityProfile.pollInterval)
        proximityStatus = "Etkin; araç bağlantısı aranıyor"
        if proximityAutoOffEnabled, let deadline = proximityAutoOffDeadline {
            scheduleProximityAutoOff(deadline: deadline)
        } else if proximityAutoOffEnabled {
            proximityAutoOffStatus = "Sayaç ilk doğrulanmış otomatik kilitlemeden sonra başlar."
        }
        keepBLEConnected = true
        if ble.state.isDisconnected || ble.state.isFailed {
            ble.start(vin: vehicle.vin)
        }
    }

    @MainActor
    private func captureProximitySample(isNear: Bool) {
        guard ble.state.isReady, let current = ble.rssi else {
            proximityStatus = "Ölçüm için dijital anahtar hazır ve bağlı olmalı."
            return
        }
        let recent = Array(proximityRSSISamples.suffix(3))
        let values = recent.isEmpty ? [current] : recent
        let sample = Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
        if isNear {
            proximityNearSample = sample
            UserDefaults.standard.set(sample, forKey: proximityNearKey)
            proximityStatus = "Yakın ölçüm kaydedildi: \(sample) dBm"
        } else {
            proximityFarSample = sample
            UserDefaults.standard.set(sample, forKey: proximityFarKey)
            proximityStatus = "Uzak ölçüm kaydedildi: \(sample) dBm"
        }

        if let calibration = proximityCalibration, calibration.isValid {
            proximityGate = ProximityGate(calibration: calibration, profile: proximityProfile)
            if proximityEnabled {
                proximityStatus = "Eşikler güncellendi; yakınlık izleniyor."
            }
        } else if proximityNearSample != nil, proximityFarSample != nil {
            setProximityEnabled(false)
            proximityStatus = "Ölçüm farkı yetersiz. Yakın/uzak arasında en az 14 dB olmalı."
        }
    }

    @MainActor
    private func setProximityEnabled(_ enabled: Bool) {
        if !enabled {
            proximityEnabled = false
            proximityGate = nil
            ble.setProximityRSSIPollInterval(nil)
            proximityAutoOffTask?.cancel()
            proximityAutoOffTask = nil
            pendingAutoLockTask?.cancel()
            pendingAutoLockTask = nil
            awaitingProximityLockConfirmation = false
            proximityAutoOffDeadline = nil
            UserDefaults.standard.removeObject(forKey: proximityAutoOffDeadlineKey)
            UserDefaults.standard.set(false, forKey: proximityEnabledKey)
            proximityStatus = "Kapalı"
            return
        }
        guard let calibration = proximityCalibration, calibration.isValid else {
            proximityEnabled = false
            proximityStatus = "Önce geçerli yakın/uzak ölçümü yapın."
            return
        }
        proximityEnabled = true
        UserDefaults.standard.set(true, forKey: proximityEnabledKey)
        proximityGate = ProximityGate(calibration: calibration, profile: proximityProfile)
        ble.setProximityRSSIPollInterval(proximityProfile.pollInterval)
        proximityAutoOffDeadline = nil
        UserDefaults.standard.removeObject(forKey: proximityAutoOffDeadlineKey)
        proximityAutoOffTask?.cancel()
        proximityAutoOffTask = nil
        awaitingProximityLockConfirmation = false
        pendingAutoLockTask?.cancel()
        pendingAutoLockTask = nil
        if proximityAutoOffEnabled {
            proximityAutoOffStatus = "Sayaç ilk doğrulanmış otomatik kilitlemeden sonra başlar."
        }
        proximityStatus = "Etkin; iki kararlı RSSI ölçümü bekleniyor."
        keepBLEConnected = true
        if ble.state.isDisconnected || ble.state.isFailed {
            reconnectAttempts = 0
            autoKeyStarted = false
            ble.start(vin: vehicle.vin)
        } else if ble.state.isCertificate, !authBusy {
            autoKeyStarted = false
            Task { await authenticateBLE() }
        }
    }

    @MainActor
    private func setProximityAutoOffEnabled(_ enabled: Bool) {
        proximityAutoOffEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: proximityAutoOffEnabledKey)
        proximityAutoOffTask?.cancel()
        proximityAutoOffTask = nil
        guard enabled else {
            pendingAutoLockTask?.cancel()
            pendingAutoLockTask = nil
            awaitingProximityLockConfirmation = false
            proximityAutoOffDeadline = nil
            UserDefaults.standard.removeObject(forKey: proximityAutoOffDeadlineKey)
            proximityAutoOffStatus = ""
            return
        }
        if let deadline = proximityAutoOffDeadline, deadline > Date() {
            scheduleProximityAutoOff(deadline: deadline)
        } else {
            proximityAutoOffDeadline = nil
            UserDefaults.standard.removeObject(forKey: proximityAutoOffDeadlineKey)
            proximityAutoOffStatus = "Sayaç ilk doğrulanmış otomatik kilitlemeden sonra başlar."
        }
    }

    private var effectiveProximityAutoOffMinutes: Int {
        if proximityAutoOffMinutes == 0 {
            guard let value = Int(proximityAutoOffCustomText), ProximityAutoOffPolicy.allowedMinutes.contains(value) else { return 30 }
            return value
        }
        return ProximityAutoOffPolicy.allowedMinutes.contains(proximityAutoOffMinutes) ? proximityAutoOffMinutes : 30
    }

    @MainActor
    private func startProximityAutoOffTimer() {
        guard proximityEnabled, proximityAutoOffEnabled else { return }
        if expireProximityAutoOffIfNeeded() { return }
        // Android behavior: start once after the first verified auto-lock; later
        // lock/unlock cycles do not extend the user's selected time window.
        guard proximityAutoOffDeadline == nil else { return }
        let minutes = effectiveProximityAutoOffMinutes
        guard let deadline = ProximityAutoOffPolicy.deadline(startedAt: Date(), durationMinutes: minutes) else { return }
        proximityAutoOffDeadline = deadline
        UserDefaults.standard.set(deadline, forKey: proximityAutoOffDeadlineKey)
        proximityAutoOffStatus = "Doğrulanmış otomatik kilitten sonra \(minutes) dakika sayılıyor."
        ble.recordDiagnostic("Otomatik kilit doğrulandı; \(minutes) dakika sonra yakınlık kapanacak")
        scheduleProximityAutoOff(deadline: deadline)
    }

    @MainActor
    private func scheduleProximityAutoOff(deadline: Date) {
        proximityAutoOffTask?.cancel()
        let delay = max(0, deadline.timeIntervalSinceNow)
        proximityAutoOffTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            _ = expireProximityAutoOffIfNeeded()
        }
    }

    @MainActor
    @discardableResult
    private func expireProximityAutoOffIfNeeded() -> Bool {
        guard proximityEnabled, proximityAutoOffEnabled,
              let deadline = proximityAutoOffDeadline,
              ProximityAutoOffPolicy.isExpired(deadline, now: Date()) else { return false }

        ble.recordDiagnostic("Yakınlık süresi doldu; otomasyon pasife alındı, komut gönderilmedi")
        proximityAutoOffDeadline = nil
        UserDefaults.standard.removeObject(forKey: proximityAutoOffDeadlineKey)
        proximityAutoOffTask?.cancel()
        proximityAutoOffTask = nil
        pendingAutoLockTask?.cancel()
        pendingAutoLockTask = nil
        awaitingProximityLockConfirmation = false
        setProximityEnabled(false)
        keepBLEConnected = false
        reconnectTask?.cancel()
        reconnectTask = nil
        if !ble.state.isDisconnected { ble.disconnect() }
        proximityAutoOffStatus = "Süre doldu; otomasyon kapatıldı. Araca komut gönderilmedi."
        proximityStatus = proximityAutoOffStatus
        return true
    }

    @MainActor
    private func processProximityRSSI(_ rssi: Int) {
        if expireProximityAutoOffIfNeeded() { return }
        guard proximityEnabled, ble.state.isReady, var gate = proximityGate else { return }
        let transition = gate.update(rssi: rssi)
        proximityGate = gate
        guard let transition else { return }
        ble.recordDiagnostic(transition == .approached
                             ? "Yakınlık eşiği doğrulandı (\(rssi) dBm)"
                             : "Uzaklaşma eşiği doğrulandı (\(rssi) dBm)")

        guard let state = ble.telemetry,
              Date().timeIntervalSince(state.receivedAt) < 15,
              let isLocked = state.isLocked else {
            proximityStatus = "Araç kilit durumu güncel değil; otomatik komut gönderilmedi."
            ble.recordDiagnostic("Yakınlık eylemi atlandı: araç kilit telemetrisi güncel değil")
            return
        }
        guard state.powerState == 2 else {
            proximityStatus = "Araç bekleme durumunda değil; otomatik komut gönderilmedi."
            ble.recordDiagnostic("Yakınlık eylemi atlandı: araç bekleme durumunda değil")
            return
        }

        switch transition {
        case .approached:
            if isLocked {
                ble.unlock()
                proximityStatus = "Yakınlık algılandı; imzalı kilit açma komutu gönderildi."
                ble.recordDiagnostic("Yakınlık otomasyonu kilit açma isteği gönderdi")
            } else {
                proximityStatus = "Yakınlık algılandı; kapılar zaten açık."
            }
        case .departed:
            guard state.doors.count == 4, state.doors.allSatisfy({ $0 == 0 }) else {
                proximityStatus = "Uzaklık algılandı ancak kapılar kapalı doğrulanmadı; kilitleme yapılmadı."
                ble.recordDiagnostic("Yakınlık kilitlemesi atlandı: kapıların tümü kapalı değil/bilinmiyor")
                return
            }
            if !isLocked {
                if proximityAutoOffEnabled {
                    awaitingProximityLockConfirmation = true
                    pendingAutoLockTask?.cancel()
                    pendingAutoLockTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 30_000_000_000)
                        guard !Task.isCancelled, awaitingProximityLockConfirmation else { return }
                        awaitingProximityLockConfirmation = false
                        pendingAutoLockTask = nil
                        proximityAutoOffStatus = "Kilit telemetrisi doğrulanmadı; süre sayacı başlatılmadı."
                        ble.recordDiagnostic("Yakınlık kilidi doğrulanmadı; otomatik kapatma sayacı başlamadı")
                    }
                }
                ble.lock()
                proximityStatus = "Uzaklaşma algılandı; cam kapatma ve ardından kapı kilitleme akışı başlatıldı."
                ble.recordDiagnostic("Yakınlık otomasyonu cam kapatıp kilitleme isteği gönderdi")
            } else {
                proximityStatus = "Uzaklaşma algılandı; kapılar zaten kilitli."
            }
        }
    }

    @MainActor
    private func handleBLEState(_ state: BleConnection.State) {
        if state.isReady {
            hasAuthenticatedBLE = true
            if proximityEnabled { proximityStatus = "Bağlı; yakınlık izleniyor (uygulama ekranda kalmalı)." }
            stableConnectionTask?.cancel()
            stableConnectionTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 45_000_000_000)
                guard !Task.isCancelled, ble.state.isReady else { return }
                reconnectAttempts = 0
                stableConnectionTask = nil
            }
            return
        }

        if state.isDisconnected || state.isFailed {
            autoKeyStarted = false
            stableConnectionTask?.cancel()
            stableConnectionTask = nil
            guard keepBLEConnected, !ble.needsRepair else { return }
            scheduleBLEReconnect()
            return
        }

        let debugAutoKey = ProcessInfo.processInfo.arguments.contains("-autoDigitalKey")
        guard state.isCertificate,
              hasAuthenticatedBLE || proximityEnabled || debugAutoKey,
              !autoKeyStarted else { return }
        autoKeyStarted = true
        let overwrite = ProcessInfo.processInfo.arguments.contains("-overwriteOwner")
        print("[BLE] auto-auth triggering overwrite=\(overwrite)")
        Task { await authenticateBLE(overwriteOwner: overwrite) }
    }

    @MainActor
    private func scheduleBLEReconnect() {
        guard reconnectTask == nil else { return }
        reconnectAttempts += 1
        let exponent = min(reconnectAttempts - 1, 4)
        let delay = min(pow(2.0, Double(exponent)), 16.0)
        print("[BLE] reconnect scheduled attempt=\(reconnectAttempts) delay=\(delay)s")
        reconnectTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            reconnectTask = nil
            guard keepBLEConnected, !ble.needsRepair,
                  ble.state.isDisconnected || ble.state.isFailed else { return }
            ble.start(vin: vehicle.vin)
        }
    }

    @MainActor
    private func authenticateBLE(overwriteOwner: Bool = false) async {
        guard !authBusy else { return }
        authBusy = true
        error = nil
        defer { authBusy = false }
        do {
            try await ble.authenticate(vehicle: vehicle, api: model.api, overwriteOwner: overwriteOwner)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func send(_ command: DashboardCommand) {
        switch command {
        case .lock: ble.lock()
        case .unlock: ble.unlock()
        case .trunkOpen: ble.trunkOpen()
        case .trunkClose: ble.trunkClose()
        case .windowsOpen: ble.windowsOpen()
        case .windowsClose: ble.windowsClose()
        }
    }

    private func requestWindowCommand(_ command: DashboardCommand) {
        guard ble.state.isReady else {
            showCommands = true
            return
        }
        alert = .confirm(command)
    }

    // MARK: - Hızlı kontroller

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hızlı Araç Kontrolleri")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                QuickActionButton(
                    title: ble.telemetry?.isLocked.map { $0 ? "Kilitli" : "Açık" } ?? "Kapılar",
                    subtitle: "Kapılar",
                    icon: ble.telemetry?.isLocked == false ? "lock.open.fill" : "lock.fill",
                    active: ble.telemetry?.isLocked == false,
                    activeColor: ToggTheme.pink
                ) {
                    if ble.state.isReady, let locked = ble.telemetry?.isLocked {
                        alert = .confirm(locked ? .unlock : .lock)
                    } else {
                        showCommands = true
                    }
                }
                QuickActionButton(title: climateKnown ? (displayClimateOn ? "Açık" : "Kapalı") : "—",
                                  subtitle: "İklimlendirme", icon: "snowflake",
                                  active: displayClimateOn, activeColor: ToggTheme.cyan) {
                    Task { await toggleClimate() }
                }
                QuickActionButton(
                    title: ble.telemetry.map { $0.trunkAjar == 1 ? "Açık" : "Kapalı" } ?? "Bagaj",
                    subtitle: "Arka Bagaj",
                    icon: "car.side.rear.open",
                    active: ble.telemetry?.trunkAjar == 1,
                    activeColor: ToggTheme.teal
                ) {
                    if ble.state.isReady, let trunk = ble.telemetry?.trunkAjar {
                        alert = .confirm(trunk == 1 ? .trunkClose : .trunkOpen)
                    } else {
                        showCommands = true
                    }
                }
            }
        }
    }

    // MARK: - Şarj

    private var chargingCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(ToggTheme.green.opacity(0.2)).frame(width: 38, height: 38)
                    Image(systemName: "bolt.car.fill").foregroundStyle(ToggTheme.green)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Trugo Akıllı Şarj Yönetimi")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    Text(chargingLabel == "—" ? "Şarj durumu bilinmiyor" : chargingLabel)
                        .font(.system(size: 12)).foregroundStyle(ToggTheme.muted)
                }
                Spacer()
            }

            Text("Şarj başlatma/durdurma ve limit değiştirme araca bağlı değil. Enerji/ücret tahmini aşağıdaki hesaplayıcıdadır.")
                .font(.caption2).foregroundStyle(ToggTheme.muted)
        }
        .padding(20)
        .toggCardBackground()
    }

    private var chargingOverviewLink: some View {
        Button { tab = .charging } label: {
            HStack(spacing: 12) {
                Image(systemName: "bolt.car.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(ToggTheme.green)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Şarj ve istasyonlar")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Durum: \(chargingLabel) · tahmin ve geçmiş")
                        .font(.system(size: 10))
                        .foregroundStyle(ToggTheme.muted)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(ToggTheme.muted)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .toggCardBackground()
        }
        .buttonStyle(.plain)
    }

    private var chargingCalculator: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(ToggTheme.blue.opacity(0.18)).frame(width: 38, height: 38)
                    Image(systemName: "function").foregroundStyle(ToggTheme.blue)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Şarj Hesaplama")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    Text("Kapasite ve fiyat varsayımdır")
                        .font(.system(size: 12)).foregroundStyle(ToggTheme.muted)
                }
                Spacer()
            }

            percentRow(title: "Başlangıç doluluğu", value: $chargeStartPercent, range: 0...99)
            percentRow(title: "Hedef doluluk", value: $chargeTargetPercent, range: 1...100)

            VStack(spacing: 8) {
                assumptionRow(title: "Hesaplama kapasitesi", value: $chargeCapacityKWh,
                              range: 1...200, step: 0.1, unit: "kWh")
                assumptionRow(title: "Birim fiyat", value: $chargePricePerKWh,
                              range: 0...100, step: 0.1, unit: "₺/kWh")
            }

            VStack(spacing: 8) {
                HStack {
                    Text("Tahmini enerji").font(.system(size: 13)).foregroundStyle(ToggTheme.muted)
                    Spacer()
                    Text(chargeEstimate.energyText)
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(.white).monospacedDigit()
                }
                HStack {
                    Text("Tahmini ücret").font(.system(size: 13)).foregroundStyle(ToggTheme.muted)
                    Spacer()
                    Text(chargeEstimate.costText)
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(ToggTheme.teal).monospacedDigit()
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(ToggTheme.surfaceVariant))

            Text("Kapasite ve fiyat varsayımdır; şarj kayıpları hesaba katılmaz. Araçta şarj başlatmaz.")
                .font(.caption2).foregroundStyle(ToggTheme.muted)
        }
        .padding(20)
        .toggCardBackground()
        .id("chargingCalculator")
    }

    private func percentRow(title: String, value: Binding<Double>,
                            range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(ToggTheme.muted)
                Spacer()
                Text("%\(Int(value.wrappedValue.rounded()))")
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(ToggTheme.teal).monospacedDigit()
            }
            Slider(value: value, in: range, step: 1)
                .tint(ToggTheme.teal)
        }
    }

    private func assumptionRow(title: String, value: Binding<Double>,
                               range: ClosedRange<Double>, step: Double, unit: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 12)).foregroundStyle(ToggTheme.muted)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Text("\(ExperienceFormat.oneDecimal(value.wrappedValue)) \(unit)")
                .font(.system(size: 13, weight: .bold)).foregroundStyle(.white).monospacedDigit()
                .lineLimit(1)
            Stepper("", value: value, in: range, step: step)
                .labelsHidden()
                .scaleEffect(0.8)
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(ToggTheme.surfaceVariant))
    }

    private var trugoStations: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.car.fill").foregroundStyle(ToggTheme.teal)
                Text("En Yakın Trugo Şarj İstasyonları")
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
            }
            VStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 26)).foregroundStyle(ToggTheme.teal)
                Text("Yakındaki istasyonları gör")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                Text("Apple Maps üzerinden Trugo ve elektrikli araç şarj noktalarını haritada bul.")
                    .font(.caption).foregroundStyle(ToggTheme.muted).multilineTextAlignment(.center)
                Button { showStations = true } label: {
                    Label("Haritayı aç", systemImage: "map.fill")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(.black)
                        .padding(.horizontal, 16).frame(height: 38)
                        .background(Capsule().fill(ToggTheme.teal))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .toggCardBackground(20)
        }
    }

    // MARK: - Alt menü

    private var bottomBar: some View {
        HStack(spacing: 0) {
            ForEach(DashboardTab.allCases) { item in
                Button { tab = item } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.icon).font(.system(size: 20))
                        Text(item.title)
                            .font(.system(size: 10, weight: tab == item ? .bold : .regular))
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(tab == item ? ToggTheme.teal : ToggTheme.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(
            ToggTheme.surface
                .overlay(alignment: .top) {
                    Rectangle().fill(ToggTheme.outline.opacity(0.5)).frame(height: 1)
                }
        )
    }

    // MARK: - Veri

    @MainActor
    private func liveLoop() async {
        await refresh()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    /// Sertifikayı BLE bağlantısından önce hazırlar. Böylece Togg servisi
    /// yavaşladığında araç, API yanıtı beklenirken bağlantıyı düşürmez.
    @MainActor
    private func prefetchCertificate() async {
        guard let pair = try? PhoneKeyStore.keyPair(for: vehicle.vin) else { return }
        let hex = pair.publicKey.hexString
        if CertificateCache.load(vin: vehicle.vin, phonePublicKeyHex: hex) != nil { return }
        do {
            _ = try await model.api.ensureCertificate(vin: vehicle.vin, phonePublicKeyHex: hex)
            print("[CERT] prefetch complete")
        } catch is CancellationError {
            return
        } catch {
            print("[CERT] prefetch failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func climateLoop() async {
        loadClimateTarget()
        await refreshClimate()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard !Task.isCancelled else { return }
            await refreshClimate()
        }
    }

    @MainActor
    private func loadClimateTarget() {
        guard let stored = UserDefaults.standard.object(forKey: climateTargetKey) as? NSNumber else { return }
        let value = stored.doubleValue
        if (16...30).contains(value) {
            targetTemperature = value
        }
    }

    @MainActor
    private func refreshClimate() async {
        guard !climateBusy else { return }
        climateBusy = true
        defer { climateBusy = false }
        print("[CLIMATE] status query start vin=\(vehicle.vin)")
        do {
            let status = try await model.api.climateStatus(vin: vehicle.vin)
            climateOn = status.active
            climateKnown = true
            climateStatusAt = Date()
            let temperature = status.temperature.map { String($0) } ?? "unknown"
            print("[CLIMATE] status active=\(status.active) temperature=\(temperature)")
            if UserDefaults.standard.object(forKey: climateTargetKey) == nil,
               let temperature = status.temperature,
               (16...30).contains(temperature) {
                targetTemperature = temperature
            }
            climateNote = status.active ? "Klima açık · hedef \(climateTemperatureText)" : "Klima kapalı."
        } catch is CancellationError {
            return
        } catch {
            climateKnown = false
            climateStatusAt = nil
            climateNote = error.localizedDescription
            print("[CLIMATE] status query failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func toggleClimate() async {
        guard !climateBusy else { return }
        climateBusy = true
        defer { climateBusy = false }
        do {
            if !climateStatusFresh {
                climateNote = "Klima durumu okunuyor…"
                let status = try await model.api.climateStatus(vin: vehicle.vin)
                climateOn = status.active
                climateKnown = true
                climateStatusAt = Date()
                if UserDefaults.standard.object(forKey: climateTargetKey) == nil,
                   let temperature = status.temperature,
                   (16...30).contains(temperature) {
                    targetTemperature = temperature
                }
            }
            let desired = !climateOn
            climatePending = desired
            defer { climatePending = nil }
            climateNote = desired ? "Klima açılıyor…" : "Klima kapatılıyor…"
            let result = try await model.api.setClimate(
                vin: vehicle.vin,
                active: desired,
                temperature: targetTemperature
            )
            guard result.status == "COMPLETED" else {
                let status = result.status.isEmpty ? "YANITSIZ" : result.status
                let code = result.code.isEmpty ? "" : " · \(result.code)"
                climateNote = "Klima komutu \(status)\(code)"
                return
            }
            climateNote = "Araç yanıtı doğrulanıyor…"
            do {
                let confirmed = try await model.api.climateStatus(vin: vehicle.vin)
                climateOn = confirmed.active
                climateKnown = true
                climateStatusAt = Date()
                if confirmed.active == desired {
                    climateNote = desired ? "Klima açıldı." : "Klima kapatıldı."
                } else {
                    climateNote = "Komut tamamlandı; araç henüz \(desired ? "açık" : "kapalı") durumu bildirmedi."
                }
            } catch {
                climateKnown = false
                climateStatusAt = nil
                climateNote = "Komut tamamlandı; durum doğrulanamadı: \(error.localizedDescription)"
            }
        } catch is CancellationError {
            return
        } catch {
            climateNote = error.localizedDescription
        }
    }

    @MainActor
    private func applyClimateTemperature() async {
        guard !climateBusy else { return }
        if !climateStatusFresh {
            await refreshClimate()
        }
        guard climateStatusFresh, climateOn else {
            climateNote = "Hedef \(climateTemperatureText) kaydedildi; klima açıkken uygulanabilir."
            return
        }
        climateBusy = true
        defer { climateBusy = false }
        do {
            climateNote = "Hedef sıcaklık gönderiliyor…"
            let result = try await model.api.setClimate(
                vin: vehicle.vin,
                active: true,
                temperature: targetTemperature
            )
            if result.status == "COMPLETED" {
                climateNote = "Hedef sıcaklık \(climateTemperatureText) olarak uygulandı."
            } else {
                let status = result.status.isEmpty ? "YANITSIZ" : result.status
                let code = result.code.isEmpty ? "" : " · \(result.code)"
                climateNote = "Sıcaklık komutu \(status)\(code)"
            }
        } catch is CancellationError {
            return
        } catch {
            climateNote = error.localizedDescription
        }
    }

    @MainActor
    private func refresh() async {
        guard !busy else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let response = try await model.api.details(for: vehicle)
            let parsed = try VehicleTelemetry(data: Data(response.utf8))
            try Task.checkCancellation()
            telemetry = parsed
            updatedAt = parsed.vehicleUpdatedAt ?? Date()
        } catch is CancellationError {
            return
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Başlık

private struct DashboardHeader: View {
    let email: String
    let vehicle: Vehicle
    let badge: String
    let connected: Bool
    let updatedAt: Date?
    let location: String?
    let busy: Bool
    let vehicles: [Vehicle]
    let selectedVin: String?
    let onSelectVehicle: (Vehicle) -> Void
    let onRefresh: () -> Void
    let onOpenCommands: () -> Void
    let onOpenService: () -> Void
    let onOpenExperience: () -> Void
    let onOpenAccount: () -> Void
    let onOpenDetail: () -> Void
    let onOpenDiscovery: () -> Void
    let onLogout: () -> Void
    @Binding var themeName: String
    @Binding var layoutName: String

    private var telemetryIsFresh: Bool {
        guard let updatedAt else { return false }
        return Date().timeIntervalSince(updatedAt) < 300
    }

    private var telemetryColor: Color {
        telemetryIsFresh ? ToggTheme.green : ToggTheme.orange
    }

    private var telemetryLabel: String {
        telemetryIsFresh ? "Canlı Telemetri" : "Son Telemetri"
    }

    private var updatedText: String {
        guard let updatedAt else { return "• henüz okunmadı" }
        if Calendar.current.isDateInToday(updatedAt) {
            return "• \(updatedAt.formatted(date: .omitted, time: .shortened))"
        }
        return "• \(updatedAt.formatted(.dateTime.day().month(.abbreviated).hour().minute()))"
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 15)).foregroundStyle(ToggTheme.teal)
                    Text(email)
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(ToggTheme.teal)
                        .lineLimit(1)
                }
                Spacer()
                Text("Togg ID Aktif")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(ToggTheme.green)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(ToggTheme.green.opacity(0.15)))
            }

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("TRUMORE")
                            .font(.system(size: 22, weight: .black))
                            .tracking(2)
                            .foregroundStyle(ToggTheme.teal)
                        Text(badge)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(hex: 0x86F8F0))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(ToggTheme.tealContainer))
                    }
                    HStack(spacing: 4) {
                        Image(systemName: "car.side.fill")
                            .font(.system(size: 12)).foregroundStyle(ToggTheme.teal)
                        Text("\(vehicle.title) • \(vehicle.plate.isEmpty ? vehicle.vin : vehicle.plate)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ToggTheme.muted)
                            .lineLimit(1)
                    }
                }
                Spacer()
                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(connected ? (telemetryIsFresh ? ToggTheme.green : ToggTheme.orange) : ToggTheme.pink)
                            .frame(width: 7, height: 7)
                        Image(systemName: "wifi").font(.system(size: 12)).foregroundStyle(ToggTheme.teal)
                        Text(connected ? (telemetryIsFresh ? "Aracım Bağlı" : "Son Veri") : "Veri yok")
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Capsule().fill(ToggTheme.surfaceVariant))

                    Menu {
                        if vehicles.count > 1 {
                            Menu("Araç seç", systemImage: "car.2.fill") {
                                ForEach(vehicles) { item in
                                    Button {
                                        onSelectVehicle(item)
                                    } label: {
                                        if item.vin == selectedVin {
                                            Label(item.title, systemImage: "checkmark")
                                        } else {
                                            Text(item.title)
                                        }
                                    }
                                }
                            }
                            Divider()
                        }
                        Button("Araç detayı", systemImage: "info.circle") { onOpenDetail() }
                        Button("Servis kartı", systemImage: "wrench.and.screwdriver") { onOpenService() }
                        Button("Sürüş & şarj analizi", systemImage: "chart.xyaxis.line") { onOpenExperience() }
                        Button("Bildirimler & destek", systemImage: "bell.badge") { onOpenAccount() }
                        Button("Bluetooth komutları", systemImage: "key.horizontal") { onOpenCommands() }
                        Button("Bluetooth taraması", systemImage: "dot.radiowaves.left.and.right") { onOpenDiscovery() }
                        Picker("Renk teması", selection: $themeName) {
                            ForEach(ToggThemeStyle.allCases) { style in
                                Text(style.title).tag(style.rawValue)
                            }
                        }
                        Picker("Dashboard düzeni", selection: $layoutName) {
                            ForEach(DashboardLayoutStyle.allCases) { layout in
                                Text("\(layout.title) · \(layout.subtitle)").tag(layout.rawValue)
                            }
                        }
                        Divider()
                        Button("Çıkış yap", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { onLogout() }
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(ToggTheme.teal)
                            .frame(width: 32, height: 32)
                    }
                }
            }

            Button(action: onRefresh) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: telemetryIsFresh
                              ? "sensor.tag.radiowaves.forward.fill"
                              : "clock.arrow.circlepath")
                            .font(.system(size: 13)).foregroundStyle(telemetryColor)
                        Text(telemetryLabel)
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(telemetryColor)
                        Text(updatedText)
                            .font(.system(size: 11)).foregroundStyle(ToggTheme.muted)
                    }
                    Spacer()
                    if busy {
                        ProgressView().tint(ToggTheme.teal).scaleEffect(0.8)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "location.fill")
                                .font(.system(size: 11)).foregroundStyle(ToggTheme.teal)
                            Text(location ?? "Konum yok")
                                .font(.system(size: 10, weight: .medium)).foregroundStyle(.white)
                                .lineLimit(1).minimumScaleFactor(0.75)
                        }
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 12).fill(ToggTheme.surfaceVariant))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Araç kartı

private struct VehicleVisualCard: View {
    let battery: Int
    let range: Int
    let batteryColor: Color
    let updatedAt: Date?
    let lockState: Bool?
    let odometer: Double?
    let outsideTemperature: Double?

    private var lockBadge: (text: String, color: Color, icon: String) {
        switch lockState {
        case true: return ("KİLİTLİ", ToggTheme.green, "lock.fill")
        case false: return ("KİLİT AÇIK", ToggTheme.pink, "lock.open.fill")
        case nil: return ("KİLİT BİLİNMİYOR", ToggTheme.muted, "lock.fill")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: lockBadge.icon).font(.system(size: 14))
                    Text(lockBadge.text).font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(lockBadge.color)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 12).fill(lockBadge.color.opacity(0.15)))

                Spacer()

                Text(updatedAt.map { "Güncellendi \($0.formatted(date: .omitted, time: .shortened))" } ?? "Veri bekleniyor")
                    .font(.system(size: 10)).foregroundStyle(ToggTheme.muted)
            }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "gauge.with.dots.needle.50percent")
                            .font(.system(size: 17)).foregroundStyle(ToggTheme.teal)
                        Text("KALAN MENZİL")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(ToggTheme.muted)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(range > 0 ? "\(range)" : "—")
                            .font(.system(size: 44, weight: .black)).foregroundStyle(.white)
                        Text("KM")
                            .font(.system(size: 18, weight: .bold)).foregroundStyle(ToggTheme.teal)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill").font(.system(size: 18)).foregroundStyle(batteryColor)
                        Text(battery > 0 ? "%\(battery)" : "—")
                            .font(.system(size: 22, weight: .bold)).foregroundStyle(batteryColor)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(batteryColor.opacity(0.15))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(batteryColor.opacity(0.4), lineWidth: 1))
                    )
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(ToggTheme.surfaceVariant)
                    Capsule().fill(batteryColor)
                        .frame(width: geo.size.width * CGFloat(min(max(battery, 0), 100)) / 100)
                }
            }
            .frame(height: 8)

            HStack(spacing: 16) {
                HStack(spacing: 5) {
                    Image(systemName: "gauge")
                        .font(.system(size: 12)).foregroundStyle(ToggTheme.orange)
                    Text(odometer.map { "\($0.formatted(.number.precision(.fractionLength(0)))) km" } ?? "— km")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(ToggTheme.muted)
                }
                HStack(spacing: 5) {
                    Image(systemName: "thermometer.medium")
                        .font(.system(size: 12)).foregroundStyle(ToggTheme.cyan)
                    Text(outsideTemperature.map { "\(Int($0.rounded()))°C" } ?? "—°C")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(ToggTheme.muted)
                }
                Spacer()
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(colors: [ToggTheme.surfaceVariant, ToggTheme.surface],
                                   startPoint: .top, endPoint: .bottom)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(ToggTheme.outline.opacity(0.5), lineWidth: 1)
                )
        )
    }
}

// MARK: - Hızlı işlem düğmesi

private struct QuickActionButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let active: Bool
    let activeColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(active ? activeColor : ToggTheme.outline.opacity(0.3))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundStyle(active ? .black : .white)
                }
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(active ? activeColor : .white)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(ToggTheme.muted)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(active ? activeColor.opacity(0.18) : ToggTheme.surfaceVariant)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Premium kontroller

private struct PremiumControlsSection: View {
    @Binding var sentryMode: Bool
    @Binding var valetMode: Bool
    @Binding var ambientColor: Color
    @Binding var sunroofOpen: Bool
    let onWindowCommand: (DashboardCommand) -> Void

    private let palette: [(Color, String)] = [
        (ToggTheme.teal, "Turkuaz"),
        (ToggTheme.cyan, "Elektrik"),
        (Color(hex: 0xFF007A), "Magenta"),
        (Color(hex: 0x7000FF), "Mor"),
        (ToggTheme.yellow, "Altın")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Akıllı Konfor & Güvenlik Sistemleri")
                .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)

            HStack(spacing: 12) {
                modeCard(title: "Nöbetçi (Sentry) Güvenlik",
                         subtitle: sentryMode ? "Kameralar Aktif" : "Kapalı",
                         icon: "shield.lefthalf.filled",
                         isOn: $sentryMode, color: ToggTheme.green)
                modeCard(title: "Valet / Sürücü Sınırı",
                         subtitle: valetMode ? "Maks 70 km/h kilitli" : "Devre dışı",
                         icon: "key.fill",
                         isOn: $valetMode, color: ToggTheme.orange)
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "paintpalette.fill")
                        .font(.system(size: 16)).foregroundStyle(ambientColor)
                    Text("64 Renk Ambiyans Aydınlatma")
                        .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                }

                HStack(spacing: 10) {
                    ForEach(Array(palette.enumerated()), id: \.offset) { _, item in
                        Button { ambientColor = item.0 } label: {
                            Text(item.1)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(ambientColor == item.0 ? .black : .white)
                                .frame(maxWidth: .infinity).frame(height: 38)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(item.0.opacity(ambientColor == item.0 ? 0.9 : 0.25))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(ambientColor == item.0 ? .white : .clear, lineWidth: 2)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack(spacing: 10) {
                    windowButton(title: "Yan camları aç", subtitle: "İmzalı BLE komutu",
                                 icon: "rectangle.split.3x3.fill", color: ToggTheme.cyan) {
                        onWindowCommand(.windowsOpen)
                    }
                    windowButton(title: "Yan camları kapat", subtitle: "İmzalı BLE komutu",
                                 icon: "xmark", color: ToggTheme.teal) {
                        onWindowCommand(.windowsClose)
                    }
                }
                windowButton(title: "Panoramik cam tavan",
                             subtitle: sunroofOpen ? "Önizleme: açık" : "Önizleme: kapalı",
                             icon: "sun.max.fill", color: ToggTheme.teal) {
                    sunroofOpen.toggle()
                }
            }
            .padding(18)
            .toggCardBackground(24)

            Text("Yan cam komutları onay ister; araç cam konumunu BLE ile doğrulamıyor. Panoramik tavan, ambiyans ve güvenlik ayarları önizlemedir.")
                .font(.caption2).foregroundStyle(ToggTheme.muted)
        }
    }

    private func modeCard(title: String, subtitle: String, icon: String,
                          isOn: Binding<Bool>, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ZStack {
                    Circle().fill(isOn.wrappedValue ? color.opacity(0.2) : ToggTheme.surfaceVariant)
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(isOn.wrappedValue ? color : ToggTheme.muted)
                }
                Spacer()
                Toggle("", isOn: isOn).labelsHidden().tint(color)
            }
            Text(title)
                .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                .lineLimit(2).minimumScaleFactor(0.8)
            Text(subtitle)
                .font(.system(size: 10)).foregroundStyle(ToggTheme.muted)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(isOn.wrappedValue ? color.opacity(0.12) : ToggTheme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(isOn.wrappedValue ? color.opacity(0.5) : ToggTheme.outline.opacity(0.3), lineWidth: 1)
                )
        )
    }

    private func windowButton(title: String, subtitle: String, icon: String,
                              color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 16)).foregroundStyle(color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(subtitle).font(.system(size: 9)).foregroundStyle(ToggTheme.muted)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).fill(ToggTheme.surfaceVariant))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Klima

private struct ClimateCard: View {
    let isOn: Bool
    let known: Bool
    @Binding var temperature: Double
    let busy: Bool
    let note: String?
    let onToggle: () -> Void
    let onApplyTemperature: () -> Void

    private var subtitle: String {
        if busy { return "İşlem sürüyor…" }
        if !known { return "Durum bilinmiyor · dokunarak dene" }
        return isOn ? "Otomatik iklimlendirme aktif" : "Kapalı"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(isOn ? ToggTheme.cyan.opacity(0.2) : ToggTheme.surfaceVariant)
                            .frame(width: 36, height: 36)
                        Image(systemName: "snowflake")
                            .font(.system(size: 18))
                            .foregroundStyle(isOn ? ToggTheme.cyan : ToggTheme.muted)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Klima & İklimlendirme")
                            .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                        Text(subtitle)
                            .font(.system(size: 12)).foregroundStyle(ToggTheme.muted)
                    }
                }
                Spacer()
                Button(action: onToggle) {
                    ZStack(alignment: isOn ? .trailing : .leading) {
                        Capsule()
                            .fill(isOn ? ToggTheme.cyan : ToggTheme.outline.opacity(0.5))
                            .frame(width: 52, height: 30)
                        Circle()
                            .fill(.white)
                            .frame(width: 24, height: 24)
                            .padding(3)
                    }
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .opacity(busy ? 0.6 : 1)
            }

            HStack {
                circleButton("minus") { temperature = max(16, temperature - 0.5) }
                    .disabled(busy)
                Spacer()
                VStack(spacing: 2) {
                    Text(String(format: "%.1f°C", temperature))
                        .font(.system(size: 38, weight: .black))
                        .foregroundStyle(isOn ? ToggTheme.cyan : ToggTheme.muted)
                    Text("Hedef Sıcaklık")
                        .font(.system(size: 11)).foregroundStyle(ToggTheme.muted)
                }
                Spacer()
                circleButton("plus") { temperature = min(30, temperature + 0.5) }
                    .disabled(busy)
            }

            if isOn {
                Button(action: onApplyTemperature) {
                    Label("Sıcaklığı Uygula", systemImage: "thermometer.medium")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(ToggTheme.cyan)
                        )
                }
                .buttonStyle(.plain)
                .disabled(busy)
            } else {
                Text("Klima açılırken hedef \(String(format: "%.1f", temperature))°C uygulanır.")
                    .font(.caption2).foregroundStyle(ToggTheme.muted)
            }

            if let note {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(ToggTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("Komut Togg uzaktan kontrol servisine gönderilir; araç durumu ayrıca doğrulanır.")
                .font(.caption2).foregroundStyle(ToggTheme.muted)
        }
        .padding(20)
        .toggCardBackground()
    }

    private func circleButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Circle().fill(ToggTheme.surfaceVariant))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sağlık

private struct VehicleHealthCard: View {
    let auxiliaryBattery: Double?
    let tires: [TireReading]
    let insideTemperature: Double?
    let brakeWarning: Bool?
    let engineWarning: Bool?
    let driveMode: String?
    let chargingState: String
    let updatedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(ToggTheme.green.opacity(0.2)).frame(width: 38, height: 38)
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(ToggTheme.green)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Araç Sağlığı & Lastik Basınçları")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    Text(updatedAt.map { "Canlı API • \($0.formatted(date: .omitted, time: .shortened))" }
                         ?? "Canlı veri bekleniyor")
                        .font(.system(size: 12)).foregroundStyle(ToggTheme.muted)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Lastik Basınçları (TPMS - PSI)")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(ToggTheme.muted)
                HStack(spacing: 10) {
                    tireBox(.frontLeft)
                    tireBox(.frontRight)
                    tireBox(.rearLeft)
                    tireBox(.rearRight)
                }
            }

            HStack(spacing: 12) {
                statBox(title: "12 V Akü", value: auxiliaryBattery.map { "%\(Int($0.rounded()))" } ?? "—",
                        icon: "car.battery", color: ToggTheme.teal)
                statBox(title: "Şarj Durumu", value: chargingState,
                        icon: "bolt.circle", color: ToggTheme.cyan)
            }

            HStack(spacing: 12) {
                statBox(title: "İç Sıcaklık",
                        value: insideTemperature.map { "\(Int($0.rounded()))°C" } ?? "—",
                        icon: "thermometer.medium", color: ToggTheme.orange)
                statBox(title: "Sürüş Modu", value: driveMode ?? "—",
                        icon: "steeringwheel", color: ToggTheme.teal)
            }

            if brakeWarning != nil || engineWarning != nil {
                HStack(spacing: 12) {
                    warningBox(title: "Fren Uyarısı", warning: brakeWarning)
                    warningBox(title: "Motor Uyarısı", warning: engineWarning)
                }
            }

            Text("Lastik basınç/sıcaklıkları, 12 V akü, şarj durumu, iç sıcaklık, sürüş modu ve fren/motor uyarıları VehicleInfo API'sinden gösterilir. Lastik basıncı kPa'dan PSI'ye çevrilir; uyarı alanları yalnızca API'de dolu geldiğinde gösterilir. Batarya, menzil, kilometre ve dış sıcaklık üst araç kartındadır.")
                .font(.caption2).foregroundStyle(ToggTheme.muted)
        }
        .padding(20)
        .toggCardBackground()
    }

    private func tireBox(_ position: TirePosition) -> some View {
        let reading = tires.first { $0.position == position }
        return VStack(spacing: 4) {
            Image(systemName: "car.side.fill")
                .font(.system(size: 15)).foregroundStyle(ToggTheme.teal)
            Text(reading?.pressurePSI.map { String(format: "%.1f PSI", $0) } ?? "— PSI")
                .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(reading?.temperatureC.map { "\(Int($0.rounded()))°C" } ?? "—°C")
                .font(.system(size: 10)).foregroundStyle(ToggTheme.muted)
            Text(position.title).font(.system(size: 9)).foregroundStyle(ToggTheme.muted)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14).fill(ToggTheme.surfaceVariant))
    }

    private func statBox(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 10)).foregroundStyle(ToggTheme.muted)
                Text(value).font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(ToggTheme.surfaceVariant))
    }

    private func warningBox(title: String, warning: Bool?) -> some View {
        let active = warning == true
        let color = active ? ToggTheme.red : ToggTheme.green
        return HStack(spacing: 10) {
            Image(systemName: active ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 20)).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 10)).foregroundStyle(ToggTheme.muted)
                Text(warning == nil ? "—" : (active ? "Uyarı var" : "Yok"))
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(color)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 16).fill(ToggTheme.surfaceVariant))
    }
}

// MARK: - Giriş ekranı

struct LoginView: View {
    @ObservedObject var model: GarageModel

    var body: some View {
        ZStack {
            ToggTheme.background.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                VStack(spacing: 10) {
                    Text("TRUMORE")
                        .font(.system(size: 40, weight: .black))
                        .tracking(4)
                        .foregroundStyle(ToggTheme.teal)
                    Text("Togg dijital anahtar ve araç kontrolü")
                        .font(.subheadline).foregroundStyle(ToggTheme.muted)
                }
                VStack(spacing: 12) {
                    Image(systemName: "car.side.fill")
                        .font(.system(size: 70)).foregroundStyle(ToggTheme.teal.opacity(0.8))
                    Text("Aracınıza bağlanmak için Togg ID ile giriş yapın.")
                        .font(.footnote).foregroundStyle(ToggTheme.muted)
                        .multilineTextAlignment(.center)
                }
                .padding(28)
                .frame(maxWidth: .infinity)
                .toggCardBackground()

                Button {
                    Task { await model.login() }
                } label: {
                    HStack {
                        Image(systemName: "person.badge.key.fill")
                        Text("Togg ID ile giriş yap")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(RoundedRectangle(cornerRadius: 18).fill(ToggTheme.teal))
                }
                .buttonStyle(.plain)
                .disabled(model.busy)

                if model.busy { ProgressView().tint(ToggTheme.teal) }
                if let error = model.error {
                    Text(error).font(.footnote).foregroundStyle(ToggTheme.pink)
                        .multilineTextAlignment(.center)
                }
                Spacer()
                Text("Togg ID ve araç bilgileri üretim servislerini kullanır.")
                    .font(.caption2).foregroundStyle(ToggTheme.muted)
            }
            .padding(24)
        }
    }
}
