import LocalAuthentication
import SwiftUI
import UIKit
import UserNotifications

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
    case automaticLockOn, automaticLockOff

    var id: String { rawValue }

    var detail: String {
        switch self {
        case .lock: return "Önce cam kapatma komutu, ardından kapı kilitleme komutu gönderilecek. Cam konumu doğrulanamıyor; çevrede engel olmadığından emin olun."
        case .unlock: return "Kapı kilitleri açılacak."
        case .trunkOpen: return "Arka bagaj açılacak."
        case .trunkClose: return "Arka bagaj kapatılacak."
        case .windowsOpen: return "Yan cam açma komutu gönderilecek. Cam konumu ayrıca doğrulanamayabilir; çevrede engel olmadığından emin olun."
        case .windowsClose: return "Yan cam kapatma komutu gönderilecek. Cam konumu ayrıca doğrulanamayabilir; çevrede engel olmadığından emin olun."
        case .automaticLockOn: return "Yakınlık otomasyonu etkinleştirilecek. Bu onay araç komutu göndermez; yaklaşma/uzaklaşma otomasyonu yönetilir."
        case .automaticLockOff: return "Yakınlık otomasyonu kapatılacak; araca komut gönderilmez."
        }
    }
}

struct DashboardView: View {
    @ObservedObject var model: GarageModel
    let vehicle: Vehicle
    @AppStorage(StorageKeys.theme) private var themeName = ToggThemeStyle.togg.rawValue
    @AppStorage(StorageKeys.dashboardLayout) private var layoutName = DashboardLayoutStyle.classic.rawValue

    @EnvironmentObject private var ble: BleConnection

