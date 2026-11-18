import LocalAuthentication
import SwiftUI
import UIKit
import UserNotifications

/// Alt menü: her sekmenin **tek işi** var. İklimlendirme ayrı sekme değil,
/// "Araç → Tüm kontroller" derinliğinde (klima sık kullanılan bir eylem
/// olarak hızlı karolarda da duruyor).
enum DashboardTab: String, CaseIterable, Identifiable {
    case vehicle, energy, care, account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vehicle: return "Araç"
        case .energy: return "Enerji"
        case .care: return "Bakım"
        case .account: return "Hesap"
        }
    }

    var icon: String {
        switch self {
        case .vehicle: return "car.side.fill"
        case .energy: return "bolt.car.fill"
        case .care: return "wrench.and.screwdriver.fill"
        case .account: return "person.crop.circle"
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

// PremiumControlsSection (App/Dashboard/PremiumControlsSection.swift) bu
// komutları parametre olarak alır; erişim düzeyi internal'e açıldı.
enum DashboardCommand: String, Identifiable {
    case lock, unlock, trunkOpen, trunkClose, windowsOpen, windowsClose
    case automaticLockOn, automaticLockOff

    var id: String { rawValue }

    var detail: String {
        switch self {
        case .lock: return "Kapılar kilitlenecek; kilit onaylanınca camlar kapatılmaya çalışılacak. Cam konumu doğrulanamaz, açık cam kalmış olabilir."
        case .unlock: return "Kapı kilitleri açılacak."
        case .trunkOpen: return "Arka bagaj açılacak."
        case .trunkClose: return "Arka bagaj kapatılacak."
        case .windowsOpen: return "Yan cam açma komutu gönderilecek. Park hâlinde açık cam bırakmayın (yağmur/hırsızlık riski). Cam konumu doğrulanamaz; çevrede engel olmadığından emin olun."
        case .windowsClose: return "Yan cam kapatma komutu gönderilecek. Cam konumu ayrıca doğrulanamayabilir; çevrede engel olmadığından emin olun."
        case .automaticLockOn: return "Yakınlık otomasyonu etkinleştirilecek. Bu onay araç komutu göndermez; yaklaşma/uzaklaşma otomasyonu yönetilir."
        case .automaticLockOff: return "Yakınlık otomasyonu kapatılacak; araca komut gönderilmez."
        }
    }
}

struct DashboardView: View {
    @ObservedObject var model: GarageModel
    let vehicle: Vehicle
    @AppStorage(StorageKeys.theme) private var themeName = ToggThemeStyle.corporate.rawValue
    @AppStorage(StorageKeys.dashboardLayout) private var layoutName = DashboardLayoutStyle.classic.rawValue

    @EnvironmentObject private var ble: BleConnection
    /// Reduce Motion: kaydırma/büyüme animasyonlarını kapatır (U3).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var tab: DashboardTab = .vehicle
    @State private var telemetry: VehicleTelemetry?
    @State private var updatedAt: Date?
    @State private var busy = false
    @State private var error: String?
    @State private var facingError: UserFacingError?
    @State private var geofenceNotice: String?
    @State private var showCommands = false
    @State private var showQuickStart = false
    @State private var showDesignPreview = false
    @State private var showAllControls = false
    @State private var showEnergyDetails = false
    @State private var showCareDiagnostics = false
    /// Son **imzalı** kilit/bagaj/sürüş özeti (diskten). BLE oturumu
    /// kapandığında ekran "hiç yok" yerine "son bilinen + yaş" gösterir.
    @State private var stateSnapshot: VehicleStateSnapshot?
    @State private var showOnboarding = false
    @AppStorage("toqdas.onboarding.seen.v1") private var onboardingSeen = false
    @State private var showDetail = false
    @State private var showDiscovery = false
    @State private var showService = false
    @State private var showExperience = false
    @State private var showStations = false
    @State private var showBLESetupGuide = false
    @State private var authBusy = false
    @State private var showRepairConfirm = false
    @State private var showKeyDiscovery = false
    @State private var alert: DashboardAlert?
    @State private var hasAuthenticatedBLE = false
    @State private var certificateProvenance: CertificateProvenance?
    @AppStorage(GaragePreferences.keepConnectedKey) private var keepBLEConnected = false
    @State private var proximityEnabled = false
    @StateObject private var voice = VoiceAssistant()
    @State private var showVoice = false
    @State private var voiceSourcedConfirm = false
    @State private var proximityProfile: ProximityProfile = .balanced
    @State private var proximityNearSample: Int?
    @State private var proximityFarSample: Int?
    @State private var proximityCalibrationSavedAt: Date?
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
    @State private var showScenarioGuide = false
    @State private var scenarioGuideSection: ScenarioSection?
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

        // Aynı lastik için günde bir kez bildirim (`NotificationDedupe`).
        let vin = vehicle.vin
        var notifiedAny = false
        for alert in alerts {
            let key = StorageKeys.tireNotified(vin, position: alert.position.rawValue, severity: String(describing: alert.severity))
            guard notificationDedupe.shouldNotify(key: key) else { continue }
            notificationDedupe.record(key: key)
            notifiedAny = true
        }
        guard notifiedAny else { return }

        NotificationPoster.requestAuthorization(using: notificationPoster)
        let critical = alerts.contains { $0.severity == .critical }
        let detail = alerts
            .sorted { $0.pressurePSI < $1.pressurePSI }
            .map { "\($0.position.title) \(TurkishFormat.decimal($0.pressurePSI, digits: 0)) PSI" }
            .joined(separator: ", ")
        NotificationPoster.post(
            NotificationPoster.Draft(
                identifier: "tire-pressure-\(vin)",
                title: critical ? "Kritik lastik basıncı" : "Lastik basıncı uyarısı",
                body: "\(detail). Eşik: \(Int(policy.lowThresholdPSI.rounded())) PSI."
            ),
            using: notificationPoster
        )
    }
    @State private var proximityAutoOffEnabled = false
    @State private var proximityAutoOffMinutes = 30
    @State private var proximityAutoOffCustomText = "30"
    @State private var proximityAutoOffDeadline: Date?
    @State private var proximityAutoOffStatus = ""
    @State private var proximityAutoOffTask: Task<Void, Never>?
    @State private var pendingAutoLockTask: Task<Void, Never>?
    @State private var awaitingProximityLockConfirmation = false
    /// Otomatik yakınlık komutunun sonucu beklenirken türü ve zamanı;
    /// yalnız 60 sn içindeki sonuç bildirime dönüşür (manuel komutlar hariç).
    @State private var pendingAutomaticCommandKind: ProximityCommandNotice.Kind?
    @State private var pendingAutomaticCommandAt: Date?
    @State private var lastLockSoundCount: Int?
    /// Uzaklaşınca kilitleme bileti: araç, dijital anahtar güçlü sinyaldeyken
    /// kilit komutunu onaylayıp uygulamıyor (ölçüm 2026-11-17: yakın 7/7 red,
    /// uzak 6/6 uygulama). Bilet, tek komutu sinyal zayıfladığı an gönderir.
    @State private var deferredLockTicket: DeferredLockTicket?
    @State private var deferredLockStatus: String?
    /// Bilet son tarihi diske yazılır; uygulama askıya alınsa da kaybolmaz.
    private var deferredLockSettings: DeferredLockSettings {
        DeferredLockSettings(store: UserDefaults.standard)
    }

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
            onOpenAccount: { tab = .account },
            onOpenDetail: { showDetail = true },
            onOpenDiscovery: { showDiscovery = true },
            onOpenScenarioGuide: {
                scenarioGuideSection = nil
                showScenarioGuide = true
            },
            onOpenDesignPreview: { showDesignPreview = true },
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

                    switch tab {
                    case .vehicle: vehicleTab
                    case .energy: energyTab
                    case .care: careTab
                    case .account: accountTab
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
                        showEnergyDetails = true
                        scheduleScrollChargingCalculator(proxy: proxy)
                    }
                            if let arg = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("-openTab=") }),
                       let value = DashboardTab(rawValue: String(arg.dropFirst("-openTab=".count))) {
                        tab = value
                    }
                    if ProcessInfo.processInfo.arguments.contains("-scrollCamControls") {
                        showAllControls = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            withAnimation(reduceMotion ? nil : .default) {
                                proxy.scrollTo("windows.section", anchor: .top)
                            }
                        }
                    }
                    if ProcessInfo.processInfo.arguments.contains("-scrollQuickActions") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            withAnimation { proxy.scrollTo("quickActions", anchor: .top) }
                        }
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
        .task {
            loadProximitySettings()
            loadCertificateProvenance()
        }
        .task {
            restoreDeferredLockTicketIfNeeded()
            showLastKnownCloudTelemetryIfNeeded()
        }
        .onAppear {
            // Saatten gelen otomasyon anahtarı panodaki geçiş mantığına
            // delegasyon: dönen değer kalibrasyon geçerliyse true.
            // DashboardView bir struct: kopya aynı @State deposunu paylaşır,
            // bu nedenle kapanış doğrudan metodu çağırabilir.
            model.proximityToggleHandler = { enabled in
                setProximityEnabled(enabled)
            }
        }
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
            processDeferredLockTicket(value)
        }
        .onReceive(ble.$lastEvent) { event in
            guard proximityEnabled,
                  let outcome = ProximityCommandNotice.outcome(forEvent: event) else { return }
            proximityStatus = event
            handleAutomaticCommandOutcome(outcome)
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
        .onReceive(ble.$telemetry) { telemetry in
            guard let telemetry else { return }
            VehicleStateSnapshotStore.save(telemetry, vin: vehicle.vin)
            stateSnapshot = VehicleStateSnapshotStore.load(vin: vehicle.vin)
        }
        .onReceive(ble.$lastCommandReceipt) { receipt in
            guard let receipt else { return }
            // Komutun imzalı telemetri sonucu widget + saat kaydına yazılır.
            // Bağlantı komuttan hemen sonra kopsa bile saat "doğrulanamadı"
            // görür; sessiz kaybolma yok. Yön eşleşmesi: "Kilidi aç" →
            // "Kilit açma"; "Kilitle"/cam akışı → "Kilitleme".
            let action = receipt.action.lowercased()
            let matchesLock: (String) -> Bool = { label in
                let l = label.lowercased()
                if action.contains("kilidi aç") { return l.contains("kilit aç") }
                if action.contains("kilit") { return l.contains("kilit") && !l.contains("aç") }
                return false
            }
            switch receipt.phase {
            case .verified:
                // Yayın, depo değişikliğini dinleyen tek noktadan yapılır.
                VehicleCommandStatusStore.markVerified(
                    true, ifLabelMatches: matchesLock, note: receipt.note
                )
            case .failed:
                VehicleCommandStatusStore.markVerified(false, ifLabelMatches: matchesLock)
            default:
                break
            }
        }
        .onAppear {
            // Palet göçü: eski değer (togg/ocean/graphite) seçicide karşılık
            // bulamaz; kurumsala yazılır ki VoiceOver doğru seçiliyi bildirsin.
            if !ToggThemeStyle.selectable.contains(where: { $0.rawValue == themeName }) {
                themeName = ToggThemeStyle.corporate.rawValue
            }
            stateSnapshot = VehicleStateSnapshotStore.load(vin: vehicle.vin)
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-seedStateSnapshot"),
               stateSnapshot == nil {
                let seeded = BleTelemetry(locked: 1, doors: [0, 0, 0, 0], trunkAjar: 0,
                                          powerState: 3, counter: 1,
                                          receivedAt: Date().addingTimeInterval(-7_200))
                VehicleStateSnapshotStore.save(seeded, vin: vehicle.vin)
                stateSnapshot = VehicleStateSnapshotStore.load(vin: vehicle.vin)
            }
            #endif
            // İlk açılış tanıtımı: bir kez; UI testlerinde atlanır.
            let args = ProcessInfo.processInfo.arguments
            if !onboardingSeen,
               !args.contains("-uiTestFixture"),
               !args.contains("-uiTestSignedOut"),
               !args.contains("-skipOnboarding") {
                showOnboarding = true
            }
        }
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-openDriveExperience") {
                showExperience = true
            }
            if ProcessInfo.processInfo.arguments.contains("-openChargingTab")
                || ProcessInfo.processInfo.arguments.contains("-scrollChargingCalculator") {
                tab = .energy
                // Hesaplayıcı artık "Geçmiş ve araçlar" derinliğinde: test için aç.
                showEnergyDetails = true
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
            climateSettings.setTarget(value, vin: vehicle.vin)
        }
        .onChange(of: vehicle.vin) { _ in
            // Araç değişince klima durumu eski araçtan taşınmaz: eski
            // aracın <90 sn "taze" durumuyla yeni araca komut gitmesin.
            // Hedef yeni aracın kaydından yüklenir; komut gönderilmez.
            climateOn = false
            climateKnown = false
            climateStatusAt = nil
            climatePending = nil
            climateNote = nil
            loadClimateTarget()
            Task { await refreshClimate() }
        }
        .onChange(of: proximityProfile) { profile in
            proximitySettings.setProfileRaw(profile.rawValue, vin: vehicle.vin)
            if !proximityEnabled, let calibration = proximityCalibration, calibration.isValid {
                proximityGate = ProximityGate(calibration: calibration, profile: profile)
                proximityGuard = ProximityCycleGuard()
                proximityLatencyMeter = ProximityLatencyMeter()
                proximityLastLatency = nil
            }
        }
        .onChange(of: proximityAutoOffMinutes) { value in
            proximitySettings.setAutoOffMinutes(value, vin: vehicle.vin)
        }
        .onChange(of: proximityAutoOffCustomText) { value in
            if let minutes = Int(value), (1...1440).contains(minutes) {
                proximitySettings.setAutoOffCustomMinutes(minutes, vin: vehicle.vin)
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
            Text("Uygulama ekrandayken yeni yaklaşma algılanırsa kilit açılır. Uzaklaşınca, tüm kapılar kapalı ve araç beklemedeyse kilitleme komutu gönderilir; kilit onaylanınca camlar da kapatılmaya çalışılır. Cam konumu telemetride yok, bu yüzden sonuç doğrulanamaz. Arka planda araç komutu gönderilmez.")
        }
        .sheet(isPresented: $showVoice) {
            VoiceSheet(voice: voice) { text in
                handleVoiceUtterance(text)
            }
        }
        .sheet(isPresented: $showBLESetupGuide) {
            BLESetupGuideSheet(ble: ble)
        }
        .sheet(isPresented: $showKeyDiscovery) {
            KeyDiscoveryView(ble: ble, vin: vehicle.vin)
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
        .sheet(isPresented: $showScenarioGuide, onDismiss: { scenarioGuideSection = nil }) {
            ScenarioGuideSheet(
                initialSection: scenarioGuideSection,
                live: ScenarioLiveStatus(
                    bleReady: ble.state.isReady,
                    automationEnabled: proximityEnabled,
                    calibrationValid: proximityCalibration?.isValid,
                    telemetryFresh: updatedAt.map { Date().timeIntervalSince($0) < 300 }
                )
            )
        }
        .sheet(isPresented: $showOnboarding) {
            FirstRunSheet()
                .onDisappear { onboardingSeen = true }
        }
        .sheet(isPresented: $showDesignPreview) {
            DesignPreviewView()
        }
        .sheet(isPresented: $showQuickStart) {
            QuickStartView()
                .environmentObject(ble)
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
    }

    // MARK: - Sekmeler

    /// "Araç": durum → öncelik → eylem. İlk ekranda en fazla beş blok;
    /// geri kalan her şey "Tüm kontroller" derinliğinde (aşamalı açıklama).
    private var vehicleTab: some View {
        VStack(spacing: blockSpacing) {
            bleSecurityBanner
            statusHero
            prioritiesSection
            quickActions
            lastCommandCard
            controlsSection
        }
    }

    /// Yoğunluk tercihi: eski "düzen" seçimi (Klasik/Sportif/Teknik) gevşek,
    /// "Sade" sıkı ritme eşlenir. Düzen sırası artık dinamik (öncelik motoru).
    private var compactDensity: Bool {
        (DashboardLayoutStyle(rawValue: layoutName) ?? .classic) == .minimal
    }

    private var blockSpacing: CGFloat {
        compactDensity ? DSSpace.xs : DSSpace.md
    }

    // MARK: - Durum şeridi

    private var telemetryAgeSeconds: TimeInterval? {
        ble.telemetry.map { Date().timeIntervalSince($0.receivedAt) }
    }

    /// 45 sn üstü gerçekten bayat; 15–45 sn normal dönem arasıdır
    /// (imzalı telemetri ~30 sn aralıklı gelir).
    private var heroStatus: DSStatus {
        guard let age = telemetryAgeSeconds else { return .waiting }
        if age < 45 { return .fresh }
        if age < 300 { return .waiting }
        return .stale
    }

    /// Etkin durum: canlı imzalı telemetri → diskteki son bilinen → bilinmiyor.
    private var effectiveLocked: Bool? { ble.telemetry?.isLocked ?? stateSnapshot?.isLocked }
    private var effectiveTrunkAjar: Bool? {
        ble.telemetry.map { $0.trunkAjar == 1 } ?? stateSnapshot?.isTrunkAjar
    }
    private var effectivePowerState: Int? { ble.telemetry?.powerState ?? stateSnapshot?.powerState }

    private var lockValueText: String {
        switch effectiveLocked {
        case true: return "Kilitli"
        case false: return "Kilit açık"
        default: return "Kilit bilinmiyor"
        }
    }

    private var heroFooter: String {
        if ble.state.isReady {
            return "Komut onayı uygulandı anlamına gelmez; sonuç imzalı telemetriden doğrulanır."
        }
        if let snapshot = stateSnapshot {
            let age = LastSeenSummary.relative(snapshot.observedAt, Date())
            return "Kilit/bagaj yalnız BLE oturumunda okunur. Gösterilen değer \(age) alınan imzalı telemetriden."
        }
        return "Komutlar için dijital anahtar ve taze imzalı durum gerekir."
    }

    private var auxiliaryValueText: String {
        guard let aux = telemetry?.auxiliaryBatteryPercent else { return "—" }
        return AuxiliaryBatteryPolicy.percentText(aux) ?? "—"
    }

    private var auxiliaryTint: Color {
        guard let assessment = AuxiliaryBatteryPolicy.assess(telemetry?.auxiliaryBatteryPercent) else {
            return telemetry?.auxiliaryBatteryPercent == nil ? ToggTheme.muted : ToggTheme.green
        }
        return assessment.severity == .critical ? ToggTheme.red : ToggTheme.orange
    }

    private var statusHero: some View {
        let summary = LastSeenSummary.make(ble: ble.telemetry?.receivedAt, cloud: updatedAt)
        return StatusHero(
            eyebrow: vehicleBadge.uppercased(),
            title: lockValueText,
            subtitle: summary.map { "\($0.relativeText) · \($0.sourceText)" } ?? "Henüz araç verisi alınmadı",
            status: energyStatus,
            metrics: [
                HeroMetric(label: "Batarya", value: battery.map { "%\($0)" } ?? "—",
                           icon: "battery.75", tint: batteryColor),
                HeroMetric(label: "Menzil", value: range.map { "\($0) km" } ?? "—",
                           icon: "road.lanes"),
                HeroMetric(label: "12 V", value: auxiliaryValueText,
                           icon: "bolt.batteryblock", tint: auxiliaryTint)
            ],
            footer: heroFooter,
            primaryTitle: ble.state.isReady ? "Veriyi yenile" : "Araç servisine bağlan",
            primaryIcon: ble.state.isReady ? "arrow.clockwise" : "antenna.radiowaves.left.and.right",
            primaryAction: {
                if ble.state.isReady {
                    Task { await refresh() }
                } else {
                    toggleConnection()
                }
            }
        )
        .dsAppear(index: 0, reduceMotion: reduceMotion)
    }

    // MARK: - Öncelikler ("şimdi ne önemli")

    private var priorityInputs: DashboardPriorities.Inputs {
        var inputs = DashboardPriorities.Inputs()
        inputs.linkReady = ble.state.isReady
        inputs.lastSeenText = LastSeenSummary.make(
            ble: ble.telemetry?.receivedAt, cloud: updatedAt).map {
                "\($0.relativeText) · \($0.sourceText)"
            }
        inputs.telemetryAge = telemetryAgeSeconds
        if let receipt = ble.lastCommandReceipt, receipt.phase == .failed {
            inputs.commandUnverifiedDetail = receipt.detail
                ?? receipt.failureReason?.explanation
        }
        inputs.auxiliaryPercent = telemetry?.auxiliaryBatteryPercent
        let live = model.chargingLive
        inputs.chargingActive = live?.charging == true
        if let target = model.chargingTarget {
            inputs.chargingTargetRemaining = ChargingTargetPolicy.remaining(
                target: target, percent: telemetry?.batteryPercent).map { Int($0.rounded()) }
            if let live, live.charging {
                inputs.chargingEtaText = liveRemainingText(live: live, now: Date())
            }
        }
        inputs.openDoorCount = ble.telemetry?.openDoorCount ?? 0
        inputs.trunkAjar = ble.telemetry?.trunkAjar == 1
        inputs.powerState = ble.telemetry?.powerState
        inputs.weakSignal = ble.rssi.map { $0 <= BleReconnectPolicy.weakSignalThreshold } ?? false
        return inputs
    }

    @ViewBuilder
    private var prioritiesSection: some View {
        let items = DashboardPriorities.make(priorityInputs)
        if items.isEmpty {
            EmptyState(icon: "checkmark.circle",
                       title: "Şimdi acil bir şey yok",
                       message: "Bağlantı, 12 V ve son komut durumu normal görünüyor. Ayrıntılar \"Tüm kontroller\" altında.")
        } else {
            VStack(alignment: .leading, spacing: DSSpace.xs) {
                SectionHeader(title: "Şimdi önemli", subtitle: "En fazla üç başlık")
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    PriorityCard(
                        title: item.title,
                        detail: item.detail,
                        icon: priorityIcon(item.kind),
                        severity: prioritySeverity(item.severity),
                        actionTitle: item.actionTitle,
                        action: { handlePriority(item.kind) }
                    )
                    .dsAppear(index: index, reduceMotion: reduceMotion)
                }
            }
        }
    }

    private func priorityIcon(_ kind: DashboardPriorities.Kind) -> String {
        switch kind {
        case .connectionLost: return "wifi.slash"
        case .auxiliaryCritical: return "bolt.batteryblock"
        case .lockUnverified: return "questionmark.circle"
        case .doorOpen: return "door.left.hand.open"
        case .telemetryStale: return "clock.badge.exclamationmark"
        case .weakSignal: return "antenna.radiowaves.left.and.right"
        case .chargingTarget: return "bolt.car"
        case .readyToDrive: return "steeringwheel"
        }
    }

    private func prioritySeverity(_ severity: DashboardPriorities.Severity) -> DSStatus {
        switch severity {
        case .critical: return .critical
        case .warning: return .unverified
        case .info: return .waiting
        }
    }

    private func handlePriority(_ kind: DashboardPriorities.Kind) {
        switch kind {
        case .connectionLost:
            if !ble.state.isReady { toggleConnection() }
        case .lockUnverified:
            showCommands = true
        case .chargingTarget:
            tab = .energy
        case .readyToDrive:
            showQuickStart = true
        default:
            break
        }
    }

    // MARK: - Son komut

    @ViewBuilder
    private var lastCommandCard: some View {
        if let receipt = ble.lastCommandReceipt {
            VStack(alignment: .leading, spacing: DSSpace.xs) {
                SectionHeader(title: "Son komut",
                              subtitle: TurkishFormat.date(receipt.updatedAt, format: "HH:mm"))
                VStack(spacing: DSSpace.xs) {
                    DataRow(label: receipt.action,
                            value: receipt.phase == .verified ? "Doğrulandı"
                                 : (receipt.phase == .failed ? "Doğrulanamadı" : "Bekliyor"),
                            detail: receipt.note
                                ?? receipt.detail
                                ?? receipt.failureReason?.explanation,
                            tint: receipt.phase == .verified ? DSColor.positive
                                 : (receipt.phase == .failed ? DSColor.warning : DSColor.muted))
                    if receipt.phase == .failed {
                        Text(receipt.failureReason?.explanation
                             ?? "Araç gerekçe bildirmiyor.")
                            .font(ToggTheme.text(.micro))
                            .foregroundStyle(DSColor.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(DSSpace.md)
                .dsCard()
            }
        }
    }

    // MARK: - Tüm kontroller (aşamalı açıklama)

    private var controlsSection: some View {
        VStack(spacing: DSSpace.sm) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    showAllControls.toggle()
                }
            } label: {
                HStack(spacing: DSSpace.xs) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(DSColor.accent)
                    Text("Tüm kontroller")
                        .font(ToggTheme.text(.body, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(showAllControls ? "Gizle" : "Klima, cam, yakınlık, güvenlik")
                        .font(ToggTheme.text(.micro))
                        .foregroundStyle(DSColor.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Image(systemName: showAllControls ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DSColor.muted)
                }
                .padding(DSSpace.sm)
                .dsCard()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("vehicle.allControls")

            if showAllControls {
                controlsContent
            }
        }
    }

    private var controlsContent: some View {
        VStack(spacing: DSSpace.md) {
            climateCardBlock
            deferredLockRow
            PremiumControlsSection(onWindowCommand: requestWindowCommand)
                .id("windows.section")
            proximityCard
            geofenceCard
            lastSeenCard
            bleCard
        }
    }

    private var climateCardBlock: some View {
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

    /// "Enerji": şarj + hedef + geçmiş + 12 V maliyeti. Kart sırası sabittir
    /// (canlı oturum her zaman üstte).
    private var energyTab: some View {
        VStack(spacing: blockSpacing) {
            energyHero
            liveChargingCard
            chargingTargetCard
            ChargingBudgetCard(vin: vehicle.vin)
            energyDetails
        }
    }

    /// Enerji durum şeridi: şarj hâli, batarya, hedef ve hedefe kalan.
    /// Hiçbir komut göndermez; değer yoksa "—" / "Kapalı" der.
    private var energyHero: some View {
        let summary = LastSeenSummary.make(ble: ble.telemetry?.receivedAt, cloud: updatedAt)
        return StatusHero(
            eyebrow: "ENERJİ",
            title: chargingHeroTitle,
            subtitle: summary.map { "\($0.relativeText) · \($0.sourceText)" } ?? "Henüz veri alınmadı",
            status: heroStatus,
            statusDetail: heroStatus.text,
            metrics: [
                HeroMetric(label: "Batarya", value: battery.map { "%\($0)" } ?? "—",
                           icon: "battery.75", tint: batteryColor),
                HeroMetric(label: "Hedef", value: model.chargingTarget.map { "%\($0)" } ?? "Kapalı",
                           icon: "target"),
                HeroMetric(label: "Kalan", value: remainingToTargetText,
                           icon: "flag.checkered")
            ],
            footer: "Enerji (kWh/kW) telemetrisi gelmiyor; yüzdeler bulut veya imzalı telemetriden. Uygulama şarjı durdurmaz.",
            primaryTitle: "Veriyi yenile",
            primaryIcon: "arrow.clockwise",
            primaryAction: { Task { await refresh() } }
        )
        .dsAppear(index: 0, reduceMotion: reduceMotion)
    }

    private var chargingHeroTitle: String {
        if model.chargingLive?.charging == true { return "Şarj sürüyor" }
        let label = chargingLabel
        guard label != "—" else { return "Şarj durumu bilinmiyor" }
        return label
    }

    /// Şarj durumu: canlı oturum → şarj sürüyor/yok; veri yoksa "Bekleniyor".
    private var energyStatus: DSStatus {
        if model.chargingLive?.charging == true { return .charging }
        if chargingLabel == "—" { return .waiting }
        return .idle
    }

    private var remainingToTargetText: String {
        guard let target = model.chargingTarget,
              let remaining = ChargingTargetPolicy.remaining(
                target: target, percent: telemetry?.batteryPercent) else { return "—" }
        return "%\(Int(remaining.rounded()))"
    }

    /// Geçmiş, hesaplama ve istasyonlar ilk ekranı doldurmasın: aşamalı açılır.
    private var energyDetails: some View {
        VStack(spacing: DSSpace.sm) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    showEnergyDetails.toggle()
                }
            } label: {
                HStack(spacing: DSSpace.xs) {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(DSColor.accent)
                    Text("Geçmiş ve araçlar")
                        .font(ToggTheme.text(.body, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer(minLength: DSSpace.xs)
                    Text(showEnergyDetails ? "Gizle" : "Geçmiş, hesaplama, istasyonlar")
                        .font(ToggTheme.text(.micro))
                        .foregroundStyle(DSColor.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Image(systemName: showEnergyDetails ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DSColor.muted)
                }
                .padding(DSSpace.sm)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .dsCard()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("energy.details")

            if showEnergyDetails {
                VStack(spacing: DSSpace.md) {
                    chargingHistoryCard
                    chargingCalculator
                    seyahatnameLink
                    trugoStations
                }
            }
        }
    }

    private var seyahatnameLink: some View {
        Button { showExperience = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "chart.bar.xaxis")
                    .font(ToggTheme.text(.lead)).foregroundStyle(ToggTheme.teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Seyahatname")
                        .font(ToggTheme.text(.body, weight: .bold)).foregroundStyle(.white)
                    Text("Yolculuk, şarj ve karşılaştırma kayıtları")
                        .font(ToggTheme.text(.micro)).foregroundStyle(ToggTheme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(ToggTheme.text(.caption, weight: .bold)).foregroundStyle(ToggTheme.muted)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .dsCard()
        }
        .buttonStyle(.plain)
    }

    /// "Bakım": sağlık + servis + sürüş istatistikleri + tanı.
    private var careTab: some View {
        VStack(spacing: blockSpacing) {
            careHero
            healthTab
            MaintenanceCard(vin: vehicle.vin, odometer: telemetry?.odometerKM)
            drivingStatsCard
            careDetails
        }
    }

    /// Bakım durum şeridi: tek bakışta "bir şey var mı". Uyarı yoksa
    /// "Araç sağlıklı" der; veri yoksa susmaz, "Sağlık verisi yok" der.
    private var careHero: some View {
        let summary = LastSeenSummary.make(ble: ble.telemetry?.receivedAt, cloud: updatedAt)
        return StatusHero(
            eyebrow: "BAKIM",
            title: healthHeadline,
            subtitle: summary.map { "\($0.relativeText) · \($0.sourceText)" } ?? "Henüz veri alınmadı",
            status: careStatus,
            metrics: [
                HeroMetric(label: "12 V", value: telemetry?.auxiliaryBatteryPercent.map { "%\(Int($0.rounded()))" } ?? "—",
                           icon: "car.battery", tint: careAuxiliaryTint),
                HeroMetric(label: "Lastik", value: lowestTirePSI.map { "\(Int($0.rounded())) PSI" } ?? "—",
                           icon: "circle.dashed", tint: careTireTint),
                HeroMetric(label: "İç sıcaklık", value: telemetry?.insideTemperatureC.map { String(format: "%.1f °C", $0) } ?? "—",
                           icon: "thermometer.medium")
            ],
            footer: "12 V ve lastik değerleri imzalı telemetriden gelir; eksik değer \"—\" kalır, 0'a çevrilmez.",
            primaryTitle: "Veriyi yenile",
            primaryIcon: "arrow.clockwise",
            primaryAction: { Task { await refresh() } }
        )
        .dsAppear(index: 0, reduceMotion: reduceMotion)
    }

    private var lowestTirePSI: Double? {
        (telemetry?.tires ?? []).compactMap(\.pressurePSI).min()
    }

    private var healthHeadline: String {
        if telemetry?.brakeWarning == true { return "Fren uyarısı var" }
        if telemetry?.engineWarning == true { return "Motor uyarısı var" }
        if let aux = telemetry?.auxiliaryBatteryPercent, aux < 40 { return "12 V akü zayıf" }
        if let low = lowestTirePSI, low < TirePressurePolicy.default.lowThresholdPSI {
            return "Lastik basıncı düşük"
        }
        guard telemetry != nil else { return "Sağlık verisi yok" }
        // Uyarı yokluğu "sağlıklı" demek için yeterli değil: lastik gelmiyorsa söyle.
        guard lowestTirePSI != nil else { return "Lastik verisi yok" }
        return "Araç sağlıklı"
    }

    private var careStatus: DSStatus {
        if telemetry?.brakeWarning == true || telemetry?.engineWarning == true { return .critical }
        if let aux = telemetry?.auxiliaryBatteryPercent, aux < 40 { return .critical }
        if let low = lowestTirePSI, low < TirePressurePolicy.default.criticalThresholdPSI { return .critical }
        return heroStatus
    }

    private var careAuxiliaryTint: Color {
        guard let aux = telemetry?.auxiliaryBatteryPercent else { return DSColor.muted }
        if aux >= 60 { return DSColor.positive }
        if aux >= 40 { return DSColor.warning }
        return DSColor.negative
    }

    private var careTireTint: Color {
        guard let low = lowestTirePSI else { return DSColor.muted }
        if low < TirePressurePolicy.default.criticalThresholdPSI { return DSColor.negative }
        if low < TirePressurePolicy.default.lowThresholdPSI { return DSColor.warning }
        return DSColor.positive
    }

    /// Tanı ve bağlantı ayrıntısı ilk ekranı doldurmasın.
    private var careDetails: some View {
        VStack(spacing: DSSpace.sm) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    showCareDiagnostics.toggle()
                }
            } label: {
                HStack(spacing: DSSpace.xs) {
                    Image(systemName: "waveform.path.ecg").foregroundStyle(DSColor.accent)
                    Text("Tanı ve bağlantı")
                        .font(ToggTheme.text(.body, weight: .bold))
                        .foregroundStyle(.white)
                    Spacer(minLength: DSSpace.xs)
                    Text(showCareDiagnostics ? "Gizle" : "BLE tanısı, olaylar")
                        .font(ToggTheme.text(.micro))
                        .foregroundStyle(DSColor.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Image(systemName: showCareDiagnostics ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DSColor.muted)
                }
                .padding(DSSpace.sm)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .dsCard()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("care.diagnostics")

            if showCareDiagnostics {
                technicalOverview
            }
        }
    }

    private var accountTab: some View {
        NavigationStack {
            AccountCenterView(api: model.api)
        }
    }

    private var healthTab: some View {
        VehicleHealthCard(
            auxiliaryBattery: telemetry?.auxiliaryBatteryPercent,
            auxiliaryTrend: auxiliaryTrend,
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

    /// "Son görülme": araçla en son iletişim (BLE veya bulut, en yeni
    /// kanal). Hiç iletişim yoksa düz metin; asla 0 dakika önce yazılmaz.
    private var lastSeenCard: some View {
        let summary = LastSeenSummary.make(
            ble: ble.telemetry?.receivedAt,
            cloud: updatedAt)
        return HStack(spacing: 12) {
            ZStack {
                Circle().fill(ToggTheme.teal.opacity(0.18)).frame(width: 34, height: 34)
                Image(systemName: "eye")
                    .foregroundStyle(ToggTheme.teal)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Son görülme")
                    .font(ToggTheme.text(.caption)).foregroundStyle(ToggTheme.muted)
                if let summary {
                    Text("\(summary.relativeText) · \(summary.sourceText)")
                        .font(ToggTheme.text(.body, weight: .semibold)).foregroundStyle(.white)
                } else {
                    Text("Araç henüz görülmedi")
                        .font(ToggTheme.text(.body, weight: .semibold)).foregroundStyle(.white)
                }
            }
            Spacer()
        }
        .padding(16)
        .dsCard()
        .id("lastSeenCard")
        .accessibilityElement(children: .combine)
    }

    private var bleCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(bleStatusColor.opacity(0.2)).frame(width: 38, height: 38)
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(ToggTheme.text(.headline)).foregroundStyle(bleStatusColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Bluetooth Dijital Anahtar")
                        .font(ToggTheme.text(.lead, weight: .bold)).foregroundStyle(.white)
                    Text(bleStateTitle)
                        .font(ToggTheme.text(.caption))
                        .foregroundStyle(ble.state.isReady && !model.silentRecovery ? ToggTheme.green : ToggTheme.muted)
                }
                Spacer()
                Circle().fill(bleStatusColor).frame(width: 9, height: 9)
            }

            if !model.silentRecovery {
                if let summary = ble.failureSummary, ble.state.isFailed {
                    Label(summary, systemImage: "exclamationmark.triangle.fill")
                        .font(ToggTheme.text(.caption, weight: .semibold))
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
                    .font(ToggTheme.text(.caption, weight: .semibold))
                    .foregroundStyle(ToggTheme.teal)
            }
            .buttonStyle(.plain)
            // 44 pt dokunma hedefi düğmenin kendisinde (erişilebilirlik denetimi).
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())

            if let rssi = ble.rssi {
                Text("Bağlantı sinyali: \(rssi) dBm")
                    .font(ToggTheme.text(.micro)).foregroundStyle(ToggTheme.muted)
            }

            if ble.needsRepair {
                VStack(alignment: .leading, spacing: 6) {
                    Label(PairingRecovery.title, systemImage: "exclamationmark.triangle.fill")
                        .font(ToggTheme.text(.caption, weight: .bold)).foregroundStyle(ToggTheme.orange)
                    Text(PairingRecovery.summary)
                        .font(ToggTheme.text(.micro)).foregroundStyle(ToggTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(Array(PairingRecovery.steps.enumerated()), id: \.offset) { index, step in
                        Text("\(index + 1). \(step)")
                            .font(ToggTheme.text(.micro)).foregroundStyle(ToggTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button {
                        model.link.retryAfterRepair()
                    } label: {
                        Label("Adımları tamamladım, yeniden dene", systemImage: "arrow.clockwise")
                            .font(ToggTheme.text(.caption, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ToggTheme.orange)
                    .padding(.top, 4)
                    .accessibilityHint("iPhone ve araç tarafında eşleşmeyi yenilediysen bağlantıyı tekrar dener")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(ToggTheme.orange.opacity(0.12)))
                .accessibilityElement(children: .contain)
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
                        .font(ToggTheme.text(.body)).foregroundStyle(powerStateColor(telemetry))
                    Text("Güç durumu")
                        .font(ToggTheme.text(.caption, weight: .semibold)).foregroundStyle(ToggTheme.muted)
                    Spacer()
                    Text(telemetry.powerStateText)
                        .font(ToggTheme.text(.caption, weight: .bold)).foregroundStyle(powerStateColor(telemetry))
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 10).fill(ToggTheme.surfaceVariant))
                .accessibilityElement(children: .combine)
            }

            HStack(spacing: 10) {
                Button { toggleConnection() } label: {
                    Label(connectTitle,
                          systemImage: ble.state.isDisconnected || ble.state.isFailed
                            ? "antenna.radiowaves.left.and.right" : "xmark.circle")
                        .font(ToggTheme.text(.caption, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 44)
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
                    .font(ToggTheme.text(.caption, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(RoundedRectangle(cornerRadius: 14).fill(ToggTheme.surfaceVariant))
                }
                .buttonStyle(.plain)
                .disabled(!(ble.state.isCertificate || ble.state.isChallenge) || authBusy)
            }

            if let line = digitalKeyStatusLine {
                Label(line, systemImage: "checkmark.seal")
                    .font(ToggTheme.text(.micro))
                    .foregroundStyle(ToggTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(line)
            }

            if !ble.state.isReady {
                Button { showRepairConfirm = true } label: {
                    Label("Dijital anahtarı yeniden eşleştir", systemImage: "arrow.triangle.2.circlepath")
                        .font(ToggTheme.text(.caption, weight: .semibold))
                        .foregroundStyle(ToggTheme.teal)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())

                Button { showKeyDiscovery = true } label: {
                    Label("Cihaz ortamında aday seç", systemImage: "list.bullet.rectangle")
                        .font(ToggTheme.text(.caption, weight: .semibold))
                        .foregroundStyle(ToggTheme.teal)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
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
                        .font(ToggTheme.text(.caption, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right").font(ToggTheme.text(.caption))
                }
                .foregroundStyle(ToggTheme.teal)
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .dsCard()
    }

    private var proximityCard: some View {
        let calibration = proximityCalibration
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Yakınlıkla Kapı Kilidi", systemImage: "dot.radiowaves.left.and.right")
                    .font(ToggTheme.text(.lead, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    scenarioGuideSection = .proximity
                    showScenarioGuide = true
                } label: {
                    Image(systemName: "book")
                        .font(ToggTheme.text(.lead))
                        .foregroundStyle(ToggTheme.teal)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Yakınlık senaryoları")
                .accessibilityIdentifier("proximity.scenarios")
                Button {
                    showProximityGuide = true
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(ToggTheme.text(.lead))
                        .foregroundStyle(ToggTheme.teal)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Yakınlık kalibrasyon rehberi")
                .accessibilityIdentifier("proximity.calibration")
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
                .font(ToggTheme.text(.caption, weight: .medium))
                .foregroundStyle(proximityEnabled ? ToggTheme.teal : ToggTheme.muted)

            if let savedAt = proximityCalibrationSavedAt,
               ProximityCalibrationAge.needsRefresh(savedAt) {
                Label(ProximityCalibrationAge.message(
                    days: ProximityCalibrationAge.daysSince(savedAt)),
                      systemImage: "clock.arrow.circlepath")
                    .font(ToggTheme.text(.micro))
                    .foregroundStyle(ToggTheme.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button { captureProximitySample(isNear: true) } label: {
                    Label("Yakında ölç", systemImage: "figure.walk")
                        .font(ToggTheme.text(.caption, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(RoundedRectangle(cornerRadius: 12).fill(ToggTheme.teal))
                }
                .buttonStyle(.plain)
                .disabled(proximityEnabled || !ble.state.isReady || ble.rssi == nil)

                Button { captureProximitySample(isNear: false) } label: {
                    Label("Uzakta ölç", systemImage: "figure.walk.departure")
                        .font(ToggTheme.text(.caption, weight: .bold))
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
                .font(ToggTheme.text(.micro))
                .foregroundStyle(proximityProfile == .fast || proximityProfile == .aggressive
                                 ? ToggTheme.orange : ToggTheme.muted)

            Toggle("Kilit doğrulandıktan sonra otomasyonu kapat", isOn: Binding(
                get: { proximityAutoOffEnabled },
                set: { setProximityAutoOffEnabled($0) }
            ))
            .font(ToggTheme.text(.caption, weight: .medium))
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
                            .font(ToggTheme.text(.micro)).foregroundStyle(ToggTheme.muted)
                        TextField("30", text: $proximityAutoOffCustomText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 72)
                    }
                }

                if !proximityAutoOffStatus.isEmpty {
                    Text(proximityAutoOffStatus)
                        .font(ToggTheme.text(.micro))
                        .foregroundStyle(ToggTheme.muted)
                }
                Text("Sayaç ilk doğrulanmış otomatik kilitten sonra başlar. Süre dolunca araca komut gönderilmez; iOS uygulamayı arka planda askıya alırsa kapanma gecikebilir.")
                    .font(ToggTheme.text(.micro))
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
                        .font(ToggTheme.text(.micro))
                        .foregroundStyle(ToggTheme.muted)
                } else {
                    Text("Ölçümler arasında en az 14 dB fark olmalı; aynı telefon konumuyla yeniden ölçün.")
                        .font(ToggTheme.text(.micro))
                        .foregroundStyle(ToggTheme.orange)
                }
            } else {
                Text("Önce araç yanında, sonra araçtan birkaç metre uzakta ölçüm alın.")
                    .font(ToggTheme.text(.micro))
                    .foregroundStyle(ToggTheme.muted)
            }

            let backgroundLog = ProximityDetectionMonitor.transitionsLog(for: vehicle.vin)
            if !backgroundLog.isEmpty {
                Text("Son geçişler (arka plan; yalnızca algılama)")
                    .font(ToggTheme.text(.micro, weight: .semibold))
                    .foregroundStyle(ToggTheme.muted)
                ForEach(backgroundLog.suffix(4).reversed()) { entry in
                    Text("\(entry.at.formatted(date: .omitted, time: .shortened)) · \(entry.approached ? "Yaklaşma" : "Uzaklaşma") · \(entry.rssi) dBm")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(ToggTheme.muted)
                }
            }

            Text("Kilit komutları yalnızca uygulama ekrandayken ve araç bağlantısı ile güncel araç durumu hazırken gönderilir. Arka planda yalnızca algılama yapılır: geçişler günlüğe yazılır, bildirim düşer, araca komut gönderilmez.")
                .font(ToggTheme.text(.micro))
                .foregroundStyle(ToggTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text("Tepki profilleri iOS RSSI örnekleme hızına göre uyarlanmıştır; Android filtresinin birebir kopyası değildir.")
                .font(ToggTheme.text(.micro))
                .foregroundStyle(ToggTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .dsCard()
    }

    private var geofenceCard: some View {
        let readiness = model.geofence.readiness
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Geofence (Ev/iş)", systemImage: "location.circle")
                    .font(ToggTheme.text(.lead, weight: .bold)).foregroundStyle(.white)
                Spacer()
                Text(geofenceStatusBadge)
                    .font(ToggTheme.text(.micro, weight: .bold))
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
                .font(ToggTheme.text(.caption, weight: .semibold)).buttonStyle(.bordered)

                if model.geofence.homeCoordinate != nil {
                    Button("Konumu sil") { model.geofence.clearHomeLocation() }
                        .font(ToggTheme.text(.caption)).buttonStyle(.bordered).tint(ToggTheme.pink)
                }
            }

            HStack {
                Text("Bölge yarıçapı").font(ToggTheme.text(.micro)).foregroundStyle(ToggTheme.muted)
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
                Text(error).font(ToggTheme.text(.micro)).foregroundStyle(ToggTheme.pink)
            } else if let notice = geofenceNotice ?? (!readiness.canEnable ? readiness.message : nil) {
                Text(notice).font(ToggTheme.text(.micro)).foregroundStyle(ToggTheme.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(readiness.message).font(ToggTheme.text(.micro)).foregroundStyle(ToggTheme.muted)
            }

            Text("Konum yalnızca cihazda kullanılır. Arka planda komut gönderilmez; bölgeye girince/çıkınca uygulama uyanır ve komut READY + taze telemetri koşuluna tabidir.")
                .font(ToggTheme.text(.micro)).foregroundStyle(ToggTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18).dsCard()
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
                    .font(ToggTheme.text(.lead, weight: .bold)).foregroundStyle(.white)
                Spacer()
                Text(monthTitle(stats.month)).font(ToggTheme.text(.micro)).foregroundStyle(ToggTheme.muted)
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(Int(stats.km.rounded())) km")
                        .font(ToggTheme.text(.title, weight: .bold)).foregroundStyle(ToggTheme.teal)
                    Text("Bu ay · \(stats.daysWithData) gün veri")
                        .font(.caption).foregroundStyle(ToggTheme.muted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(TurkishFormat.decimal(stats.estimatedCostTRY, digits: 0)) ₺")
                        .font(ToggTheme.text(.title, weight: .bold)).foregroundStyle(ToggTheme.orange)
                    Text("\(TurkishFormat.decimal(stats.estimatedKWh, digits: 1)) kWh \(stats.consumptionIsMeasured ? "" : "tahmini")")
                        .font(.caption).foregroundStyle(ToggTheme.muted)
                }
            }
            Divider().overlay(ToggTheme.muted.opacity(0.2))
            HStack {
                Text("Son 7 gün").font(.caption).foregroundStyle(ToggTheme.muted)
                Spacer()
                Text(stats.daysWithData > 0 ? "\(Int(weekKm.rounded())) km" : "—")
                    .font(ToggTheme.text(.body, weight: .semibold)).foregroundStyle(.white)
            }
            HStack {
                Text("Tüketim").font(.caption).foregroundStyle(ToggTheme.muted)
                Spacer()
                Text(consumptionText(stats))
                    .font(ToggTheme.text(.body, weight: .semibold)).foregroundStyle(.white)
            }
            Text(stats.daysWithData > 1
                 ? (stats.consumptionIsMeasured
                    ? "Tüketim batarya yüzdesi farkından ölçülür (88,5 kWh batarya). Maliyet \(priceText) varsayımıyla, kayıp yok."
                    : "Tüketim için yeterli batarya ölçümü yok; 17 kWh/100 km varsayılanı kullanılıyor. Maliyet \(priceText) varsayımıyla, kayıp yok.")
                 : "Yeterli veri yok. Birkaç günlük odometer ve batarya okumasından sonra km, tüketim ve maliyet hesaplanır.")
                .font(ToggTheme.text(.micro)).foregroundStyle(ToggTheme.muted)
        }
        .padding(18).dsCard()
    }

    var technicalOverview: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Label("Canlı BLE Tanısı", systemImage: "waveform.path.ecg")
                    .font(ToggTheme.text(.caption, weight: .bold))
                    .foregroundStyle(ToggTheme.teal)
                Spacer()
                Text(ble.state.description)
                    .font(ToggTheme.text(.micro, weight: .semibold))
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
                    .font(ToggTheme.text(.micro))
                    .foregroundStyle(ToggTheme.muted)
            }
            if !ble.diagnosticEvents.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Son olaylar").font(ToggTheme.text(.micro, weight: .semibold)).foregroundStyle(ToggTheme.muted)
                    ForEach(Array(ble.diagnosticEvents.suffix(5).reversed())) { event in
                        HStack(spacing: 6) {
                            Text(event.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(ToggTheme.muted)
                            Text(event.message)
                                .font(ToggTheme.text(.micro, weight: .medium))
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
                        .font(ToggTheme.text(.micro, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(14)
        .dsCard()
    }

    func technicalMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(ToggTheme.text(.micro, weight: .semibold)).foregroundStyle(ToggTheme.muted)
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
                    .font(ToggTheme.text(.body, weight: .bold))
                    .foregroundStyle(ToggTheme.pink)
                Text(warning)
                    .font(ToggTheme.text(.caption, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Uyarı güncel, imzalı BLE araç durumuna dayanıyor.")
                    .font(ToggTheme.text(.micro))
                    .foregroundStyle(ToggTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(ToggTheme.pink.opacity(0.14)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(ToggTheme.pink.opacity(0.35), lineWidth: 1))
        }
    }

    private var bleStatusColor: Color {
        if ble.state.isReady && model.silentRecovery { return ToggTheme.orange }
        return ToggTheme.color(for: ble.state.visualTone)
    }

    private var bleStateTitle: String {
        // Eşleştirme bekleme "Yeniden bağlanıyor…" maskesinin altında kalmasın:
        // kullanıcının araç ekranında yapması gereken işlem açıkça görünsün.
        if ble.pairingRequired || ble.state.isPairingWait {
            return "Araç eşleştirmesi bekleniyor · araç ekranından eşleştirmeyi başlat"
        }
        if model.silentRecovery { return "Yeniden bağlanıyor…" }
        // Tek kaynak: koordinatörün faz modeli (string/boolean karışımı yok).
        let phase = model.link.phase
        if phase == .ready { return "Bağlı · Komut hazır" }
        return phase.label
    }

    private var connectTitle: String {
        if ble.state.isDisconnected { return "Araç servisine bağlan" }
        if ble.state.isFailed { return "Yeniden bağlan" }
        return "Bağlantıyı kes"
    }

    private func statusPill(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(ToggTheme.text(.caption))
            Text(text).font(ToggTheme.text(.caption, weight: .bold))
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
                .font(ToggTheme.text(.body)).foregroundStyle(open ? ToggTheme.pink : ToggTheme.green)
            Text("Kapı \(index + 1)")
                .font(ToggTheme.text(.micro, weight: .semibold)).foregroundStyle(ToggTheme.muted)
            Text(open ? "Açık" : "Kapalı")
                .font(ToggTheme.text(.micro, weight: .bold)).foregroundStyle(open ? ToggTheme.pink : ToggTheme.green)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(ToggTheme.surfaceVariant))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Kapı \(index + 1)")
        .accessibilityValue(open ? "Açık" : "Kapalı")
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
            keepBLEConnected = true
            model.link.configure(vin: vehicle.vin, isShared: vehicle.isShared)
            // Kullanıcı açıkça bağlanmak istedi: onarım kilidi açılabilir.
            model.link.start(clearRepair: true)
        } else {
            keepBLEConnected = false
            model.link.stop()
        }
    }

    /// Dijital anahtarın kaynağını tazele (önbellek / yenilendi / ilk kez).
    @MainActor
    private func loadCertificateProvenance() {
        certificateProvenance = CertificateProvenanceStore().load(vin: vehicle.vin)
    }

    /// "Anahtar tekrar alındı mı?" sorusunun görünür yanıtı.
    private var digitalKeyStatusLine: String? {
        guard let provenance = certificateProvenance else { return nil }
        let hex = PhoneKeyStore.publicKeyHex(for: vehicle.vin) ?? ""
        let days = CertificateCache.cachedLifecycle(vin: vehicle.vin, phonePublicKeyHex: hex)?.daysRemaining
        return CertificateProvenance.summary(provenance, daysRemaining: days)
    }

    private func loadProximitySettings() {
        // 2026-11-18: agresif profil saniyede bir zıplayan yaklaşma/uzaklaşma
        // üretti; kayıtlı agresif bir kez Dengeli'ye çekilir.
        proximitySettings.migrateAggressiveProfileOnce(vin: vehicle.vin)
        if let profile = proximitySettings.profile(vin: vehicle.vin) {
            proximityProfile = profile
        }
        proximityAutoOffEnabled = proximitySettings.autoOffEnabled(vin: vehicle.vin)
        if let minutes = proximitySettings.autoOffMinutes(vin: vehicle.vin) {
            proximityAutoOffMinutes = minutes
        }
        if let custom = proximitySettings.autoOffCustomMinutes(vin: vehicle.vin) {
            proximityAutoOffCustomText = String(custom)
        }
        proximityAutoOffDeadline = proximitySettings.autoOffDeadline(vin: vehicle.vin)
        if !proximityAutoOffEnabled {
            proximityAutoOffDeadline = nil
            proximitySettings.setAutoOffDeadline(nil, vin: vehicle.vin)
        }
        proximityNearSample = proximitySettings.nearSample(vin: vehicle.vin)
        proximityFarSample = proximitySettings.farSample(vin: vehicle.vin)
        proximityCalibrationSavedAt = proximitySettings.calibrationSavedAt(vin: vehicle.vin)
        let requested = preferences.proximityEnabled(for: vehicle.vin)
        if requested, proximityAutoOffEnabled,
           let deadline = proximityAutoOffDeadline,
           ProximityAutoOffPolicy.isExpired(deadline, now: Date()) {
            preferences.setProximityEnabled(false, for: vehicle.vin)
            proximitySettings.setAutoOffDeadline(nil, vin: vehicle.vin)
            proximityAutoOffDeadline = nil
            proximityEnabled = false
            proximityAutoOffStatus = "Süre doldu; otomasyon kapatıldı, komut gönderilmedi."
            proximityStatus = proximityAutoOffStatus
            return
        }
        guard requested, let calibration = proximityCalibration, calibration.isValid else {
            proximityEnabled = false
            ble.setProximityRSSIPollInterval(nil)
            preferences.setProximityEnabled(false, for: vehicle.vin)
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
            withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo("chargingCalculator", anchor: .top) }
        }
    }

    @MainActor
    private func resetProximityCalibration() {
        proximityNearSample = nil
        proximityFarSample = nil
        proximityCalibrationSavedAt = nil
        proximityGate = nil
        proximitySettings.clearCalibration(vin: vehicle.vin)
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
            proximitySettings.setNearSample(sample, vin: vehicle.vin)
            proximityStatus = "Yakın ölçüm kaydedildi: \(sample) dBm"
        } else {
            proximityFarSample = sample
            proximitySettings.setFarSample(sample, vin: vehicle.vin)
            proximityStatus = "Uzak ölçüm kaydedildi: \(sample) dBm"
        }
        // Ölçüm anı kaydedilir: eskime uyarısı (30 gün) bundan hesaplanır.
        let savedAt = Date()
        proximityCalibrationSavedAt = savedAt
        proximitySettings.setCalibrationSavedAt(savedAt, vin: vehicle.vin)

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
    /// Dönen değer: geçiş uygulandı mı (saat isteği için; kalibrasyon
    /// geçersizse açma yapılmaz ve false döner).
    @discardableResult
    private func setProximityEnabled(_ enabled: Bool) -> Bool {
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
            proximitySettings.setAutoOffDeadline(nil, vin: vehicle.vin)
            preferences.setProximityEnabled(false, for: vehicle.vin)
            proximityStatus = "Kapalı"
            return true
        }
        guard let calibration = proximityCalibration, calibration.isValid else {
            proximityEnabled = false
            proximityStatus = "Önce geçerli yakın/uzak ölçümü yapın."
            return false
        }
        proximityEnabled = true
        preferences.setProximityEnabled(true, for: vehicle.vin)
        proximityGate = ProximityGate(calibration: calibration, profile: proximityProfile)
        proximityGuard = ProximityCycleGuard()
        proximityLatencyMeter = ProximityLatencyMeter()
        proximityLastLatency = nil
        proximityRSSISamples.removeAll()
        ble.setProximityRSSIPollInterval(proximityProfile.pollInterval)
        proximityAutoOffDeadline = nil
        proximitySettings.setAutoOffDeadline(nil, vin: vehicle.vin)
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
            model.link.start()
        } else if ble.state.isCertificate, !authBusy {
            Task { await authenticateBLE() }
        }
        return true
    }

    @MainActor
    private func setProximityAutoOffEnabled(_ enabled: Bool) {
        proximityAutoOffEnabled = enabled
        proximitySettings.setAutoOffEnabled(enabled, vin: vehicle.vin)
        proximityAutoOffTask?.cancel()
        proximityAutoOffTask = nil
        guard enabled else {
            pendingAutoLockTask?.cancel()
            pendingAutoLockTask = nil
            awaitingProximityLockConfirmation = false
            proximityAutoOffDeadline = nil
            proximitySettings.setAutoOffDeadline(nil, vin: vehicle.vin)
            proximityAutoOffStatus = ""
            return
        }
        if let deadline = proximityAutoOffDeadline, deadline > Date() {
            scheduleProximityAutoOff(deadline: deadline)
        } else {
            proximityAutoOffDeadline = nil
            proximitySettings.setAutoOffDeadline(nil, vin: vehicle.vin)
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
        proximitySettings.setAutoOffDeadline(deadline, vin: vehicle.vin)
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
        proximitySettings.setAutoOffDeadline(nil, vin: vehicle.vin)
        proximityAutoOffTask?.cancel()
        proximityAutoOffTask = nil
        pendingAutoLockTask?.cancel()
        pendingAutoLockTask = nil
        awaitingProximityLockConfirmation = false
        setProximityEnabled(false)
        keepBLEConnected = false
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
        // Güç durumu: yalnız aksesuar/hazır (3/4) otomasyonu durdurur. Park
        // hâlinde araç 0/1 bildiriyor ve kilit bu durumda uygulanıyor
        // (2026-11-17 kanıtı); eski `powerState == 2` şartı otomasyonu en sık
        // senaryoda sessizce durduruyordu.
        if let reason = ProximityPowerGate.blockReason(powerState: state.powerState) {
            proximityStatus = reason
            ble.recordDiagnostic("Yakınlık eylemi atlandı: power=\(state.powerState) (aksesuar/hazır)")
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
                    if let recent = AutomaticCommandLedger.shared.recent(action: "unlock",
                                                                        vin: vehicle.vin,
                                                                        within: 30, excluding: .proximity) {
                        proximityStatus = "Yakınlık algılandı; \(recent.source == .geofence ? "geofence" : "otomatik") açması yeni gönderildi, çift komut engellendi."
                        ble.recordDiagnostic("proximity_unlock_skipped · son açma \(recent.source.rawValue) kaynaklı; çift komut engellendi")
                    } else if ble.unlock() {
                        proximityGuard.noteUnlockIssued()
                        AutomaticCommandLedger.shared.note(source: .proximity, action: "unlock", vin: vehicle.vin)
                        pendingAutomaticCommandKind = .unlock
                        pendingAutomaticCommandAt = Date()
                        recordWidgetCommand("Otomatik kilit açma (yakınlık)")
                        proximityStatus = "Yakınlık algılandı; imzalı kilit açma isteği başlatıldı."
                        ble.recordDiagnostic("Yakınlık otomasyonu kilit açma biletiyle istek başlattı")
                    } else {
                        proximityGuard.noteAmbiguity(now: Date())
                        postProximityCommandNotice(kind: .unlock, failure: .notStarted)
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
                if let recent = AutomaticCommandLedger.shared.recent(action: "lock", vin: vehicle.vin,
                                                                    within: 60) {
                    let age = Int(Date().timeIntervalSince(recent.at))
                    proximityStatus = "Son kilitleme \(age) sn önce denendi; pencere dolana dek tekrar denemiyor."
                    ble.recordDiagnostic("proximity_lock_skipped · son kilitleme \(age) sn önce; 60 sn penceresi")
                    return
                }
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
                    AutomaticCommandLedger.shared.note(source: .proximity, action: "lock", vin: vehicle.vin)
                    pendingAutomaticCommandKind = .lock
                    pendingAutomaticCommandAt = Date()
                    recordWidgetCommand("Kilitleme (yakınlık)")
                    proximityStatus = "Uzaklaşma algılandı; kilitleme komutu gönderildi; camlar kapatılmaya çalışılıyor."
                    ble.recordDiagnostic("Yakınlık otomasyonu kilitleme komutunu başlattı")
                } else {
                    pendingAutoLockTask?.cancel()
                    pendingAutoLockTask = nil
                    awaitingProximityLockConfirmation = false
                    postProximityCommandNotice(kind: .lock, failure: .notStarted)
                    proximityStatus = "Uzaklaşma algılandı; kilitleme başlatılamadı: \(ble.lastEvent)"
                    ble.recordDiagnostic("Yakınlık otomasyonu kilitleme akışını başlatamadı")
                }
            } else {
                proximityStatus = "Uzaklaşma algılandı; kapılar zaten kilitli."
            }
        }
    }

    // MARK: - Uzaklaşınca kilitleme bileti

    @MainActor
    private func armDeferredLockTicket() {
        guard ble.state.isReady else {
            showCommands = true
            return
        }
        if ble.telemetry?.isLocked == true {
            deferredLockStatus = "Araç zaten kilitli; bilet kurulmadı."
            return
        }
        let ticket = DeferredLockTicket()
        deferredLockTicket = ticket
        deferredLockSettings.setDeadline(ticket.deadline, vin: vehicle.vin)
        deferredLockStatus = "Bilet kuruldu; sinyal \(BleReconnectPolicy.weakSignalThreshold) dBm altına inince tek kilitleme komutu gönderilecek."
        ble.recordDiagnostic("deferred_lock_armed · uzaklaşınca kilitleme bileti kuruldu")
    }

    /// Diskteki bilet geri yüklenir: uygulama askıya alınsa da kullanıcının
    /// kurduğu bilet sessizce kaybolmaz. Süresi dolmuş kayıt silinir.
    @MainActor
    private func restoreDeferredLockTicketIfNeeded() {
        guard deferredLockTicket == nil else { return }
        guard let restored = deferredLockSettings.restoredTicket(vin: vehicle.vin) else { return }
        deferredLockTicket = restored
        deferredLockStatus = "Bilet sürüyor; sinyal zayıflayınca tek kilitleme komutu gönderilecek."
        ble.recordDiagnostic("deferred_lock_restored · kayıtlı bilet geri yüklendi")
    }

    @MainActor
    private func cancelDeferredLockTicket(reason: String) {
        guard deferredLockTicket != nil else { return }
        deferredLockTicket = nil
        deferredLockSettings.setDeadline(nil, vin: vehicle.vin)
        deferredLockStatus = reason
        ble.recordDiagnostic("deferred_lock_cancelled · \(reason)")
    }

    /// Her GATT RSSI örneğinde beslenir. Komut yalnız bilet kurulduysa,
    /// sinyal zayıfsa, telemetri tazeyse ve araç açıksa gider; kayıt tek.
    @MainActor
    private func processDeferredLockTicket(_ rssi: Int) {
        guard let ticket = deferredLockTicket else { return }
        if let reason = ProximityPowerGate.blockReason(powerState: ble.telemetry?.powerState) {
            cancelDeferredLockTicket(reason: reason)
            return
        }
        let telemetryAge = ble.telemetry.map { Date().timeIntervalSince($0.receivedAt) }
        let recentLock = AutomaticCommandLedger.shared.recent(
            action: "lock", vin: vehicle.vin, within: 60
        ) != nil
        switch ticket.decide(
            rssi: rssi,
            now: Date(),
            isLocked: ble.telemetry?.isLocked,
            telemetryAge: telemetryAge,
            recentLock: recentLock
        ) {
        case .wait:
            return
        case .cancel(let reason):
            deferredLockTicket = nil
            deferredLockSettings.setDeadline(nil, vin: vehicle.vin)
            deferredLockStatus = reason
            ble.recordDiagnostic("deferred_lock_cancelled · \(reason)")
        case .send:
            deferredLockTicket = nil
            deferredLockSettings.setDeadline(nil, vin: vehicle.vin)
            guard ble.lock() else {
                deferredLockStatus = "Sinyal zayıfladı ancak kilitleme başlatılamadı: \(ble.lastEvent)"
                ble.recordDiagnostic("deferred_lock_failed · komut başlatılamadı")
                return
            }
            AutomaticCommandLedger.shared.note(
                source: .deferredLock, action: "lock", vin: vehicle.vin
            )
            pendingAutomaticCommandKind = .lock
            pendingAutomaticCommandAt = Date()
            recordWidgetCommand("Kilitleme (uzaklaşma bileti)")
            deferredLockStatus = "Sinyal zayıfladı (\(rssi) dBm); kilitleme gönderildi, doğrulama bekleniyor."
            ble.recordDiagnostic("deferred_lock_sent · sinyal \(rssi) dBm; tek kilitleme komutu gönderildi")
        }
    }

    // MARK: - Otomatik komut bildirimi

    /// Otomatik (yakınlık) komutun doğrulama sonucu. Yalnız 60 sn içindeki
    /// sonuç bildirime dönüşür; manuel komutlar bu yolu kullanmaz.
    @MainActor
    private func handleAutomaticCommandOutcome(_ outcome: ProximityCommandNotice.Outcome) {
        guard let kind = pendingAutomaticCommandKind,
              let at = pendingAutomaticCommandAt,
              Date().timeIntervalSince(at) <= 60 else { return }
        pendingAutomaticCommandKind = nil
        pendingAutomaticCommandAt = nil
        guard outcome == .failed else { return }
        postProximityCommandNotice(kind: kind, failure: .notVerified)
    }

    /// Başarısız otomatik komut bildirimi. Metin "yeniden gönderilmedi"
    /// der — bildirim komutu tekrar tetiklemez (davranışa sadık).
    @MainActor
    private func postProximityCommandNotice(kind: ProximityCommandNotice.Kind,
                                            failure: ProximityCommandNotice.Failure) {
        pendingAutomaticCommandKind = nil
        pendingAutomaticCommandAt = nil
        let failureKey = failure == .notVerified ? "notVerified" : "notStarted"
        let throttleKey = StorageKeys.proximityNoticeThrottle(
            vehicle.vin, kind: kind.actionText, failure: failureKey)
        guard noticeThrottle.shouldNotify(key: throttleKey, window: 600) else {
            // Aynı başarısızlık 10 dakikada bir bildirime sığınır; tekrar
            // sessizce kayda geçer (spam engeli; ilk uyarı gecikmez).
            ble.recordDiagnostic("proximity_command_notice · \(kind.actionText) · "
                                 + (failure == .notVerified ? "doğrulanamadı" : "başlatılamadı")
                                 + " · pencere içinde, bildirim susturuldu")
            return
        }
        noticeThrottle.record(key: throttleKey)
        let doorOpen = (ble.telemetry?.openDoorCount ?? 0) > 0 || (ble.telemetry?.trunkAjar ?? 0) != 0
        NotificationPoster.post(
            ProximityCommandNotice.failureDraft(kind: kind, failure: failure, vin: vehicle.vin,
                                                doorOpenContext: doorOpen,
                                                reason: ble.lastCommandReceipt?.failureReason),
            using: notificationPoster
        )
        ble.recordDiagnostic("proximity_command_notice · \(kind.actionText) · "
                             + (failure == .notVerified ? "doğrulanamadı" : "başlatılamadı")
                             + " · bildirim gönderildi")
    }

    /// Eşleşme geçersiz bildirimi: araç başına günde bir kez. Banner ile
    /// aynı `PairingRecovery` metnini kullanır; bildirim komut tetiklemez.
    @MainActor
    private func notifyPairingRecoveryIfNeeded() {
        let key = StorageKeys.pairingRecoveryNotified(vehicle.vin)
        guard notificationDedupe.shouldNotify(key: key) else { return }
        notificationDedupe.record(key: key)
        NotificationPoster.requestAuthorization(using: notificationPoster)
        NotificationPoster.post(PairingRecovery.notificationDraft(vin: vehicle.vin),
                                using: notificationPoster)
        ble.recordDiagnostic("pairing_lost · kurtarma bildirimi gönderildi (günde bir)")
    }

    @MainActor
    private func handleBLEState(_ state: BleConnection.State) {
        if ble.needsRepair {
            notifyPairingRecoveryIfNeeded()
        }
        if state.isConnecting || state.isDisconnected || state.isFailed {
            requireFreshProximityCycle(reason: "BLE oturumu değişti: \(state.description)", resetGuard: true)
        }
        if state.isReady {
            hasAuthenticatedBLE = true
            loadCertificateProvenance()
            if proximityEnabled { proximityStatus = "Bağlı; yakınlık izleniyor (uygulama ekranda kalmalı)." }
            return
        }

        // Kopma yaşam döngüsü tek sahipte (BleLinkCoordinator); görünüm
        // yalnız gösterim durumunu günceller.
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
        case .lock:
            guard ble.lock() else { return }
            noteManualCommand(action: "lock", label: "Kilitleme")
        case .unlock:
            guard ble.unlock() else { return }
            noteManualCommand(action: "unlock", label: "Kilit açma")
        case .trunkOpen:
            guard ble.trunkOpen() else { return }
            recordWidgetCommand("Bagaj açma")
        case .trunkClose:
            guard ble.trunkClose() else { return }
            recordWidgetCommand("Bagaj kapatma")
        case .windowsOpen:
            guard ble.windowsOpen() else { return }
            recordWidgetCommand("Cam açma")
        case .windowsClose:
            guard ble.windowsClose() else { return }
            recordWidgetCommand("Cam kapatma")
        // Oto kilit BLE komutu değildir; approve() uygulama anahtarını çevirir.
        case .automaticLockOn, .automaticLockOff: break
        }
    }

    /// Elle verilen kilit/açma komutu da otomatik komut defterine yazılır:
    /// otomasyonlar 60 sn içinde aynı eylemi tekrar göndermez. Kayıt yalnız
    /// komut kapıdan geçtiyse yazılır — reddedilen komut "gönderildi" sayılmaz.
    private func noteManualCommand(action: String, label: String) {
        guard !vehicle.vin.isEmpty else { return }
        AutomaticCommandLedger.shared.note(source: .manual, action: action, vin: vehicle.vin)
        recordWidgetCommand(label)
    }

    /// Widget'a son komut yazımı: yalnız etiket ve zaman; VIN/token asla
    /// yazılmaz. Doğrulama yoksa `verified` nil kalır → "doğrulama yok".
    private func recordWidgetCommand(_ label: String, verified: Bool? = nil) {
        VehicleCommandStatusStore.save(
            VehicleCommandStatus(actionLabel: label, sentAt: Date(), verified: verified)
        )
        // Saat ve widget aynı sonucu görür: depo değişikliği tek yayın
        // noktasını tetikler (çağıranların publish etmeyi unutması bitti).
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
        NotificationPoster.post(
            NotificationPoster.Draft(
                identifier: UUID().uuidString,
                title: "Uygun yakınlık aralığı algılandı",
                body: "Yakın ölçüm \(suggestion.nearSample) dBm, uzak ölçüm \(suggestion.farSample) dBm (fark \(suggestion.separation) dBm). Aralık metreye çevrilmez; otomasyonu kendi kendine açmadım. Onay için yakınlık kartındaki ölçüm düğmelerini kullan."
            ),
            using: notificationPoster
        )
    }

    /// 12 V akü düşükse iPhone'a yerel bildirim. Lastik uyarısıyla aynı
    /// desen: yalnız **taze** telemetri güncellemesinden gelir (önbellekten
    /// gösterilen eski değere yazılmaz), ciddiyet başına günde bir kez,
    /// VIN'siz anahtar ve VIN'siz metin. Eksik veri bildirim üretmez
    /// ("bilgi yok" ≠ uyarı); gerçek 0 kritik bildirimdir.
    /// 12 V akü günlük geçmişi (Android aux_history paritesi); yalnız
    /// taze telemetri kaydı yapılır, eksik gün "—" kalır.
    @State private var auxiliaryHistory = AuxiliaryBatteryHistory()

    /// 12 V geçmiş ve bildirim tekniği ortak altyapısı (Core; testli).
    private let auxiliaryHistoryStore = AuxiliaryBatteryHistoryStore(store: UserDefaults.standard)
    private let notificationDedupe = NotificationDedupe(store: UserDefaults.standard)
    /// Otomatik komut bildirim penceresi: zayıf sinyal döngüsünde aynı
    /// başarısızlık dakikalar içinde tekrar bildirim üretmesin.
    private let noticeThrottle = NoticeThrottle(store: UserDefaults.standard)
    /// Yakınlık/klima kalıcılığı (Core; testli). `enabled` durumu
    /// GaragePreferences'a aittir.
    private let proximitySettings = ProximitySettings(store: UserDefaults.standard)
    private let climateSettings = ClimateSettings(store: UserDefaults.standard)
    private let preferences = GaragePreferences()
    /// Yerel bildirim gönderimi tek noktadan (Core `NotificationPoster`).
    private let notificationPoster = SystemNotificationPoster()

    /// Şarj hedefi gözcüsü: yalnız **taze** telemetri + aktif canlı şarj
    /// oturumunda değerlendirilir; hedef aşılınca oturum başına bir kez
    /// bildirim. Anahtar oturum başlangıcını içerir (yeni oturum = yeni
    /// izin). Metin VIN içermez; "araç durdurulmaz" dürüstlüğü korunur.
    private func checkChargingTarget(_ parsed: VehicleTelemetry) {
        guard let target = model.chargingTarget,
              model.chargingLive?.charging == true,
              let percent = parsed.batteryPercent,
              ChargingTargetPolicy.reached(target: target, percent: percent) else { return }
        let startedAt = model.chargingLive?.startedAt ?? 0
        let key = "toqdas.chargingtarget.notified.\(vehicle.vin).\(Int(startedAt)).\(target)"
        guard notificationDedupe.shouldNotify(key: key) else { return }
        notificationDedupe.record(key: key)

        NotificationPoster.requestAuthorization(using: notificationPoster)
        NotificationPoster.post(
            NotificationPoster.Draft(
                identifier: UUID().uuidString,
                title: "Şarj hedefi (%\(target)) aşıldı",
                body: "Akü %\(Int(percent.rounded())). Araç şarjı uygulamadan durdurmaz; gerekirse uygulamadan veya şarj ünitesinden durdurabilirsin.",
                timeSensitive: false),
            using: notificationPoster
        )
    }

    private func checkAuxiliaryBattery(_ percent: Double?) {
        // Geçmiş kaydı uyarıdan bağımsızdır: sağlıklı değer (> %40) de günün
        // en güncel ölçümü olarak yazılır; eksik/aralık dışı değer record
        // içinde reddedilir. Uyarı değerlendirmesi yalnız bildirimi yönetir.
        if auxiliaryHistory.record(percent: percent, on: Date()) {
            saveAuxiliaryHistory()
        }
        guard let assessment = AuxiliaryBatteryPolicy.assess(percent) else { return }
        let key = StorageKeys.auxiliaryNotified(vehicle.vin, severity: assessment.severity == .critical ? "critical" : "warning")
        guard notificationDedupe.shouldNotify(key: key) else { return }
        notificationDedupe.record(key: key)

        NotificationPoster.requestAuthorization(using: notificationPoster)
        // Kritik bandı time-sensitive taşınır: kilitli ekranda ve
        // eşlenmiş saatte yoğun olmayan haptikle görünür (Critical Alerts
        // yetkisi yok; kullanıcının bildirim ayarı geçerlidir).
        NotificationPoster.post(
            NotificationPoster.Draft(
                identifier: UUID().uuidString,
                title: assessment.isCritical ? "12 V akü kritik düşük" : "12 V akü zayıf",
                body: "Akü yüzde \(assessment.percent). "
                    + (assessment.isCritical
                        ? "Uzun parklarda araç açılmayabilir; en kısa sürede şarj/bakım kontrolü önerilir."
                        : "Yakında şarj/bakım kontrolü önerilir."),
                timeSensitive: assessment.isCritical
            ),
            using: notificationPoster
        )
    }

    private var auxiliaryHistoryKey: String { StorageKeys.auxiliaryHistory(vehicle.vin) }

    /// Görüntü için geçmiş: taze kayıt varsa state; yoksa kayıtlı veri.
    /// Bilinçli olarak salt-okunurdur (body değerlendirmesinde state
    /// yazımı yapılmaz).
    private var storedAuxiliaryHistory: AuxiliaryBatteryHistory {
        if !auxiliaryHistory.samples.isEmpty { return auxiliaryHistory }
        return auxiliaryHistoryStore.load(key: auxiliaryHistoryKey)
    }

    private func saveAuxiliaryHistory() {
        auxiliaryHistoryStore.save(auxiliaryHistory, key: auxiliaryHistoryKey)
    }

    /// 12 V trendi: 7 günlük geçmişten yön çıkarımı (Core, testli).
    private var auxiliaryTrend: AuxiliaryBatteryTrend {
        AuxiliaryBatteryTrend.make(history: storedAuxiliaryHistory, today: Date())
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
            proximitySettings.setAutoOffCustomMinutes(minutes, vin: vehicle.vin)
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

    private var lockTileSubtitle: String {
        switch effectiveLocked {
        case true: return ble.telemetry != nil ? "Kilitli" : (stateSnapshot?.lockText() ?? "Kilitli")
        case false: return ble.telemetry != nil ? "Kilit açık" : (stateSnapshot?.lockText() ?? "Kilit açık")
        default: return "Bilinmiyor"
        }
    }

    private var climateTileSubtitle: String {
        guard climateKnown else { return "Bilinmiyor" }
        return displayClimateOn
            ? "Açık · \(TurkishFormat.decimal(targetTemperature, digits: 1))°C"
            : "Kapalı"
    }

    private var trunkTileSubtitle: String {
        guard let ajar = effectiveTrunkAjar else { return "Bilinmiyor" }
        if ble.telemetry == nil, let text = stateSnapshot?.trunkText() { return text }
        return ajar ? "Açık" : "Kapalı"
    }

    /// "Hazır" yalnız imzalı telemetriden (`powerState == 4`).
    private var driveTileSubtitle: String {
        guard let power = effectivePowerState else { return "Bilinmiyor" }
        if ble.telemetry == nil, let text = stateSnapshot?.driveText() { return text }
        return power == 4 ? "Hazır" : "Hazır değil"
    }

    /// Kilit/bagaj/sürüş/iklim değerlerinden **hiçbiri** yoksa dört ölü
    /// karo yerine tek eylem kartı gösterilir: "Bilinmiyor" tekrarı yerine
    /// "bağlan ve oku" çıkışı.
    private var hasAnyVehicleState: Bool {
        effectiveLocked != nil || effectiveTrunkAjar != nil
            || effectivePowerState != nil || climateKnown
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: DSSpace.xs) {
            SectionHeader(title: "Hızlı kontroller", subtitle: "Kapı, iklim, bagaj, sürüş")
            if !hasAnyVehicleState {
                EmptyState(
                    icon: "antenna.radiowaves.left.and.right",
                    title: "Araç durumu henüz okunmadı",
                    message: "Kilit, bagaj ve sürüş durumu yalnız araçla kurulan BLE oturumunda okunur. Araç yakınken bağlanın; okunan son imzalı değer yaşıyla birlikte saklanır.",
                    actionTitle: ble.state.isReady ? "Durumu oku" : "Araçla bağlan",
                    action: {
                        if ble.state.isReady {
                            Task { await authenticateBLE() }
                        } else {
                            toggleConnection()
                        }
                    },
                    prominentAction: true
                )
            } else {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: DSSpace.sm),
                                GridItem(.flexible(), spacing: DSSpace.sm)],
                      spacing: DSSpace.sm) {
                ActionTile(
                    title: "Kapılar",
                    subtitle: lockTileSubtitle,
                    icon: effectiveLocked == false ? "lock.open.fill" : "lock.fill",
                    active: effectiveLocked == false,
                    tint: DSColor.warning
                ) {
                    if ble.state.isReady, let locked = ble.telemetry?.isLocked {
                        alert = .confirm(locked ? .unlock : .lock)
                    } else {
                        showCommands = true
                    }
                }

                ActionTile(
                    title: "İklimlendirme",
                    subtitle: climateTileSubtitle,
                    icon: "snowflake",
                    active: climateKnown && displayClimateOn,
                    tint: DSColor.info
                ) {
                    if ble.state.isReady {
                        Task { await toggleClimate() }
                    } else {
                        showAllControls = true
                    }
                }

                ActionTile(
                    title: "Arka Bagaj",
                    subtitle: trunkTileSubtitle,
                    icon: "car.side.rear.open",
                    active: effectiveTrunkAjar == true,
                    tint: DSColor.accent
                ) {
                    if ble.state.isReady, let trunk = ble.telemetry?.trunkAjar {
                        alert = .confirm(trunk == 1 ? .trunkClose : .trunkOpen)
                    } else {
                        showCommands = true
                    }
                }

                ActionTile(
                    title: "Sürüş",
                    subtitle: driveTileSubtitle,
                    icon: "steeringwheel",
                    active: effectivePowerState == 4,
                    tint: DSColor.accent
                ) {
                    showQuickStart = true
                }
            }
            .id("quickActions")
            }
        }
    }

    /// "Uzaklaşınca kilitle" bileti: araç yanında kilit uygulanmadığında
    /// kullanıcı bileti kurar; sinyal zayıfladığı an tek komut gider.
    @ViewBuilder
    private var deferredLockRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            if deferredLockTicket == nil {
                HStack(spacing: 10) {
                    Button {
                        armDeferredLockTicket()
                    } label: {
                        Label("Uzaklaşınca kilitle", systemImage: "figure.walk.departure")
                            .font(ToggTheme.text(.caption, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(RoundedRectangle(cornerRadius: 12).fill(ToggTheme.surfaceVariant))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("deferredLock.arm")
                }
                Text("Araç, dijital anahtar yanındayken kilit komutunu uygulamıyor. Bilet, sinyal zayıfladığında tek kilitleme komutu gönderir (en çok 10 dk). Arka planda sinyal örneği ~1 dk gecikebilir.")
                    .font(ToggTheme.text(.micro))
                    .foregroundStyle(ToggTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 10) {
                    Label("Uzaklaşma bekleniyor", systemImage: "figure.walk.departure")
                        .font(ToggTheme.text(.caption, weight: .semibold))
                        .foregroundStyle(ToggTheme.teal)
                    Spacer()
                    Button {
                        cancelDeferredLockTicket(reason: "Bilet iptal edildi; kilitleme gönderilmedi.")
                    } label: {
                        Text("İptal")
                            .font(ToggTheme.text(.caption, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 32)
                            .background(RoundedRectangle(cornerRadius: 10).fill(ToggTheme.surfaceVariant))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("deferredLock.cancel")
                }
            }
            if let status = deferredLockStatus {
                Text(status)
                    .font(ToggTheme.text(.micro))
                    .foregroundStyle(ToggTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
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
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Trugo Akıllı Şarj Yönetimi")
                        .font(ToggTheme.text(.lead, weight: .bold)).foregroundStyle(.white)
                    Text(chargingLabel == "—" ? "Şarj durumu bilinmiyor" : chargingLabel)
                        .font(ToggTheme.text(.caption)).foregroundStyle(ToggTheme.muted)
                }
                Spacer()
            }

            Text("Şarj başlatma/durdurma ve limit değiştirme araca bağlı değil. Enerji/ücret tahmini aşağıdaki hesaplayıcıdadır.")
                .font(.caption2).foregroundStyle(ToggTheme.muted)
        }
        .padding(20)
        .dsCard()
    }

    private var chargingOverviewLink: some View {
        Button { tab = .energy } label: {
            HStack(spacing: 12) {
                Image(systemName: "bolt.car.fill")
                    .font(ToggTheme.text(.headline))
                    .foregroundStyle(ToggTheme.green)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Şarj ve istasyonlar")
                        .font(ToggTheme.text(.body, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Durum: \(chargingLabel) · tahmin ve geçmiş")
                        .font(ToggTheme.text(.micro))
                        .foregroundStyle(ToggTheme.muted)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(ToggTheme.text(.caption, weight: .bold))
                    .foregroundStyle(ToggTheme.muted)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsCard()
        }
        .buttonStyle(.plain)
    }

    /// Canlı şarj gözlemi. Dürüst sınırlar: enerji (kWh/kW) telemetride
    /// yok, gösterilmez; hız ve bitiş gözlemlenen yüzde eğiminden hesaplanır;
    /// geçen süre yalnız uygulama açıkken ölçülür. "Kalan süre" ile "tahmini
    /// bitiş" tek tabandan üretilir (resmi uygulamadaki çelişki burada yok).
    private var liveChargingCard: some View {
        TimelineView(.periodic(from: .now, by: 5)) { timeline in
            let now = timeline.date
            let live = model.chargingLive
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(ToggTheme.blue.opacity(0.18)).frame(width: 38, height: 38)
                        Image(systemName: "bolt.badge.clock")
                            .foregroundStyle(ToggTheme.blue)
                            .accessibilityHidden(true)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Canlı şarj gözlemi")
                            .font(ToggTheme.text(.lead, weight: .bold)).foregroundStyle(.white)
                        Text(live?.charging == true ? "Ölçüm sürüyor" : "Şarj oturumu bekleniyor")
                            .font(ToggTheme.text(.caption)).foregroundStyle(ToggTheme.muted)
                    }
                    Spacer()
                }

                if let live, live.charging {
                    VStack(spacing: 8) {
                        liveRow("Doluluk", telemetry?.batteryPercent.map { "%\(TurkishFormat.decimal($0, digits: 1))" } ?? "—")
                        if let target = model.chargingTarget {
                            liveRow("Hedefe kalan (%\(target))",
                                    ChargingTargetPolicy.remaining(target: target, percent: telemetry?.batteryPercent)
                                        .map { "%\(TurkishFormat.integer($0))" } ?? "—")
                        }
                        liveRow("Menzil", telemetry?.rangeKM.map { "\(TurkishFormat.integer($0)) km" } ?? "—")
                        liveRow("Geçen süre", live.startedAt.map { liveElapsedText(since: $0, now: now) }
                                                  ?? "— (uygulama kapalıydı)")
                        liveRow("Gözlemlenen hız", live.percentPerMinute.map { "%\(TurkishFormat.decimal($0, digits: 2))/dk" }
                                                    ?? "ölçülüyor…")
                        liveRow("Kalan süre", liveRemainingText(live: live, now: now))
                        liveRow("Tahmini bitiş", liveFinishText(live: live, now: now))
                    }
                    .accessibilityElement(children: .combine)
                } else if let last = live?.lastSession {
                    Text("Son oturum: \(TurkishFormat.date(Date(timeIntervalSince1970: last.startedAt), format: "dd.MM HH:mm")) – \(TurkishFormat.date(Date(timeIntervalSince1970: last.endedAt), format: "HH:mm")) · \(liveDurationText(last.endedAt - last.startedAt))")
                        .font(ToggTheme.text(.body)).foregroundStyle(.white)
                } else {
                    Text("Şarj sırasında bu kart süre ve tahmini bitişi izler.")
                        .font(ToggTheme.text(.body)).foregroundStyle(ToggTheme.muted)
                }

                Text("Enerji (kWh/kW) telemetrisi gelmediği için gösterilmez; hız ve bitiş, gözlemlenen yüzde değişiminden hesaplanır. Geçen süre yalnız uygulama açıkken ölçülür.")
                    .font(.caption2).foregroundStyle(ToggTheme.muted)
            }
            .padding(20)
            .dsCard()
            .id("liveChargingCard")
        }
    }

    /// Şarj hedefi seçimi. Uygulama araca durdurma komutu göndermez;
    /// hedef aşılınca yerel bildirim üretir (oturum başına bir kez).
    private var chargingTargetCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(ToggTheme.blue.opacity(0.18)).frame(width: 38, height: 38)
                    Image(systemName: "target")
                        .foregroundStyle(ToggTheme.blue)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Şarj hedefi")
                        .font(ToggTheme.text(.lead, weight: .bold)).foregroundStyle(.white)
                    Text(model.chargingTarget.map { "Hedef %\($0)" } ?? "Kapalı")
                        .font(ToggTheme.text(.caption)).foregroundStyle(ToggTheme.muted)
                }
                Spacer()
            }
            Picker("Şarj hedefi", selection: Binding(
                get: { model.chargingTarget ?? 0 },
                set: { model.setChargingTarget($0 == 0 ? nil : $0) })) {
                Text("Kapalı").tag(0)
                Text("%50").tag(50)
                Text("%80").tag(80)
                Text("%90").tag(90)
            }
            .pickerStyle(.segmented)
            Text("Araç şarjı uygulamadan durdurulmaz; hedefe ulaşıldığında bildirim alırsın, gerekirse uygulamadan veya şarj ünitesinden durdurursun.")
                .font(.caption2).foregroundStyle(ToggTheme.muted)
        }
        .padding(20)
        .dsCard()
        .id("chargingTargetCard")
    }

    /// Şarj geçmişi: tamamlanmış oturumların listesi. Enerji telemetrisi
    /// olmadığı için yalnız süre, yüzde değişimi ve gözlemlenen hız gösterilir.
    private var chargingHistoryCard: some View {
        let entries = model.chargingHistory.suffix(8).reversed()
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(ToggTheme.teal.opacity(0.18)).frame(width: 38, height: 38)
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundStyle(ToggTheme.teal)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Şarj geçmişi")
                        .font(ToggTheme.text(.lead, weight: .bold)).foregroundStyle(.white)
                    Text("\(model.chargingHistory.count) oturum kayıtlı")
                        .font(ToggTheme.text(.caption)).foregroundStyle(ToggTheme.muted)
                }
                Spacer()
            }

            if model.chargingHistory.isEmpty {
                Text("Tamamlanan ilk oturum burada listelenir; şarj sırasında canlı gözlem üstteki kartta izlenir.")
                    .font(ToggTheme.text(.body)).foregroundStyle(ToggTheme.muted)
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(entries), id: \.startedAt) { entry in
                        HStack(alignment: .firstTextBaseline) {
                            Text(chargingHistoryDate(entry))
                                .font(ToggTheme.text(.body)).foregroundStyle(.white)
                            Spacer()
                            Text(chargingHistoryValues(entry))
                                .font(ToggTheme.text(.caption)).foregroundStyle(ToggTheme.muted)
                                .multilineTextAlignment(.trailing)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            Text("Enerji (kWh) telemetrisi gelmediği için yalnız süre, yüzde değişimi ve gözlemlenen hız gösterilir; ölçülemeyen değer — olur. Oturumlar yalnız uygulama açıkken ölçülür.")
                .font(.caption2).foregroundStyle(ToggTheme.muted)
        }
        .padding(20)
        .dsCard()
        .id("chargingHistoryCard")
    }

    private func chargingHistoryDate(_ entry: ChargingHistoryEntry) -> String {
        let start = Date(timeIntervalSince1970: entry.startedAt)
        let end = Date(timeIntervalSince1970: entry.endedAt)
        return TurkishFormat.date(start, format: "dd.MM HH:mm") + " – "
            + TurkishFormat.date(end, format: "HH:mm")
    }

    private func chargingHistoryValues(_ entry: ChargingHistoryEntry) -> String {
        var parts: [String] = [liveDurationText(entry.endedAt - entry.startedAt)]
        if let start = entry.startPercent, let end = entry.endPercent {
            parts.append("%\(TurkishFormat.integer(start)) → %\(TurkishFormat.integer(end))")
        }
        if let rate = entry.ratePerMinute {
            parts.append("%\(TurkishFormat.decimal(rate, digits: 2))/dk")
        }
        return parts.joined(separator: " · ")
    }

    private func liveRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(ToggTheme.text(.body)).foregroundStyle(ToggTheme.muted)
            Spacer()
            Text(value)
                .font(ToggTheme.text(.body, weight: .semibold)).foregroundStyle(.white)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func liveElapsedText(since startedAt: TimeInterval, now: Date) -> String {
        liveDurationText(max(0, now.timeIntervalSince1970 - startedAt))
    }

    private func liveDurationText(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total) sn" }
        if total < 3600 { return "\(total / 60) dk \(total % 60) sn" }
        return "\(total / 3600) sa \((total % 3600) / 60) dk"
    }

    private func liveRemainingMinutes(live: ChargingLiveState, now: Date) -> Double? {
        guard let rate = live.percentPerMinute,
              let percent = telemetry?.batteryPercent else { return nil }
        let remaining = max(0, 100 - percent)
        return remaining / rate * 60
    }

    private func liveRemainingText(live: ChargingLiveState, now: Date) -> String {
        guard let seconds = liveRemainingMinutes(live: live, now: now) else { return "—" }
        return liveDurationText(seconds)
    }

    /// Tahmini bitiş, kalan süre ile aynı hızdan üretilir: iki değer asla
    /// çelişmez (aynı taban, iki gösterim).
    private func liveFinishText(live: ChargingLiveState, now: Date) -> String {
        guard let seconds = liveRemainingMinutes(live: live, now: now) else { return "—" }
        return TurkishFormat.date(now.addingTimeInterval(seconds), format: "HH:mm")
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
                        .font(ToggTheme.text(.lead, weight: .bold)).foregroundStyle(.white)
                    Text("Kapasite ve fiyat varsayımdır")
                        .font(ToggTheme.text(.caption)).foregroundStyle(ToggTheme.muted)
                }
                Spacer()
            }

            percentRow(title: "Başlangıç doluluğu", value: $chargeStartPercent,
                       range: 0...99, identifier: "calculator.startPercent")
            percentRow(title: "Hedef doluluk", value: $chargeTargetPercent,
                       range: 1...100, identifier: "calculator.targetPercent")

            VStack(spacing: 8) {
                assumptionRow(title: "Hesaplama kapasitesi", value: $chargeCapacityKWh,
                              range: 1...200, step: 0.1, unit: "kWh")
                assumptionRow(title: "Birim fiyat", value: $chargePricePerKWh,
                              range: 0...100, step: 0.1, unit: "₺/kWh")
            }

            VStack(spacing: 8) {
                HStack {
                    Text("Tahmini enerji").font(ToggTheme.text(.body)).foregroundStyle(ToggTheme.muted)
                    Spacer()
                    Text(chargeEstimate.energyText)
                        .font(ToggTheme.text(.lead, weight: .bold)).foregroundStyle(.white).monospacedDigit()
                        .accessibilityIdentifier("calculator.energy")
                }
                HStack {
                    Text("Tahmini ücret").font(ToggTheme.text(.body)).foregroundStyle(ToggTheme.muted)
                    Spacer()
                    Text(chargeEstimate.costText)
                        .font(ToggTheme.text(.lead, weight: .bold)).foregroundStyle(ToggTheme.teal).monospacedDigit()
                        .accessibilityIdentifier("calculator.cost")
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(ToggTheme.surfaceVariant))

            Text("Kapasite ve fiyat varsayımdır; şarj kayıpları hesaba katılmaz. Araçta şarj başlatmaz.")
                .font(.caption2).foregroundStyle(ToggTheme.muted)
        }
        .padding(20)
        .dsCard()
        .id("chargingCalculator")
    }

    private func percentRow(title: String, value: Binding<Double>,
                            range: ClosedRange<Double>, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(ToggTheme.text(.body, weight: .semibold)).foregroundStyle(ToggTheme.muted)
                Spacer()
                Text("%\(Int(value.wrappedValue.rounded()))")
                    .font(ToggTheme.text(.body, weight: .bold)).foregroundStyle(ToggTheme.teal).monospacedDigit()
            }
            Slider(value: value, in: range, step: 1)
                .tint(ToggTheme.teal)
                .accessibilityLabel(title)
                .accessibilityIdentifier(identifier)
        }
    }

    private func assumptionRow(title: String, value: Binding<Double>,
                               range: ClosedRange<Double>, step: Double, unit: String) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(ToggTheme.text(.caption)).foregroundStyle(ToggTheme.muted)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            Text("\(ExperienceFormat.oneDecimal(value.wrappedValue)) \(unit)")
                .font(ToggTheme.text(.body, weight: .bold)).foregroundStyle(.white).monospacedDigit()
                .lineLimit(1)
            Stepper("", value: value, in: range, step: step)
                .labelsHidden()
                .scaleEffect(0.8)
                .accessibilityLabel(title)
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(ToggTheme.surfaceVariant))
    }

    private var trugoStations: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.car.fill")
                    .foregroundStyle(ToggTheme.teal)
                    .accessibilityHidden(true)
                Text("En Yakın Trugo Şarj İstasyonları")
                    .font(ToggTheme.text(.lead, weight: .bold)).foregroundStyle(.white)
            }
            VStack(spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .font(ToggTheme.text(.display)).foregroundStyle(ToggTheme.teal)
                Text("Yakındaki istasyonları gör")
                    .font(ToggTheme.text(.body, weight: .semibold)).foregroundStyle(.white)
                Text("Apple Maps üzerinden Trugo ve elektrikli araç şarj noktalarını haritada bul.")
                    .font(.caption).foregroundStyle(ToggTheme.muted).multilineTextAlignment(.center)
                Button { showStations = true } label: {
                    Label("Haritayı aç", systemImage: "map.fill")
                        .font(ToggTheme.text(.caption, weight: .bold)).foregroundStyle(.black)
                        .padding(.horizontal, 16).frame(height: 38)
                        .background(Capsule().fill(ToggTheme.teal))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .dsCard()
        }
    }

    // MARK: - Alt menü

    private var bottomBar: some View {
        HStack(spacing: DSSpace.xxs) {
            ForEach(DashboardTab.allCases) { item in
                Button { tab = item } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.icon)
                            .font(.system(size: 17, weight: tab == item ? .semibold : .regular))
                        Text(item.title)
                            .font(ToggTheme.text(.micro, weight: tab == item ? .bold : .regular))
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(tab == item ? DSColor.accent : DSColor.muted)
                    .background(
                        RoundedRectangle(cornerRadius: DSRadius.row, style: .continuous)
                            .fill(tab == item ? DSColor.accent.opacity(0.12) : .clear)
                    )
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .accessibilityLabel("\(item.title) sekmesi")
                .accessibilityIdentifier("tab.\(item.rawValue)")
                .accessibilityValue(tab == item ? "Seçili" : "")
                .accessibilityAddTraits(tab == item ? .isSelected : [])
            }
        }
        .padding(.horizontal, DSSpace.xs)
        .padding(.top, DSSpace.xs)
        .padding(.bottom, DSSpace.xxs)
        .background(
            DSColor.surface
                .overlay(alignment: .top) {
                    Rectangle().fill(DSColor.outline.opacity(0.5)).frame(height: 1)
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
        guard let stored = climateSettings.target(vin: vehicle.vin) else { return }
        if (16...30).contains(stored) {
            targetTemperature = stored
        }
    }

    @MainActor
    private func refreshClimate() async {
        guard !climateBusy else { return }
        climateBusy = true
        defer { climateBusy = false }
        // VIN çağrı başında yakalanır: döngü sürerken araç değişse de
        // eski aracın yanıtı yeni araca karışmaz.
        let vin = vehicle.vin
        print("[CLIMATE] status query start vin=…\(vin.suffix(4))")
        do {
            let status = try await model.api.climateStatus(vin: vin)
            climateOn = status.active
            climateKnown = true
            climateStatusAt = Date()
            let temperature = status.temperature.map { String($0) } ?? "unknown"
            print("[CLIMATE] status active=\(status.active) temperature=\(temperature)")
            if !climateSettings.hasTarget(vin: vin),
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
        let vin = vehicle.vin
        do {
            if !climateStatusFresh {
                climateNote = "Klima durumu okunuyor…"
                let status = try await model.api.climateStatus(vin: vin)
                climateOn = status.active
                climateKnown = true
                climateStatusAt = Date()
                if !climateSettings.hasTarget(vin: vin),
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
                vin: vin,
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
                let confirmed = try await model.api.climateStatus(vin: vin)
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
        // VIN çağrı başında yakalanır: işlem sürerken araç değişirse
        // doğrulama yeni aracın durumunu eski aracın sonucu sanmasın.
        let vin = vehicle.vin
        climateBusy = true
        defer { climateBusy = false }
        do {
            climateNote = "Hedef sıcaklık gönderiliyor…"
            let result = try await model.api.setClimate(
                vin: vin,
                active: true,
                temperature: targetTemperature
            )
            guard result.status == "COMPLETED" else {
                let status = result.status.isEmpty ? "YANITSIZ" : result.status
                let code = result.code.isEmpty ? "" : " · \(result.code)"
                climateNote = "Sıcaklık komutu \(status)\(code)"
                return
            }
            // Toggle ile aynı dürüstlük: COMPLETED ≠ araç durumu; tek okuma
            // ile doğrulanır. Sıcaklık ±0,25 °C toleransla karşılaştırılır.
            climateNote = "Araç yanıtı doğrulanıyor…"
            let confirmed = try await model.api.climateStatus(vin: vin)
            climateOn = confirmed.active
            climateKnown = true
            climateStatusAt = Date()
            switch confirmed.temperature {
            case .some(let value) where abs(value - targetTemperature) < 0.25:
                climateNote = "Hedef sıcaklık \(climateTemperatureText) olarak uygulandı."
            case .some(let value):
                climateNote = "Komut tamamlandı; araç hedef \(TurkishFormat.decimal(value, digits: 1))°C bildirdi."
            case .none:
                climateNote = "Komut tamamlandı; araç sıcaklığı henüz bildirmedi."
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
            // Ham sürüş modu değerini tanıya yaz: ekranda gösterilen metinle
            // araç durumu uyuşmazsa ham `DRIVEMODE_*` değeriyle ayrım yapılır.
            // VIN/anahtar içermez.
            ble.recordDiagnostic("vehicleInfo · driveMode=\(parsed.driveMode ?? "yok")")
            facingError = nil
            if let odo = parsed.odometerKM {
                drivingStats.record(odometer: odo, batteryPercent: parsed.batteryPercent)
            }
            checkTirePressure(parsed.tires)
            checkAuxiliaryBattery(parsed.auxiliaryBatteryPercent)
            checkChargingTarget(parsed)
            model.noteCloudTelemetry(parsed)
        } catch is CancellationError {
            return
        } catch {
            self.facingError = .from(error)
        }
    }
}