    @State private var tab: DashboardTab = .overview
    @State private var telemetry: VehicleTelemetry?
    @State private var updatedAt: Date?
    @State private var busy = false
    @State private var error: String?
    @State private var facingError: UserFacingError?
    @State private var geofenceNotice: String?
    @State private var showCommands = false
    @State private var showDetail = false
    @State private var showDiscovery = false
    @State private var showService = false
    @State private var showExperience = false
    @State private var showStations = false
    @State private var showAccount = false
    @State private var showBLESetupGuide = false
    @State private var authBusy = false
    @State private var showRepairConfirm = false
    @State private var alert: DashboardAlert?
    @State private var autoKeyStarted = false
    @State private var hasAuthenticatedBLE = false
    @AppStorage(GaragePreferences.keepConnectedKey) private var keepBLEConnected = false
    @State private var reconnectAttempts = 0
    @State private var reconnectTask: Task<Void, Never>?
    @State private var stableConnectionTask: Task<Void, Never>?
    @State private var proximityEnabled = false
    @StateObject private var voice = VoiceAssistant()
    @State private var showVoice = false
    @State private var voiceSourcedConfirm = false
    @State private var proximityProfile: ProximityProfile = .balanced
    @State private var proximityNearSample: Int?
    @State private var proximityFarSample: Int?
    @State private var proximityGate: ProximityGate?
    @State private var proximityRSSISamples: [Int] = []
    @State private var proximityStatus = "Ölçüm bekleniyor"
    /// Android .57 paritesi: tek biletl açma + 30 sn belirsizlik guard'ı.
    @State private var proximityGuard = ProximityCycleGuard()
    /// Android .57 paritesi: yaklaşma karar gecikmesi ölçümü.
    @State private var proximityLatencyMeter = ProximityLatencyMeter()
    @State private var proximityLastLatency: ProximityLatencyMeter.Reading?
    /// GATT örneklerinden uygun aralık önerisi; kalibrasyonsuz oturumda çalışır.
    @State private var proximitySuggester = ProximityAutoCalibrationSuggester()
    @State private var showProximityConfirmation = false
    @State private var showProximityGuide = false
    private var drivingStats: DrivingStatsStore { DrivingStatsStore(vin: vehicle.vin) }
    /// UI testinde ağ ve CoreBluetooth tarafı sessizleştirilir; yalnız yerel
    /// fixture verisi ve komut kapısı gösterimi test edilir.
    private var usesUITestFixture: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-uiTestFixture")
        #else
        false
        #endif
    }


    private func checkTirePressure(_ tires: [TireReading]) {
        let policy = TirePressureSettings().policy
        let alerts = policy.alerts(for: tires)
        guard !alerts.isEmpty else { return }

        // Aynı lastik için günde bir kez bildirim.
        let calendar = Calendar.current
        let vin = vehicle.vin
        var notifiedAny = false
        for alert in alerts {
            let key = StorageKeys.tireNotified(vin, position: alert.position.rawValue, severity: String(describing: alert.severity))
            let last = UserDefaults.standard.object(forKey: key) as? Date ?? .distantPast
            guard !calendar.isDate(last, inSameDayAs: Date()) else { continue }
            UserDefaults.standard.set(Date(), forKey: key)
            notifiedAny = true
        }
        guard notifiedAny else { return }

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let critical = alerts.contains { $0.severity == .critical }
        let content = UNMutableNotificationContent()
        content.title = critical ? "Kritik lastik basıncı" : "Lastik basıncı uyarısı"
        let detail = alerts
            .sorted { $0.pressurePSI < $1.pressurePSI }
            .map { "\($0.position.title) \(TurkishFormat.decimal($0.pressurePSI, digits: 0)) PSI" }
            .joined(separator: ", ")
        content.body = "\(detail). Eşik: \(Int(policy.lowThresholdPSI.rounded())) PSI."
        content.sound = .default
        let req = UNNotificationRequest(identifier: "tire-pressure-\(vin)", content: content, trigger: nil)
        center.add(req)
    }
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
    @AppStorage(StorageKeys.chargeCapacityKWh) private var chargeCapacityKWh = 88.5
    @AppStorage(StorageKeys.chargePricePerKWh) private var chargePricePerKWh = 10.0

    private var dashboardHeader: some View {
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
            onOpenVoice: { showVoice = true },
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
    }

    /// Eksik değer "—" olarak gösterilir; 0 değerli araç verisi "0" ve "%0"
    /// olarak korunur. Eksik veriyi 0'a sıkıştırmayan tipli gösterim.
    private var battery: Int? {
        telemetry?.batteryPercent.flatMap { value in
            value.isFinite && value >= 0 ? Int(value.rounded()) : nil
        }
    }
    private var range: Int? {
        telemetry?.rangeKM.flatMap { value in
            value.isFinite && value >= 0 ? Int(value.rounded()) : nil
        }
    }
    private var chargeEstimate: ChargingEstimate {
        ChargingEstimate.calculate(
            capacityKWh: chargeCapacityKWh,
            startPercent: chargeStartPercent,
            targetPercent: chargeTargetPercent,
            pricePerKWh: chargePricePerKWh
        )
    }
    private var batteryColor: Color {
        guard let battery else { return ToggTheme.muted }
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

    private var climateTargetKey: String { StorageKeys.climateTarget(vehicle.vin) }
    private var proximityEnabledKey: String { StorageKeys.proximityEnabled(vehicle.vin) }
    private var proximityNearKey: String { StorageKeys.proximityNear(vehicle.vin) }
    private var proximityFarKey: String { StorageKeys.proximityFar(vehicle.vin) }
    private var proximityProfileKey: String { StorageKeys.proximityProfile(vehicle.vin) }
    private var proximityAutoOffEnabledKey: String { StorageKeys.proximityAutoOffEnabled(vehicle.vin) }
    private var proximityAutoOffMinutesKey: String { StorageKeys.proximityAutoOffMinutes(vehicle.vin) }
    private var proximityAutoOffCustomKey: String { StorageKeys.proximityAutoOffCustom(vehicle.vin) }
    private var proximityAutoOffDeadlineKey: String { StorageKeys.proximityAutoOffDeadline(vehicle.vin) }
    private var proximityCalibration: ProximityCalibration? {
        guard let near = proximityNearSample, let far = proximityFarSample else { return nil }
        return ProximityCalibration(nearSample: near, farSample: far)
    }
    private var climateTemperatureText: String { "\(TurkishFormat.decimal(targetTemperature, digits: 1))°C" }
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
                        dashboardHeader
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

                    if let facingError {
                        ErrorBanner(
                            error: facingError,
                            onRetry: { Task { await refresh() } },
                            onDismiss: { self.facingError = nil }
                        )
                    } else if let error {
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
                        scheduleScrollChargingCalculator(proxy: proxy)
                    }
                    #endif
                }
            }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .toolbar(.hidden, for: .navigationBar)
        .task { if !usesUITestFixture { await liveLoop() } }
        .task { if !usesUITestFixture { await climateLoop() } }
        .task { if !usesUITestFixture { await prefetchCertificate() } }
        .task { loadProximitySettings() }
        .task { showLastKnownCloudTelemetryIfNeeded() }
        }
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
            feedProximityCalibrationSuggestion(value)
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
            // Kilit/kilit açma komutu imzalı telemetriyle doğrulandıysa widget
            // kaydına yazılır; klima/bagaj gibi diğer komutlar etiket
            // filtresiyle dışarıda kalır.
            VehicleCommandStatusStore.markVerified(true, ifLabelMatches: { label in
                label.lowercased().contains("kilit")
            })
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
            if ProcessInfo.processInfo.arguments.contains("-openCommands") {
                showCommands = true
            }
            if ProcessInfo.processInfo.arguments.contains("-autoDigitalKey"), ble.state.isDisconnected {
                keepBLEConnected = true
                model.link.configure(vin: vehicle.vin, isShared: vehicle.isShared)
                model.link.start()
            }
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-voiceMicTest") {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    let result = await voice.runMicrophoneDiagnostic()
                    print("[Voice] mikrofon tanı: \(result)")
                }
            }
            if arguments.contains("-voiceRecorderTest") {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    let result = await voice.runRecorderTest()
                    print("[Voice] kayıt testi sonucu: \(result)")
                }
            }
            if let index = arguments.firstIndex(of: "-voiceDemo"), arguments.indices.contains(index + 1) {
                let text = arguments[index + 1]
                showVoice = true
                Task { @MainActor in
                    let parsed = VoiceCommandParser().parseDetailed(text)
                    if parsed.command.isAction {
                        for _ in 0..<36 {
                            if ble.state.isReady,
                               let state = ble.telemetry,
                               Date().timeIntervalSince(state.receivedAt) < 10 {
                                break
                            }
                            try? await Task.sleep(nanoseconds: 500_000_000)
                        }
                    } else {
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                    }
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    voice.submit(text)
                }
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
                proximityGuard = ProximityCycleGuard()
                proximityLatencyMeter = ProximityLatencyMeter()
                proximityLastLatency = nil
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
            updateChargeStartPercentIfNeeded(value)
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
                    primaryButton: .destructive(Text("Gönder")) { approve(command) },
                    secondaryButton: .cancel(Text("Vazgeç")) { voiceSourcedConfirm = false }
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
            Text("Uygulama ekrandayken yeni yaklaşma algılanırsa kilit açılır. Uzaklaşınca, tüm kapılar kapalı ve araç beklemedeyse önce cam kapatma isteği, araç onayından sonra kilitleme gönderilir. Pencere açıklığı telemetride yok; bu nedenle cam kapatma her kilitlemeden önce denenir. Arka planda araç komutu gönderilmez.")
        }
        .sheet(isPresented: $showVoice) {
            VoiceSheet(voice: voice) { text in
                handleVoiceUtterance(text)
            }
        }
        .sheet(isPresented: $showBLESetupGuide) {
            BLESetupGuideSheet(ble: ble)
        }
        .sheet(isPresented: $showProximityGuide) {
            ProximityCalibrationSheet(
                vin: vehicle.vin,
                currentRSSI: ble.rssi,
                rssiAge: ble.rssiUpdatedAt.map { Date().timeIntervalSince($0) },
                bleReady: ble.state.isReady,
                nearSample: proximityNearSample,
                farSample: proximityFarSample,
                calibrationValid: proximityCalibration?.isValid == true,
                profile: proximityProfile,
                onCaptureNear: { captureProximitySample(isNear: true) },
                onCaptureFar: { captureProximitySample(isNear: false) },
                onReset: resetProximityCalibration
            )
        }
        .sheet(isPresented: $showCommands) {
            NavigationStack {
                CommandView(vehicle: vehicle, api: model.api, linkStatus: model.linkStatus)
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
            if layout == .sport { quickActions }
            bleCard
            if layout == .technical { technicalOverview }
            if layout != .minimal && layout != .sport { proximityCard }
            if layout != .minimal {
                PremiumControlsSection(onWindowCommand: requestWindowCommand)
            }
            if layout == .sport { proximityCard }
            geofenceCard
            drivingStatsCard
            ChargingBudgetCard(vin: vehicle.vin)
            MaintenanceCard(vin: vehicle.vin, odometer: telemetry?.odometerKM)
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
                        Text("Seyahatname")
                            .font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                        Text("Yolculuk, şarj ve karşılaştırma kayıtları")
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
            auxiliaryHistoryLine: auxiliaryHistoryLine,
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
                    Text(bleStateTitle)
                        .font(.system(size: 12))
                        .foregroundStyle(ble.state.isReady && !model.silentRecovery ? ToggTheme.green : ToggTheme.muted)
                }
                Spacer()
                Circle().fill(bleStatusColor).frame(width: 9, height: 9)
            }

            if !model.silentRecovery {
                if let summary = ble.failureSummary, ble.state.isFailed {
                    Label(summary, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ToggTheme.orange)
                        .lineLimit(2)
                } else if !ble.lastEvent.isEmpty {
                    Text(ble.lastEvent)
                        .font(.caption2).foregroundStyle(ToggTheme.muted).lineLimit(2)
                }
            }

            if !ble.state.isReady, !model.linkStatus.isEmpty, model.linkStatus != ble.state.description {
                Text(model.linkStatus)
                    .font(.caption2).foregroundStyle(ToggTheme.muted).lineLimit(2)
            }

            Button { showBLESetupGuide = true } label: {
                Label("Kurulumu adım adım dinle", systemImage: "speaker.wave.2.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ToggTheme.teal)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

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

            if !ble.state.isReady {
                Button { showRepairConfirm = true } label: {
                    Label("Dijital anahtarı yeniden eşleştir", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ToggTheme.teal)
                }
                .buttonStyle(.plain)
                .disabled(authBusy)
                .confirmationDialog("Dijital anahtarı yeniden eşleştir?",
                                    isPresented: $showRepairConfirm,
                                    titleVisibility: .visible) {
                    Button("Eşleştir") { Task { await authenticateBLE(overwriteOwner: true) } }
                    Button("Vazgeç", role: .cancel) {}
                } message: {
                    Text("Araç sahipliği bu telefona taşınır ve araç anahtarı yeniden alınır. Araçta dijital anahtar eşleştirmesi açık olmalı.")
                }
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
                Button {
                    showProximityGuide = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(ToggTheme.teal)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Yakınlık kalibrasyon rehberi")
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

            let backgroundLog = ProximityDetectionMonitor.transitionsLog(for: vehicle.vin)
            if !backgroundLog.isEmpty {
                Text("Son geçişler (arka plan; yalnızca algılama)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ToggTheme.muted)
                ForEach(backgroundLog.suffix(4).reversed()) { entry in
                    Text("\(entry.at.formatted(date: .omitted, time: .shortened)) · \(entry.approached ? "Yaklaşma" : "Uzaklaşma") · \(entry.rssi) dBm")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(ToggTheme.muted)
                }
            }

            Text("Kilit komutları yalnızca uygulama ekrandayken ve araç bağlantısı ile güncel araç durumu hazırken gönderilir. Arka planda yalnızca algılama yapılır: geçişler günlüğe yazılır, bildirim düşer, araca komut gönderilmez.")
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

    private var geofenceCard: some View {
        let readiness = model.geofence.readiness
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Geofence (Ev/iş)", systemImage: "location.circle")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                Spacer()
                Text(geofenceStatusBadge)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(model.geofence.enabled ? ToggTheme.green : ToggTheme.muted)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill((model.geofence.enabled ? ToggTheme.green : ToggTheme.muted).opacity(0.15)))
            }

            Toggle("Geofence aktif", isOn: Binding(
                get: { model.geofence.enabled },
                set: { newValue in
                    if !model.geofence.setEnabled(newValue), newValue {
                        geofenceNotice = readiness.message
                    } else {
                        geofenceNotice = nil
                    }
                }
            ))
            .tint(ToggTheme.teal)
            .disabled(!readiness.canEnable && !model.geofence.enabled)
            .accessibilityHint(readiness.canEnable ? "Bölgeye girince açma, çıkınca kilitleme" : readiness.message)

            HStack(spacing: 8) {
                Button(model.geofence.homeCoordinate == nil ? "Ev konumunu ayarla" : "Ev konumunu güncelle") {
                    model.geofence.setHomeToCurrentLocation()
                }
                .font(.system(size: 11, weight: .semibold)).buttonStyle(.bordered)

                if model.geofence.homeCoordinate != nil {
                    Button("Konumu sil") { model.geofence.clearHomeLocation() }
                        .font(.system(size: 11)).buttonStyle(.bordered).tint(ToggTheme.pink)
                }
            }

            HStack {
                Text("Bölge yarıçapı").font(.system(size: 10)).foregroundStyle(ToggTheme.muted)
                Slider(
                    value: Binding(
                        get: { model.geofence.radiusMeters },
                        set: { model.geofence.setRadius($0) }
                    ),
                    in: GeofencePolicy.minimumRadiusMeters...GeofencePolicy.maximumRadiusMeters,
                    step: 10
                )
                .tint(ToggTheme.teal)
                Text("\(Int(model.geofence.radiusMeters)) m")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
            }

            if let coord = model.geofence.homeCoordinate {
                Text("Ev: \(coord.latitude, specifier: "%.5f"), \(coord.longitude, specifier: "%.5f")")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(ToggTheme.muted)
            }

            if let error = model.geofence.lastError {
                Text(error).font(.system(size: 9)).foregroundStyle(ToggTheme.pink)
            } else if let notice = geofenceNotice ?? (!readiness.canEnable ? readiness.message : nil) {
                Text(notice).font(.system(size: 9)).foregroundStyle(ToggTheme.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(readiness.message).font(.system(size: 9)).foregroundStyle(ToggTheme.muted)
            }

            Text("Konum yalnızca cihazda kullanılır. Arka planda komut gönderilmez; bölgeye girince/çıkınca uygulama uyanır ve komut READY + taze telemetri koşuluna tabidir.")
                .font(.system(size: 9)).foregroundStyle(ToggTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18).toggCardBackground()
    }

    private var geofenceStatusBadge: String {
        if model.geofence.enabled {
            return model.geofence.isMonitoring ? "İZLENİYOR" : "BEKLİYOR"
        }
        return "KAPALI"
    }

    private func consumptionText(_ stats: DrivingStats) -> String {
        guard stats.daysWithData > 0 else { return "—" }
        let value = TurkishFormat.decimal(stats.consumptionKWhPer100km, digits: 1)
        return stats.consumptionIsMeasured ? "\(value) kWh/100 km" : "\(value) kWh/100 km (varsayılan)"
    }

    private func monthTitle(_ month: String) -> String {
        let parts = month.split(separator: "-")
        guard parts.count == 2, let monthNumber = Int(parts[1]), (1...12).contains(monthNumber) else { return month }
        let names = ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran",
                     "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"]
        return "\(names[monthNumber - 1]) \(parts[0])"
    }

    private var priceText: String {
        EnergyPricing(pricePerKWh: chargePricePerKWh).priceText
    }

    private var drivingStatsCard: some View {
        let stats = drivingStats.monthlyStats(pricePerKWh: chargePricePerKWh)
        let weekKm = drivingStats.last7DaysKm()
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Sürüş İstatistikleri", systemImage: "chart.bar.fill")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                Spacer()
                Text(monthTitle(stats.month)).font(.system(size: 10)).foregroundStyle(ToggTheme.muted)
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Int(stats.km.rounded())) km")
                        .font(.system(size: 22, weight: .bold)).foregroundStyle(ToggTheme.teal)
                    Text("Bu ay · \(stats.daysWithData) gün veri")
                        .font(.caption).foregroundStyle(ToggTheme.muted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(TurkishFormat.decimal(stats.estimatedCostTRY, digits: 0)) ₺")
                        .font(.system(size: 22, weight: .bold)).foregroundStyle(ToggTheme.orange)
                    Text("\(TurkishFormat.decimal(stats.estimatedKWh, digits: 1)) kWh \(stats.consumptionIsMeasured ? "" : "tahmini")")
                        .font(.caption).foregroundStyle(ToggTheme.muted)
                }
            }
            Divider().overlay(ToggTheme.muted.opacity(0.2))
            HStack {
                Text("Son 7 gün").font(.caption).foregroundStyle(ToggTheme.muted)
                Spacer()
                Text(stats.daysWithData > 0 ? "\(Int(weekKm.rounded())) km" : "—")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            }
            HStack {
                Text("Tüketim").font(.caption).foregroundStyle(ToggTheme.muted)
                Spacer()
                Text(consumptionText(stats))
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            }
            Text(stats.daysWithData > 1
                 ? (stats.consumptionIsMeasured
                    ? "Tüketim batarya yüzdesi farkından ölçülür (88,5 kWh batarya). Maliyet \(priceText) varsayımıyla, kayıp yok."
                    : "Tüketim için yeterli batarya ölçümü yok; 17 kWh/100 km varsayılanı kullanılıyor. Maliyet \(priceText) varsayımıyla, kayıp yok.")
                 : "Yeterli veri yok. Birkaç günlük odometer ve batarya okumasından sonra km, tüketim ve maliyet hesaplanır.")
                .font(.system(size: 9)).foregroundStyle(ToggTheme.muted)
        }
        .padding(18).toggCardBackground()
    }

    var technicalOverview: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("Canlı BLE Tanısı", systemImage: "waveform.path.ecg")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(ToggTheme.teal)
                Spacer()
                Text(ble.state.description)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ToggTheme.muted)
            }
            HStack(spacing: 12) {
                technicalMetric("RSSI", ble.rssi.map { "\($0) dBm" } ?? "—")
                technicalMetric("Kanallar", "\(ble.channels.count)")
                technicalMetric("Kayıt", "\(ble.diagnosticEvents.count)")
                technicalMetric("Kilit", ble.lockConfirmationCount > 0 ? "Doğrulandı ✓" : "Bekliyor")
            }
            proximityLatencyReportRow
            if let telemetry = ble.telemetry {
                Text("İmzalı telemetri · \(telemetry.receivedAt.formatted(date: .omitted, time: .standard))")
                    .font(.system(size: 10))
                    .foregroundStyle(ToggTheme.muted)
            }
            if !ble.diagnosticEvents.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Son olaylar").font(.system(size: 9, weight: .semibold)).foregroundStyle(ToggTheme.muted)
                    ForEach(Array(ble.diagnosticEvents.suffix(5).reversed())) { event in
                        HStack(spacing: 6) {
                            Text(event.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(ToggTheme.muted)
                            Text(event.message)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 6).fill(ToggTheme.surfaceVariant))
                    }
                }
            }
            if let carProofVerified = ble.telemetry?.isLocked {
                HStack(spacing: 8) {
                    Image(systemName: carProofVerified ? "checkmark.seal.fill" : "seal")
                        .foregroundStyle(carProofVerified ? ToggTheme.green : ToggTheme.orange)
                    Text(carProofVerified ? "Araç kanıtı doğrulandı" : "Araç kanıtı bekleniyor")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(14)
        .toggCardBackground(18)
    }

    func technicalMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 9, weight: .semibold)).foregroundStyle(ToggTheme.muted)
            Text(value).font(.system(size: 12, weight: .bold, design: .monospaced)).foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Yaklaşma karar gecikmesi tek satır raporu (Android .57 latency paritesi).
    /// Eksik ölçü "—" gösterilir, asla 0 yazılmaz; pencere iddia değil profil
    /// matematiğidir (gerekli örnek × RSSI aralığı).
    private var proximityLatencyReportText: String {
        guard let last = proximityLastLatency else {
            return "Yaklaşma kararı · — · örnek — · pencere ≤ \(TurkishFormat.decimal(ProximityLatencyMeter.Reading.expectedInterval(for: proximityProfile), digits: 2)) sn"
        }
        let latency = last.cycleLatencyMs.map { "\(TurkishFormat.integer(Double($0))) ms" } ?? "—"
        return "Yaklaşma kararı · \(latency) · \(last.samples) örnek · pencere ≤ \(TurkishFormat.decimal(ProximityLatencyMeter.Reading.expectedInterval(for: proximityProfile), digits: 2)) sn · \(last.at.formatted(date: .omitted, time: .shortened))"
    }

    @ViewBuilder
    private var proximityLatencyReportRow: some View {
        Text(proximityLatencyReportText)
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(ToggTheme.muted)
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

    private var bleStateTitle: String {
        if model.silentRecovery { return "Yeniden bağlanıyor…" }
        if ble.state.isReady { return "Bağlı · Komut hazır" }
        return ble.state.description
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
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
            model.link.configure(vin: vehicle.vin, isShared: vehicle.isShared)
            model.link.start()
        } else {
            keepBLEConnected = false
            reconnectTask?.cancel()
            reconnectTask = nil
            stableConnectionTask?.cancel()
            stableConnectionTask = nil
            model.link.stop()
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
        proximityGuard = ProximityCycleGuard()
        proximityLatencyMeter = ProximityLatencyMeter()
        proximityLastLatency = nil
        ble.setProximityRSSIPollInterval(proximityProfile.pollInterval)
        proximityStatus = "Etkin; araç bağlantısı aranıyor"
        if proximityAutoOffEnabled, let deadline = proximityAutoOffDeadline {
            scheduleProximityAutoOff(deadline: deadline)
        } else if proximityAutoOffEnabled {
            proximityAutoOffStatus = "Sayaç ilk doğrulanmış otomatik kilitlemeden sonra başlar."
        }
        keepBLEConnected = true
        model.link.configure(vin: vehicle.vin, isShared: vehicle.isShared)
        if ble.state.isDisconnected || ble.state.isFailed {
            model.link.start()
        }
    }


    private func updateChargeStartPercentIfNeeded(_ value: Double) {
        if value < chargeStartPercent {
            chargeStartPercent = value
        }
    }

    private func scheduleScrollChargingCalculator(proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation { proxy.scrollTo("chargingCalculator", anchor: .top) }
        }
    }

    @MainActor
    private func resetProximityCalibration() {
        proximityNearSample = nil
        proximityFarSample = nil
        proximityGate = nil
        UserDefaults.standard.removeObject(forKey: proximityNearKey)
        UserDefaults.standard.removeObject(forKey: proximityFarKey)
        proximityStatus = "Ölçümler sıfırlandı. Yeniden yakın ve uzak ölçüm alın."
        if proximityEnabled { setProximityEnabled(false) }
    }

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
            proximityGuard = ProximityCycleGuard()
            proximityLatencyMeter = ProximityLatencyMeter()
            proximityLastLatency = nil
            proximitySuggester.reset()
            if proximityEnabled {
                proximityStatus = "Eşikler güncellendi; yakınlık izleniyor."
            }
        } else if proximityNearSample != nil, proximityFarSample != nil {
            setProximityEnabled(false)
            proximityStatus = "Ölçüm farkı yetersiz. Yakın/uzak arasında en az 14 dB olmalı."
            proximitySuggester.reset()
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
        proximityGuard = ProximityCycleGuard()
        proximityLatencyMeter = ProximityLatencyMeter()
        proximityLastLatency = nil
        proximityRSSISamples.removeAll()
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
        model.link.configure(vin: vehicle.vin, isShared: vehicle.isShared)
        if ble.state.isDisconnected || ble.state.isFailed {
            reconnectAttempts = 0
            autoKeyStarted = false
            model.link.start()
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
        model.link.stop()
        proximityAutoOffStatus = "Süre doldu; otomasyon kapatıldı. Araca komut gönderilmedi."
        proximityStatus = proximityAutoOffStatus
        return true
    }

    @MainActor
    private func processProximityRSSI(_ rssi: Int) {
        if expireProximityAutoOffIfNeeded() { return }
        guard proximityEnabled, ble.state.isReady, var gate = proximityGate else { return }
        guard let sampledAt = ble.rssiUpdatedAt,
              ProximityRSSIPolicy.isFresh(sampledAt: sampledAt, now: Date(), profile: proximityProfile) else {
            requireFreshProximityCycle(reason: "GATT RSSI ölçümü eski/geçersiz", resetGuard: false)
            proximityGuard.noteAmbiguity(now: Date())
            proximityStatus = "GATT RSSI ölçümü güncel değil; açma bileti iptal, 30 sn guard."
            ble.recordDiagnostic("gatt_rssi_stale · proximity geçişi ve komut iptal edildi, guard devrede")
            return
        }
        let transition = gate.update(rssi: rssi)
        proximityGate = gate
        proximityLatencyMeter.noteSample()
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
            let lastLatency = proximityLatencyMeter.noteApproachDecision(now: Date())
            proximityLastLatency = lastLatency
            let expected = ProximityLatencyMeter.Reading.expectedInterval(for: proximityProfile)
            ble.recordDiagnostic("proximity_latency · yaklaşma kararı \(lastLatency.cycleLatencyMs.map(String.init) ?? "none") ms · \(lastLatency.samples) örnek · pencere <= \(Int(expected * 1000)) ms")
            if isLocked {
                let decision = proximityGuard.decideApproach(now: Date())
                switch decision {
                case .sendUnlock:
                    if ble.unlock() {
                        proximityGuard.noteUnlockIssued()
                        recordWidgetCommand("Otomatik kilit açma (yakınlık)")
                        proximityStatus = "Yakınlık algılandı; imzalı kilit açma isteği başlatıldı."
                        ble.recordDiagnostic("Yakınlık otomasyonu kilit açma biletiyle istek başlattı")
                    } else {
                        proximityGuard.noteAmbiguity(now: Date())
                        proximityStatus = "Yakınlık algılandı; kilit açma gönderilmedi: \(ble.lastEvent)"
                        ble.recordDiagnostic("Yakınlık otomasyonu kilit açmayı başlatamadı; bilet iptal, guard devrede")
                    }
                case .deny(let reason):
                    proximityStatus = reason
                    ble.recordDiagnostic("Yakınlık açma guard'ı: komut gönderilmedi")
                }
            } else {
                proximityStatus = "Yakınlık algılandı; kapılar zaten açık."
            }
        case .departed:
            let now = Date()
            proximityGuard.noteDepartureConfirmed(now: now)
            proximityLatencyMeter.noteDepartureDecision(now: now)
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
                if ble.lock() {
                    recordWidgetCommand("Kilitleme (yakınlık)")
                    proximityStatus = "Uzaklaşma algılandı; cam kapatma ve ardından kapı kilitleme akışı başlatıldı."
                    ble.recordDiagnostic("Yakınlık otomasyonu cam kapatma/kilitleme akışını başlattı")
                } else {
                    pendingAutoLockTask?.cancel()
                    pendingAutoLockTask = nil
                    awaitingProximityLockConfirmation = false
                    proximityStatus = "Uzaklaşma algılandı; kilitleme başlatılamadı: \(ble.lastEvent)"
                    ble.recordDiagnostic("Yakınlık otomasyonu kilitleme akışını başlatamadı")
                }
            } else {
                proximityStatus = "Uzaklaşma algılandı; kapılar zaten kilitli."
            }
        }
    }

    @MainActor
    private func handleBLEState(_ state: BleConnection.State) {
        if state.isConnecting || state.isDisconnected || state.isFailed {
            requireFreshProximityCycle(reason: "BLE oturumu değişti: \(state.description)", resetGuard: true)
        }
        if state.isReady {
            hasAuthenticatedBLE = true
            if proximityEnabled { proximityStatus = "Bağlı; yakınlık izleniyor (uygulama ekranda kalmalı)." }
            return
        }

        if state.isDisconnected || state.isFailed {
            autoKeyStarted = false
            stableConnectionTask?.cancel()
            stableConnectionTask = nil
        }
    }

    @MainActor
    private func requireFreshProximityCycle(reason: String, resetGuard: Bool) {
        guard proximityEnabled, var gate = proximityGate,
              !gate.isAwaitingFarBaseline,
              gate.presence != .unknown || !proximityRSSISamples.isEmpty else { return }
        gate.requireFreshCycle()
        proximityGate = gate
        if resetGuard {
            proximityGuard = ProximityCycleGuard()
            proximityLatencyMeter = ProximityLatencyMeter()
            proximitySuggester = ProximityAutoCalibrationSuggester()
        } else {
            // Belirsizlik/fresh cycle: örnek penceresi yeniden başlar.
            proximityLatencyMeter.noteBaseline(now: Date())
        }
        proximityRSSISamples.removeAll()
        proximityStatus = "BLE oturumu yenilendi; önce uzak, sonra yeni yaklaşma kanıtı bekleniyor."
        ble.recordDiagnostic("proximity_fresh_cycle · \(reason)")
    }

    @MainActor
    private func authenticateBLE(overwriteOwner: Bool = false) async {
        guard !authBusy else { return }
        authBusy = true
        error = nil
        facingError = nil
        defer { authBusy = false }
        do {
            model.link.configure(vin: vehicle.vin, isShared: vehicle.isShared)
            try await model.link.authenticateNow(overwriteOwner: overwriteOwner)
        } catch is CancellationError {
            return
        } catch {
            self.facingError = .from(error)
        }
    }

    private func send(_ command: DashboardCommand) {
        switch command {
        case .lock: ble.lock(); recordWidgetCommand("Kilitleme")
        case .unlock: ble.unlock(); recordWidgetCommand("Kilit açma")
        case .trunkOpen: ble.trunkOpen(); recordWidgetCommand("Bagaj açma")
        case .trunkClose: ble.trunkClose(); recordWidgetCommand("Bagaj kapatma")
        case .windowsOpen: ble.windowsOpen(); recordWidgetCommand("Cam açma")
        case .windowsClose: ble.windowsClose(); recordWidgetCommand("Cam kapatma")
        // Oto kilit BLE komutu değildir; approve() uygulama anahtarını çevirir.
        case .automaticLockOn, .automaticLockOff: break
        }
    }

    /// Widget'a son komut yazımı: yalnız etiket ve zaman; VIN/token asla
    /// yazılmaz. Doğrulama yoksa `verified` nil kalır → "doğrulama yok".
    private func recordWidgetCommand(_ label: String, verified: Bool? = nil) {
        VehicleCommandStatusStore.save(
            VehicleCommandStatus(actionLabel: label, sentAt: Date(), verified: verified)
        )
        // Saat de aynı sonucu görsün (24 saatten eski kayıt süzülür).
        model.publishWatchSnapshot()
    }

    /// Uygun yakınlık aralığını GATT örneklerinden otomatik algılar.
    /// Öneri bildirimi yalnız kullanıcıya haber verir: kalibrasyon yazımı,
    /// otomasyon açma ve komut **kendiliğinden** olmaz.
    private func feedProximityCalibrationSuggestion(_ rssi: Int) {
        guard ble.state.isReady else { return }
        if let calibration = proximityCalibration, calibration.isValid, !proximityEnabled {
            // Geçerli kalibrasyon varken öneri takibi gereksizdir.
            proximitySuggester.reset()
            return
        }
        guard let suggestion = proximitySuggester.feed(rssi) else { return }
        let text = "Uygun aralık algılandı: yakın \(suggestion.nearSample) dBm, uzak \(suggestion.farSample) dBm."
        proximityStatus = text + " Onaylamak için yakında/uzakta ölçümleri bu değerlerle kaydedin."
        ble.recordDiagnostic("proximity_autocal · öneri yakın=\(suggestion.nearSample) uzak=\(suggestion.farSample) fark=\(suggestion.separation) dBm")
        postCalibrationSuggestionNotification(suggestion)
    }

    private func postCalibrationSuggestionNotification(_ suggestion: ProximityAutoCalibrationSuggester.Suggestion) {
        let content = UNMutableNotificationContent()
        content.title = "Uygun yakınlık aralığı algılandı"
        content.body = "Yakın ölçüm \(suggestion.nearSample) dBm, uzak ölçüm \(suggestion.farSample) dBm (fark \(suggestion.separation) dBm). Aralık metreye çevrilmez; otomasyonu kendi kendine açmadım. Onay için yakınlık kartındaki ölçüm düğmelerini kullan."
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    /// 12 V akü düşükse iPhone'a yerel bildirim. Lastik uyarısıyla aynı
    /// desen: yalnız **taze** telemetri güncellemesinden gelir (önbellekten
    /// gösterilen eski değere yazılmaz), ciddiyet başına günde bir kez,
    /// VIN'siz anahtar ve VIN'siz metin. Eksik veri bildirim üretmez
    /// ("bilgi yok" ≠ uyarı); gerçek 0 kritik bildirimdir.
    /// 12 V akü günlük geçmişi (Android aux_history paritesi); yalnız
    /// taze telemetri kaydı yapılır, eksik gün "—" kalır.
    @State private var auxiliaryHistory = AuxiliaryBatteryHistory()

    private func checkAuxiliaryBattery(_ percent: Double?) {
        // Geçmiş kaydı uyarıdan bağımsızdır: sağlıklı değer (> %40) de günün
        // en güncel ölçümü olarak yazılır; eksik/aralık dışı değer record
        // içinde reddedilir. Uyarı değerlendirmesi yalnız bildirimi yönetir.
        if auxiliaryHistory.record(percent: percent, on: Date()) {
            saveAuxiliaryHistory()
        }
        guard let assessment = AuxiliaryBatteryPolicy.assess(percent) else { return }
        let key = StorageKeys.auxiliaryNotified(vehicle.vin, severity: assessment.severity == .critical ? "critical" : "warning")
        let calendar = Calendar.current
        let last = UserDefaults.standard.object(forKey: key) as? Date ?? .distantPast
        guard !calendar.isDate(last, inSameDayAs: Date()) else { return }
        UserDefaults.standard.set(Date(), forKey: key)

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = assessment.isCritical ? "12 V akü kritik düşük" : "12 V akü zayıf"
        content.body = "Akü yüzde \(assessment.percent). "
            + (assessment.isCritical
                ? "Uzun parklarda araç açılmayabilir; en kısa sürede şarj/bakım kontrolü önerilir."
                : "Yakında şarj/bakım kontrolü önerilir.")
        content.sound = .default
        // Kritik bandı time-sensitive taşınır: kilitli ekranda ve
        // eşlenmiş saatte yoğun olmayan haptikle görünür (Critical Alerts
        // yetkisi yok; kullanıcının bildirim ayarı geçerlidir).
        if assessment.isCritical {
            content.interruptionLevel = .timeSensitive
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request, withCompletionHandler: nil)
    }

    private var auxiliaryHistoryKey: String { StorageKeys.auxiliaryHistory(vehicle.vin) }

    /// Görüntü için geçmiş: taze kayıt varsa state; yoksa kayıtlı veri.
    /// Bilinçli olarak salt-okunurdur (body değerlendirmesinde state
    /// yazımı yapılmaz).
    private var storedAuxiliaryHistory: AuxiliaryBatteryHistory {
        if !auxiliaryHistory.samples.isEmpty { return auxiliaryHistory }
        if let data = UserDefaults.standard.data(forKey: auxiliaryHistoryKey),
           let history = try? JSONDecoder().decode(AuxiliaryBatteryHistory.self, from: data) {
            return history
        }
        return AuxiliaryBatteryHistory()
    }

    private func saveAuxiliaryHistory() {
        if let data = try? JSONEncoder().encode(auxiliaryHistory) {
            UserDefaults.standard.set(data, forKey: auxiliaryHistoryKey)
        }
    }

    private var auxiliaryHistoryLine: String? {
        let values = storedAuxiliaryHistory.displayValues(count: 3, today: Date())
        guard values.contains(where: { $0 != "—" }) else { return nil }
        return "Son 3 gün (12 V): " + values.joined(separator: " · ")
    }

    private func approve(_ command: DashboardCommand) {
        let voiceSourced = voiceSourcedConfirm
        let requiresOwnerAuthentication = voiceSourced && command == .unlock
        voiceSourcedConfirm = false

        // Oto kilit araç komutu değildir: uygulama içi otomasyon anahtarı.
        // Bağlantı/telemetri kapıları uygulanmaz.
        switch command {
        case .automaticLockOn:
            setProximityEnabled(true)
            return
        case .automaticLockOff:
            setProximityEnabled(false)
            return
        default:
            break
        }

        guard ble.state.isReady else {
            error = "Araç bağlantısı hazır değil; komut gönderilmedi."
            return
        }

        if voiceSourced {
            guard let state = ble.telemetry,
                  Date().timeIntervalSince(state.receivedAt) < 15 else {
                error = "Araç verisi güncel değil; komut gönderilmedi."
                return
            }
        }

        guard requiresOwnerAuthentication else {
            send(command)
            return
        }

        Task { @MainActor in
            let authenticated = await authenticateVoiceUnlock()
            if authenticated {
                send(command)
            } else {
                error = "Kilit açma için kimlik doğrulaması yapılmadı; komut gönderilmedi."
            }
        }
    }

    private func authenticateVoiceUnlock() async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Vazgeç"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return false
        }
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Sesli komutla kapı kilitlerini açmak için kimliğini doğrula."
            )
        } catch {
            return false
        }
    }

    // MARK: - Sesli komutlar

    private func handleVoiceUtterance(_ text: String) -> String {
        let parsed = VoiceCommandParser().parseDetailed(text)
        VoiceLog.debug("komut: \(parsed.command) güven: \(parsed.confidence)")

        switch parsed.command {
        case .status(let topic):
            return voiceStatusResponse(topic)
        case .nearbyStations:
            return voiceNearbyStationsResponse()
        case .unknown:
            if let chat = VoiceChat().reply(for: text) {
                VoiceLog.debug("sohbet: \(chat.topic)")
                return chat.text
            }
            return voiceCommandResponse(parsed.command)
        default:
            return voiceCommandResponse(parsed.command)
        }
    }

    private var voiceContext: VoiceContext {
        VoiceContext(
            linkReady: ble.state.isReady,
            telemetryAge: ble.telemetry.map { Date().timeIntervalSince($0.receivedAt) },
            deviceUnlocked: UIApplication.shared.isProtectedDataAvailable,
            climateServiceAvailable: false,
            previewActionsEnabled: true
        )
    }

    /// Android `nearby_stations` paritesi, iOS kuralıyla: telefon konumu
    /// paylaşılmaz ve mesafe sıralaması yapılmaz; kayıtlı EPDK kataloğunun
    /// gerçek özeti söylenir, tazeleme arka planda tetiklenir (rate-limit'e
    /// saygılı `load()`). Veri yoksa "henüz yüklenmedi" denir, sayı uydurulmaz.
    private func voiceNearbyStationsResponse() -> String {
        Task { @MainActor in
            _ = try? await EPDKStationService.shared.load()
        }
        guard let summary = EPDKStationService.cachedCatalogSummary() else {
            return "EPDK istasyon kataloğu henüz yüklenmedi; istasyonlar sekmesine girince ilk veri çekilir. Telefon konumu paylaşmadığım için mesafe sıralaması yapmıyorum."
        }
        let time = TurkishFormat.date(summary.fetchedAt, format: "HH:mm")
        return "EPDK kataloğu yüklü: \(summary.stationCount) istasyon, saat \(time) verisi. Telefon konumu paylaşmadığım için mesafe sıralaması yapmıyorum; arama istasyonlar sekmesinde."
    }

    private func voiceCommandResponse(_ command: VoiceCommand) -> String {
        let decision = VoiceCommandPolicy().decide(command, context: voiceContext)

        switch decision {
        case .read(let topic):
            return voiceStatusResponse(topic)
        case .speak(let text), .reject(let text):
            return text
        case .confirm(_, let prompt):
            guard let dashboardCommand = dashboardCommand(for: command) else {
                return "Bu komut için onay ekranı yok."
            }
            voiceSourcedConfirm = true
            showVoice = false
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                alert = .confirm(dashboardCommand)
            }
            return prompt + " Onay ekranını açıyorum."
        case .execute(let command):
            if case .automaticLock(let on) = command, let on {
                setProximityEnabled(on)
                return on
                    ? "Otomatik kilit etkinleştirildi."
                    : "Otomatik kilit kapatıldı."
            }
            if case .autoOff(let enabled, let minutes) = command {
                return applyVoiceAutoOff(enabled: enabled, minutes: minutes)
            }
            return "\(command.actionLabel ?? "Komut") için onay gerekiyor."
        case .authenticate(let command, _):
            return "\(command.actionLabel ?? "Komut") için onay ve Face ID gerekiyor."
        }
    }

    /// Sesli autoOff uygulaması: yalnız belirtilen alan değişir (Android
    /// "belirtilmeyen alanı gönderme" kuralı). Süre aralığı dışı değer
    /// politikada yakalanır; burada savunmacı olarak da reddedilir.
    /// Sayaç anahtarı kapalıysa süre yine kaydedilir ve durum dürüstçe söylenir.
    private func applyVoiceAutoOff(enabled: Bool?, minutes: Int?) -> String {
        var parts: [String] = []
        if let enabled {
            setProximityAutoOffEnabled(enabled)
            parts.append(enabled
                ? "Otomatik kapanma sayacı açıldı."
                : "Otomatik kapanma sayacı kapatıldı.")
        }
        if let minutes {
            guard ProximityAutoOffPolicy.allowedMinutes.contains(minutes) else {
                return "Süre 1 ile 1440 dakika arasında olmalı; değişiklik yapmadım."
            }
            proximityAutoOffMinutes = 0
            proximityAutoOffCustomText = String(minutes)
            UserDefaults.standard.set(minutes, forKey: proximityAutoOffCustomKey)
            let counterNote = proximityAutoOffEnabled
                ? ""
                : " Sayaç şu an kapalı; açmak için yakınlık kartındaki anahtarı kullan."
            parts.append("Otomatik kapanma süresi \(minutes) dakika olarak ayarlandı.\(counterNote)")
        }
        return parts.isEmpty
            ? "Bu tercihi yakınlık kartından yönetebilirsin."
            : parts.joined(separator: " ")
    }

    private func dashboardCommand(for command: VoiceCommand) -> DashboardCommand? {
        switch command {
        case .lock: return .lock
        case .unlock: return .unlock
        case .trunk(let open): return open ? .trunkOpen : .trunkClose
        case .windows(let open): return open ? .windowsOpen : .windowsClose
        case .automaticLock(let on): return on == true ? .automaticLockOn : on == false ? .automaticLockOff : nil
        default: return nil
        }
    }

    private func voiceStatusResponse(_ topic: VoiceStatusTopic) -> String {
        switch topic {
        case .battery:
            var parts: [String] = []
            if let percent = telemetry?.batteryPercent, percent.isFinite {
                parts.append("Batarya yüzde \(Int(percent.rounded()))")
            } else {
                parts.append("Batarya bilgisi yok")
            }
            if let range = telemetry?.rangeKM, range.isFinite {
                parts.append("menzil \(Int(range.rounded())) kilometre")
            }
            return parts.joined(separator: ", ") + "." + voiceCloudAgeNote()

        case .range:
            guard let range = telemetry?.rangeKM, range.isFinite else {
                return "Menzil bilgisi yok."
            }
            return "Menzil \(Int(range.rounded())) kilometre." + voiceCloudAgeNote()

        case .locks:
            guard let state = ble.telemetry else {
                return "Kapı durumu için araç bağlantısı yok."
            }
            guard let locked = state.isLocked else {
                return "Kilit durumu doğrulanamıyor."
            }
            var answer = locked ? "Kapılar kilitli." : "Kapılar kilit açık."
            if state.openDoorCount > 0 {
                answer += " \(state.openDoorCount) kapı açık görünüyor."
            }
            return answer + " Son araç verisi \(voiceAge(state.receivedAt))."

        case .trunk:
            guard let state = ble.telemetry else {
                return "Bagaj durumu için araç bağlantısı yok."
            }
            let open = state.trunkAjar == 1
            return (open ? "Bagaj açık." : "Bagaj kapalı.") + " Son araç verisi \(voiceAge(state.receivedAt))."

        case .windows:
            return "Cam konumu araç telemetrisinde yok. Açmak veya kapatmak için sesli komut verebilirsin; onay ister."

        case .climate:
            guard climateKnown, let measuredAt = climateStatusAt else {
                return "Klima durumu bilinmiyor."
            }
            let answer = climateOn ? "Klima açık." : "Klima kapalı."
            guard Date().timeIntervalSince(measuredAt) >= 300 else { return answer }
            return answer + " Son veri \(voiceAge(measuredAt))."

        case .charging:
            let label = chargingLabel
            return label == "—" ? "Şarj durumu bilinmiyor." : "Şarj durumu: \(label)." + voiceCloudAgeNote()

        case .tirePressure:
            guard let telemetry, telemetry.tirePressureAvailable, !telemetry.tires.isEmpty else {
                return "Lastik basıncı verisi yok."
            }
            let readings = telemetry.tires.map { tire in
                "\(tire.position.title) \(tire.pressurePSI.map(voiceDecimal) ?? "—")"
            }
            return "Lastik basınçları: " + readings.joined(separator: ", ") + " PSI." + voiceCloudAgeNote()

        case .outsideTemperature:
            guard let temperature = telemetry?.outsideTemperatureC, temperature.isFinite else {
                return "Dış sıcaklık bilgisi yok."
            }
            return "Dış sıcaklık \(voiceDecimal(temperature)) derece." + voiceCloudAgeNote()

        case .odometer:
            guard let kilometers = telemetry?.odometerKM, kilometers.isFinite else {
                return "Odometre bilgisi yok."
            }
            return "Odometre \(Int(kilometers.rounded())) kilometre." + voiceCloudAgeNote()

        case .auxiliaryBattery:
            guard let percent = telemetry?.auxiliaryBatteryPercent, percent.isFinite else {
                return "12 V akü bilgisi yok."
            }
            if let assessment = AuxiliaryBatteryPolicy.assess(percent) {
                let level = assessment.isCritical ? "Dikkat: 12 V akü kritik düşük" : "Not: 12 V akü zayıf"
                return "\(level), yüzde \(assessment.percent). Şarj ve bakım kontrolü önerilir." + voiceCloudAgeNote()
            }
            return "12 V akü yüzde \(Int(percent.rounded()))." + voiceCloudAgeNote()
        }
    }

    private func voiceAge(_ date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 2 { return "az önce" }
        if seconds < 60 { return "\(seconds) saniye önce" }
        return "\(seconds / 60) dakika önce"
    }

    /// Bulut telemetrisi 5 dakikadan eskiyse yanıta verinin yaşını ekler.
    private func voiceCloudAgeNote() -> String {
        guard let updatedAt else { return "" }
        let seconds = Date().timeIntervalSince(updatedAt)
        guard seconds >= 300 else { return "" }
        if seconds < 3_600 {
            return " Son veri \(max(1, Int(seconds / 60))) dakika önce."
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "d MMMM HH:mm"
        return " Son veri \(formatter.string(from: updatedAt))."
    }

    private func voiceDecimal(_ value: Double) -> String {
        TurkishFormat.decimal(value, digits: 1)
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
                .accessibilityLabel("\(item.title) sekmesi")
                .accessibilityValue(tab == item ? "Seçili" : "")
                .accessibilityAddTraits(tab == item ? .isSelected : [])
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
        if CertificateCache.loadCertificate(vin: vehicle.vin, phonePublicKeyHex: hex) != nil { return }
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
        print("[CLIMATE] status query start vin=…\(vehicle.vin.suffix(4))")
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

    /// Soğuk başlıkta ağ yanıtı gelmeden önce son bilinen bulut değerini
    /// gösterir. Yalnızca gösterim: lastik uyarısı ve sürüş istatistiği gibi
    /// yan etkiler taze veri geldikten sonra çalışır, eski değerle tetiklenmez.
    /// Kartın "Güncellendi HH:mm" satırı gerçeği söylemeye devam eder; eskiyse
    /// "Son Telemetri" rozetine döner.
    @MainActor
    private func showLastKnownCloudTelemetryIfNeeded() {
        guard telemetry == nil, let cachedAt = model.cloud.updatedAt else { return }
        let summary = CloudSnapshot(
            batteryPercent: model.cloud.batteryPercent,
            rangeKM: model.cloud.rangeKM,
            outsideTemperatureC: model.cloud.outsideTemperatureC,
            auxiliaryBatteryPercent: model.cloud.auxiliaryBatteryPercent,
            odometerKM: model.cloud.odometerKM,
            chargingState: model.cloud.chargingState,
            updatedAt: cachedAt
        )
        telemetry = VehicleTelemetry(summary: summary)
        updatedAt = cachedAt
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
            facingError = nil
            if let odo = parsed.odometerKM {
                drivingStats.record(odometer: odo, batteryPercent: parsed.batteryPercent)
            }
            checkTirePressure(parsed.tires)
            checkAuxiliaryBattery(parsed.auxiliaryBatteryPercent)
            model.noteCloudTelemetry(parsed)
        } catch is CancellationError {
            return
        } catch {
            self.facingError = .from(error)
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
    let onOpenVoice: () -> Void
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

                Button(action: onOpenVoice) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(ToggTheme.teal)
                        .frame(width: 34, height: 30)
                        .background(RoundedRectangle(cornerRadius: 8).fill(ToggTheme.surfaceVariant))
                }
                .accessibilityLabel("Sesli komut")
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
                    if vehicle.isShared {
                        Label("Paylaşılan araç · sahip devri yok", systemImage: "person.2.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(ToggTheme.teal)
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
                                            Label(item.isShared ? "\(item.title) · Paylaşılan" : item.title,
                                                  systemImage: item.isShared ? "person.2.fill" : "checkmark")
                                        } else {
                                            Text(item.isShared ? "\(item.title) · Paylaşılan" : item.title)
                                        }
                                    }
                                }
                            }
                            Divider()
                        }
                        Button("Araç detayı", systemImage: "info.circle") { onOpenDetail() }
                        Button("Servis kartı", systemImage: "wrench.and.screwdriver") { onOpenService() }
                        Button("Seyahatname", systemImage: "chart.xyaxis.line") { onOpenExperience() }
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
    /// `nil` = veri yok ("—"); 0 = gerçek araç verisi.
    let battery: Int?
    let range: Int?
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
                    Image(systemName: lockBadge.icon).font(.subheadline)
                    Text(lockBadge.text).font(.footnote.weight(.bold))
                }
                .foregroundStyle(lockBadge.color)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 12).fill(lockBadge.color.opacity(0.15)))

                Spacer()

                Text(updatedCaption)
                    .font(.caption2).foregroundStyle(ToggTheme.muted)
            }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "gauge.with.dots.needle.50percent")
                            .font(.body).foregroundStyle(ToggTheme.teal)
                        Text("KALAN MENZİL")
                            .font(.footnote.weight(.semibold)).foregroundStyle(ToggTheme.muted)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(range.map { "\($0)" } ?? "—")
                            .font(.largeTitle.weight(.black)).foregroundStyle(.white)
                        Text("KM")
                            .font(.body.weight(.bold)).foregroundStyle(ToggTheme.teal)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill").font(.body).foregroundStyle(batteryColor)
                        Text(battery.map { "%\($0)" } ?? "—")
                            .font(.title3.weight(.bold)).foregroundStyle(batteryColor)
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
                    if let battery {
                        Capsule().fill(batteryColor)
                            .frame(width: geo.size.width * CGFloat(min(max(battery, 0), 100)) / 100)
                    }
                }
            }
            .frame(height: 8)

            HStack(spacing: 16) {
                HStack(spacing: 5) {
                    Image(systemName: "gauge")
                        .font(.footnote).foregroundStyle(ToggTheme.orange)
                    Text(odometer.map { "\($0.formatted(.number.precision(.fractionLength(0)))) km" } ?? "— km")
                        .font(.footnote.weight(.semibold)).foregroundStyle(ToggTheme.muted)
                }
                HStack(spacing: 5) {
                    Image(systemName: "thermometer.medium")
                        .font(.footnote).foregroundStyle(ToggTheme.cyan)
                    Text(outsideTemperature.map { "\(Int($0.rounded()))°C" } ?? "—°C")
                        .font(.footnote.weight(.semibold)).foregroundStyle(ToggTheme.muted)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Araç durumu")
        .accessibilityValue(accessibilitySummary)
    }

    /// Güncellenme satırı: taze veride saat, eski veride toplu yaş bilgisi.
    /// Verinin ne kadar önce geldiği dolaysız yazılır; hiç yoksa "Veri
    /// bekleniyor" yazılır, 0'a sıkıştırılmış sahte değer gösterilmez.
    private var updatedCaption: String {
        guard let updatedAt else { return "Veri bekleniyor" }
        let time = updatedAt.formatted(date: .omitted, time: .shortened)
        let seconds = Date().timeIntervalSince(updatedAt)
        guard seconds >= 300 else { return "Güncellendi \(time)" }
        if seconds < 3_600 {
            return "Güncellendi \(time) · \(max(1, Int(seconds / 60))) dk önce"
        }
        if seconds < 86_400 {
            return "Güncellendi \(time) · \(max(1, Int(seconds / 3_600))) sa önce"
        }
        let day = updatedAt.formatted(.dateTime.day().month(.abbreviated).hour().minute())
        return "Güncellendi \(day)"
    }

    private var accessibilitySummary: String {
        let lockText = lockBadge.text.lowercased()
        let rangeText = range.map { "\($0) kilometre menzil" } ?? "menzil bilgisi yok"
        let batteryText = battery.map { "batarya yüzde \($0)" } ?? "batarya bilgisi yok"
        let odometerText = odometer.map { "kilometre \(Int($0.rounded()))" } ?? "kilometre bilgisi yok"
        let temperatureText = outsideTemperature.map { "dış sıcaklık \(Int($0.rounded())) derece" } ?? "dış sıcaklık bilgisi yok"
        return [lockText, rangeText, batteryText, odometerText, temperatureText].joined(separator: ", ")
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(active ? "\(subtitle), açık" : subtitle)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Premium kontroller

private struct PremiumControlsSection: View {
    let onWindowCommand: (DashboardCommand) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Cam ve Güvenlik")
                .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 12) {
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

                HStack(spacing: 10) {
                    Image(systemName: "sun.max")
                        .font(.system(size: 17)).foregroundStyle(ToggTheme.muted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Panoramik cam tavan").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Araç protokolünde komut yok").font(.system(size: 10))
                            .foregroundStyle(ToggTheme.muted)
                    }
                    Spacer()
                    Text("Desteklenmiyor")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(ToggTheme.muted)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(ToggTheme.muted.opacity(0.15)))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(ToggTheme.surfaceVariant))

                HStack(spacing: 10) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 17)).foregroundStyle(ToggTheme.muted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nöbetçi (Sentry) güvenlik").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Araç API'sinde açma/kapama yok").font(.system(size: 10))
                            .foregroundStyle(ToggTheme.muted)
                    }
                    Spacer()
                    Text("Desteklenmiyor")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(ToggTheme.muted)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(ToggTheme.muted.opacity(0.15)))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(ToggTheme.surfaceVariant))
            }
            .padding(18)
            .toggCardBackground(24)

            Text("Yan cam komutları onay ister; araç cam konumunu BLE ile doğrulamıyor. Panoramik tavan ve sentry bu uygulamada komut olarak sunulmaz.")
                .font(.caption2).foregroundStyle(ToggTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
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
                    Text("\(TurkishFormat.decimal(temperature, digits: 1))°C")
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
                Text("Klima açılırken hedef \(TurkishFormat.decimal(temperature, digits: 1))°C uygulanır.")
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
    /// "Son 3 gün (12 V): %72 · %74 · —" satırı; kayıt yoksa nil.
    let auxiliaryHistoryLine: String?
    let tires: [TireReading]
    let insideTemperature: Double?
    let brakeWarning: Bool?
    let engineWarning: Bool?
    let driveMode: String?
    let chargingState: String
    let updatedAt: Date?

    @State private var showTireSettings = false
    @State private var tireLowThreshold = TirePressurePolicy.default.lowThresholdPSI

    private var tirePressureAvailable: Bool {
        tires.contains { $0.pressurePSI != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // 12 V akü düşükse belirgin uyarı bandı.
            // Kural: AuxiliaryBatteryPolicy.assess; eksik veri asla uyarıya
            // dönüştürülmez ("—" gösteriminde kalır).
            if let batteryAlert = AuxiliaryBatteryPolicy.assess(auxiliaryBattery) {
                batteryAlertBanner(batteryAlert)
            }

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
                HStack {
                    Text("Lastik Basınçları (TPMS - PSI)")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(ToggTheme.muted)
                    Spacer()
                    Button {
                        withAnimation(.snappy) { showTireSettings.toggle() }
                    } label: {
                        Label("Eşik", systemImage: "slider.horizontal.3")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ToggTheme.teal)
                }
                HStack(spacing: 10) {
                    tireBox(.frontLeft)
                    tireBox(.frontRight)
                    tireBox(.rearLeft)
                    tireBox(.rearRight)
                }
                if showTireSettings {
                    tireThresholdEditor
                } else {
                    Text(tireThresholdSummary)
                        .font(.system(size: 9)).foregroundStyle(ToggTheme.muted)
                }
                if !tirePressureAvailable {
                    Text("Lastik basıncı verisi şu an gelmiyor. Araç uyanıkken tekrar deneyin; eksik değer 0 PSI olarak gösterilmez.")
                        .font(.system(size: 9)).foregroundStyle(ToggTheme.orange)
                }
            }

            HStack(spacing: 12) {
                statBox(title: "12 V Akü", value: auxiliaryBattery.map { "%\(Int($0.rounded()))" } ?? "—",
                        icon: "car.battery", color: ToggTheme.teal)
                statBox(title: "Şarj Durumu", value: chargingState,
                        icon: "bolt.circle", color: ToggTheme.cyan)
            }

            if let auxiliaryHistoryLine {
                Text(auxiliaryHistoryLine)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(ToggTheme.muted)
                    .accessibilityLabel("Son üç gün 12 volt akü geçmişi")
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

    private var tireThresholdSummary: String {
        let policy = TirePressureSettings().policy
        return "Uyarı eşiği \(Int(policy.lowThresholdPSI.rounded())) PSI · kritik \(Int(policy.criticalThresholdPSI.rounded())) PSI"
    }

    private var tireThresholdEditor: some View {
        let policy = TirePressureSettings().policy
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Uyarı eşiği").font(.system(size: 10)).foregroundStyle(ToggTheme.muted)
                Spacer()
                Text("\(Int(tireLowThreshold.rounded())) PSI")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(ToggTheme.teal)
            }
            Slider(
                value: $tireLowThreshold,
                in: TirePressurePolicy.minimumAllowedThreshold...TirePressurePolicy.maximumAllowedThreshold,
                step: 1
            ) { editing in
                if !editing { saveTireThreshold() }
            }
            .tint(ToggTheme.teal)
            Text("Kritik eşik otomatik olarak \(Int(max(TirePressurePolicy.minimumAllowedThreshold, tireLowThreshold - 4).rounded())) PSI olur. Değerler PSI'dır.")
                .font(.system(size: 9)).foregroundStyle(ToggTheme.muted)
            Button("Varsayılana dön (\(Int(TirePressurePolicy.default.lowThresholdPSI)) PSI)") {
                tireLowThreshold = TirePressurePolicy.default.lowThresholdPSI
                saveTireThreshold()
            }
            .font(.system(size: 10)).buttonStyle(.bordered)
        }
        .onAppear { tireLowThreshold = policy.lowThresholdPSI }
    }

    private func saveTireThreshold() {
        let policy = TirePressurePolicy(
            lowThresholdPSI: tireLowThreshold,
            criticalThresholdPSI: tireLowThreshold - 4
        )
        TirePressureSettings().policy = policy
    }

    private func tireBox(_ position: TirePosition) -> some View {
        let reading = tires.first { $0.position == position }
        let severity = reading.flatMap { TirePressureSettings().policy.severity(for: $0) }
        let tint: Color = severity == .critical ? ToggTheme.pink : (severity == .low ? ToggTheme.orange : .white)
        return VStack(spacing: 4) {
            Image(systemName: severity == nil ? "car.side.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 15))
                .foregroundStyle(severity == nil ? ToggTheme.teal : tint)
            Text(reading?.pressurePSI.map { "\(TurkishFormat.decimal($0, digits: 1)) PSI" } ?? "— PSI")
                .font(.system(size: 13, weight: .bold)).foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(reading?.temperatureC.map { "\(Int($0.rounded()))°C" } ?? "—°C")
                .font(.system(size: 10)).foregroundStyle(ToggTheme.muted)
            Text(position.title).font(.system(size: 9)).foregroundStyle(ToggTheme.muted)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14).fill(ToggTheme.surfaceVariant))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(position.title)
        .accessibilityValue(tireAccessibilityValue(reading, severity: severity))
    }

    private func tireAccessibilityValue(_ reading: TireReading?, severity: TirePressurePolicy.Severity?) -> String {
        guard let reading, let psi = reading.pressurePSI else { return "basınç bilgisi yok" }
        let pressure = "\(TurkishFormat.decimal(psi, digits: 1)) PSI"
        let temperature = reading.temperatureC.map { ", \(Int($0.rounded())) derece" } ?? ""
        let warning: String
        switch severity {
        case .critical: warning = ", kritik düşük basınç"
        case .low: warning = ", düşük basınç"
        case nil: warning = ""
        }
        return pressure + temperature + warning
    }

    /// 12 V akü uyarı bandı: uyarı "belirgin" olması için kartın en üstünden
    /// başlar, renk (kritik: kırmızı, uyarı: turuncu) ve kalın metinle
    /// ayrışır; ekran okuyucu için tam cümle etiketi içerir. VIN/token
    /// içermez; mesafe/menzil iddiası taşımaz.
    @ViewBuilder
    private func batteryAlertBanner(_ assessment: AuxiliaryBatteryAssessment) -> some View {
        let critical = assessment.isCritical
        let color: Color = critical ? ToggTheme.red : ToggTheme.orange
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: critical ? "battery.0percent" : "battery.25percent")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(color)
                Text(critical ? "12 V Akü Kritik Düşük" : "12 V Akü Zayıf")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(color)
                Spacer()
                Text("%\(assessment.percent)")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(color)
            }
            Text(critical
                 ? "12 V akü %\(assessment.percent). Uzun parklarda araç açılmayabilir; en kısa sürede şarj/bakım kontrolü önerilir."
                 : "12 V akü %\(assessment.percent). Yakında şarj/bakım kontrolü önerilir.")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(color.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(color.opacity(0.8), lineWidth: 1.5)
                )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(critical ? "Uyarı: 12 volt akü kritik düşük" : "Uyarı: 12 volt akü zayıf")
        .accessibilityValue("Akü yüzde \(assessment.percent)")
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(warning == nil ? "bilgi yok" : (active ? "uyarı var" : "uyarı yok"))
    }
}

// MARK: - Giriş ekranı

private struct BLESetupGuideStep: Identifiable {
    let number: Int
    let title: String
    let narration: String
    var id: Int { number }

    static let all: [BLESetupGuideStep] = [
        .init(number: 1, title: "Aracın yanına gel", narration: "Aracın yanında dur. iPhone Bluetooth'unun açık olduğundan emin ol ve Toqdas uygulamasını ekranda açık tut."),
        .init(number: 2, title: "Bağlantıyı başlat", narration: "Dashboard'daki Bluetooth Dijital Anahtar kartında bağlan düğmesine dokun. Araç bulunup GATT servisleri keşfedilirken telefonu araçtan uzaklaştırma."),
        .init(number: 3, title: "Eşleştirmeyi araçtan başlat", narration: "Araç ekranı dijital anahtar eşleştirmesi isterse işlemi araç ekranından başlat. iPhone'da bir eşleştirme kodu görünürse kodları karşılaştırıp onayla."),
        .init(number: 4, title: "Kimlik doğrulamayı bekle", narration: "Sertifika ve imzalı kimlik doğrulaması sürerken uygulama ekranında kal. Araç anahtarı eksik uyarısı görünürse araca komut gönderilmez."),
        .init(number: 5, title: "Yeşil durumu doğrula", narration: "Bluetooth Dijital Anahtar kartında yeşil Bağlı, Komut hazır yazısını bekle. Komutlar yalnızca bağlantı hazır ve imzalı araç verisi güncelse gönderilebilir. Arka planda araç komutu gönderilmez.")
    ]
}

private struct BLESetupGuideSheet: View {
    @ObservedObject var ble: BleConnection
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speaker = BLESetupVoiceGuide()
    @State private var stepIndex = 0

    private var step: BLESetupGuideStep { BLESetupGuideStep.all[stepIndex] }

    private var liveStatus: String {
        if ble.needsRepair { return "iPhone ve araç eşleşmesi sıfırlanmalı." }
        if ble.pairingRequired { return "Araç anahtarı eksik; eşleştirmeyi araç ekranından başlat." }
        if ble.state.isReady { return "Bağlı · Komut hazır" }
        return ble.state.description
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ToggTheme.background.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Text("ADIM \(step.number) / \(BLESetupGuideStep.all.count)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(ToggTheme.teal)
                        Spacer()
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .foregroundStyle(ble.state.isReady ? ToggTheme.green : ToggTheme.teal)
                    }

                    Text(step.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                    Text(step.narration)
                        .font(.system(size: 15))
                        .foregroundStyle(ToggTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Circle().fill(ble.state.isReady ? ToggTheme.green : ToggTheme.orange)
                            .frame(width: 8, height: 8)
                        Text(liveStatus)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(ble.state.isReady ? ToggTheme.green : ToggTheme.orange)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(ToggTheme.surfaceVariant))

                    Button {
                        speaker.speak(step.narration)
                    } label: {
                        Label("Bu adımı seslendir", systemImage: "speaker.wave.2.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity, minHeight: 46)
                            .background(RoundedRectangle(cornerRadius: 14).fill(ToggTheme.teal))
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 12) {
                        Button("Önceki") {
                            speaker.stop()
                            stepIndex = max(0, stepIndex - 1)
                        }
                        .disabled(stepIndex == 0)

                        Button(stepIndex == BLESetupGuideStep.all.count - 1 ? "Baştan dinle" : "Sonraki · dinle") {
                            let nextIndex = stepIndex == BLESetupGuideStep.all.count - 1 ? 0 : stepIndex + 1
                            stepIndex = nextIndex
                            speaker.speak(BLESetupGuideStep.all[nextIndex].narration)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ToggTheme.teal)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .trailing)

                    Text("Ses cihazda üretilir. Mikrofon açılmaz; ses kaydı veya transkript gönderilmez.")
                        .font(.system(size: 10))
                        .foregroundStyle(ToggTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
                .padding(20)
            }
            .navigationTitle("Dijital anahtar kurulumu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
        .onDisappear { speaker.stop() }
    }
}

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
                .accessibilityIdentifier("login.toggButton")

                if model.busy { ProgressView().tint(ToggTheme.teal) }
                if let facingError = model.facingError {
                    ErrorBanner(error: facingError,
                                onRetry: { Task { await model.refresh() } },
                                onDismiss: { model.facingError = nil })
                }
                Spacer()
                Text("Togg ID ve araç bilgileri üretim servislerini kullanır.")
                    .font(.caption2).foregroundStyle(ToggTheme.muted)
            }
            .padding(24)
        }
    }
}
