import Foundation
import Combine

/// BLE bağlantısının yaşam döngüsünü panonun dışında yönetir.
///
/// Neden gerekli: araçla bağlantı sinyal zayıflığında `CBError.connectionTimeout`
/// (kod 6) ile kopuyor. Önceden yeniden bağlanma yalnızca pano açıkken ve
/// `keepBLEConnected` açıkken çalışıyordu. Bu sınıf:
/// - kopmada sınırlı sayıda geri çekilmeli (2/4/8/16/30 sn) yeniden bağlanır,
/// - yeniden bağlanınca önbellekteki sertifika ve araç anahtarıyla otomatik
///   kimlik doğrulama başlatır (ağ yoksa önbellekle),
/// - 60 sn kararlı bağlantıdan sonra deneme sayacını sıfırlar.
/// Komut göndermez; komutlar yalnızca READY + taze telemetri ile panodan gider.
@MainActor
final class BleLinkCoordinator: ObservableObject {
    @Published private(set) var status = ""
    @Published private(set) var reconnecting = false
    /// Daha önce kurulmuş bir oturum koptuğunda panonun "hata" göstermemesi
    /// için sessiz toparlama modu. Android uygulaması da kopmayı kullanıcıya
    /// yansıtmadan arka planda yeniden kurar.
    @Published private(set) var silentRecovery = false

    private let ble: BleConnection
    private let api: ToggAPIClient
    private let preferences: GaragePreferences
    private var vin = ""
    private var isSharedVehicle = false

    private var reconnectTask: Task<Void, Never>?
    private var pairingTask: Task<Void, Never>?
    private var authTask: Task<Void, Never>?
    private var stableTask: Task<Void, Never>?
    private var attempts = 0
    private var pairingAttempts = 0
    /// Üst üste zayıf sinyalle kopma sayısı; `weakDropLimit` aşılınca
    /// yeniden bağlanma 60 sn'ye seyreltilir (radyo/pil yükü).
    private var weakDrops = 0
    private var authenticatedThisConnection = false
    private var connectedAt: Date?
    private var awaitingConnection = false
    private var hasConnectedOnce = false
    private var lastStartAt: Date?

    /// İlk telemetri gözcüsü (Android .57 `j4` paritesi). Etiketler **yalnız
    /// tanı günlüğüne** yazılır; yeniden bağlanma kararı `BleReconnectPolicy`
    /// ve mevcut `handleDrop` akışında kalır.
    private var watchdog = BleStatusWatchdog()
    private var watchdogSession = 0
    private var watchdogTask: Task<Void, Never>?
    private var lastWatchdogLabel = ""

    init(ble: BleConnection, api: ToggAPI, preferences: GaragePreferences = GaragePreferences()) {
        self.ble = ble
        self.api = api
        self.preferences = preferences
    }

    /// Otomatik bağlanma izni: kullanıcı "bağlı tut" dediyse veya yakınlık açıksa.
    var autoConnectEnabled: Bool {
        preferences.autoConnectEnabled(for: vin)
    }

    func configure(vin: String, isShared: Bool = false) {
        guard !vin.isEmpty else { return }
        if vin != self.vin {
            self.vin = vin
            attempts = 0
            weakDrops = 0
            status = ""
        }
        // Araç listesi (ownedVins/friendVins) authoritative source'dur.
        // SharedKeyRequestStore yalnızca API verisi henüz yüklenmediğinde fallback'tir.
        isSharedVehicle = isShared
    }

    /// `clearRepair` yalnız kullanıcı onarımı açıkça yeniden denediğinde
    /// `true` olur (`retryAfterRepair`). Otomatik yollar onarım kilidini açmaz.
    func start(clearRepair: Bool = false) {
        guard !vin.isEmpty else { return }
        reconnectTask?.cancel()
        reconnectTask = nil
        attempts = 0
        reconnecting = false
        awaitingConnection = true
        lastStartAt = Date()
        status = "Araç aranıyor…"
        ble.recordDiagnostic(clearRepair ? "Onarım sonrası elle bağlantı" : "Elle bağlantı başlatıldı")
        ble.start(vin: vin, clearRepair: clearRepair)
    }

    /// Eşleşme kurtarma kullanıcı adımları tamamlandıktan sonraki tek deneme.
    /// Onarım kilidini açan **tek** yol budur.
    func retryAfterRepair() {
        weakDrops = 0
        attempts = 0
        ble.recordDiagnostic("repair_retry · kullanıcı onarımı yeniden denedi")
        start(clearRepair: true)
    }

    /// Uygulama öne geldiğinde bekleyen geri çekilme süresini atlar.
    /// Android 1.0.24.42'deki "ekran açıldı · etkileşimli" davranışının
    /// iOS karşılığı: telefon ekranı açılınca bağlantı hemen yeniden denenir.
    func handleForeground() {
        if ble.needsRepair {
            ble.recordDiagnostic("foreground_retry_skipped · eşleşme onarımı bekleniyor")
            return
        }
        let sinceLastStart = lastStartAt.map { Date().timeIntervalSince($0) }
        guard BleReconnectPolicy.shouldRetryOnForeground(
            autoConnectEnabled: autoConnectEnabled,
            radioAvailable: ble.isRadioAvailable,
            stateDisconnectedOrFailed: ble.state.isDisconnected || ble.state.isFailed,
            sinceLastStart: sinceLastStart,
            hasPendingTimerOrDisconnected: reconnectTask != nil || pairingTask != nil
                || ble.state.isFailed || ble.state.isDisconnected
        ) else { return }
        reconnectTask?.cancel()
        reconnectTask = nil
        pairingTask?.cancel()
        pairingTask = nil
        attempts = 0
        // Kullanıcı ekranı açtı: zayıf sinyal seyreltmesi sıfırlanır.
        weakDrops = 0
        ble.recordDiagnostic("foreground_retry · uygulama öne geldi; bekleme atlandı")
        start()
    }

    /// Uygulama açıldığında, kullanıcı bağlı tutmayı seçtiyse kendiliğinden bağlanır.
    func startIfDesired() {
        guard !ble.needsRepair else { return }
        guard autoConnectEnabled,
              ble.state.isDisconnected || ble.state.isFailed else { return }
        ble.recordDiagnostic("Otomatik bağlantı: bağlı tutma/yakınlık açık")
        start()
    }

    func stop() {
        reconnectTask?.cancel()
        reconnectTask = nil
        pairingTask?.cancel()
        pairingTask = nil
        authTask?.cancel()
        authTask = nil
        stableTask?.cancel()
        stableTask = nil
        watchdogTask?.cancel()
        watchdogTask = nil
        lastWatchdogLabel = ""
        attempts = 0
        pairingAttempts = 0
        weakDrops = 0
        reconnecting = false
        silentRecovery = false
        authenticatedThisConnection = false
        connectedAt = nil
        awaitingConnection = false
        hasConnectedOnce = false
        status = ""
        ble.forgetLastPeripheral()
        ble.stop()
    }

    /// Paneldeki "Sertifikayı sun" / sahip anahtarını taşıma düğmesi.
    func authenticateNow(overwriteOwner: Bool = false) async throws {
        authTask?.cancel()
        authTask = nil
        try await authenticate(overwriteOwner: overwriteOwner)
    }

    func handle(state: BleConnection.State) {
        switch state {
        case .ready:
            if connectedAt == nil { connectedAt = Date() }
            awaitingConnection = false
            hasConnectedOnce = true
            attempts = 0
            reconnecting = false
            silentRecovery = false
            pairingTask?.cancel()
            pairingTask = nil
            pairingAttempts = 0
            status = "Bağlı"
            beginWatchdog()
            stableTask?.cancel()
            stableTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled else { return }
                self?.attempts = 0
                self?.weakDrops = 0
            }

        case .certificate:
            guard autoConnectEnabled, !authenticatedThisConnection else { return }
            startAutoAuthentication()

        case .disconnected, .failed:
            authenticatedThisConnection = false
            connectedAt = nil
            stableTask?.cancel()
            stableTask = nil
            watchdogTask?.cancel()
            watchdogTask = nil
            lastWatchdogLabel = ""
            handleDrop()

        default:
            break
        }
    }

    /// Bağlıyken gözcüyü başlatır: 15 sn'de bir etiket üretir ve **yalnızca
    /// etiket değiştiğinde** tanı günlüğüne yazar. Telemetri yoksa ilk durum
    /// zaman aşımı, bayat telemetri varsa stale etiketi gelir. Kopmada döngü
    /// iptal edilir; hiçbir bağlantı eylemi tetiklemez.
    private func beginWatchdog() {
        watchdogSession += 1
        let session = watchdogSession
        lastWatchdogLabel = ""
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !Task.isCancelled, let self else { return }
                let age = self.ble.telemetry.map { Date().timeIntervalSince($0.receivedAt) }
                let label = self.watchdog.reason(
                    session: session,
                    now: Date(),
                    telemetryAge: age
                )
                guard !label.isEmpty, label != self.lastWatchdogLabel else { continue }
                self.lastWatchdogLabel = label
                self.ble.recordDiagnostic("ble_watchdog · \(label)")
            }
        }
    }

    /// Kopma kararını saf politikaya devreder; politika yalnızca eylem üretir.
    private func handleDrop() {
        // Zayıf sinyalle kopma sayacı: yalnız gerçek oturum kopmalarında artar
        // (ilk "bağlı değil" yayını sayılmaz).
        if hasConnectedOnce, let rssi = ble.rssi,
           rssi < BleReconnectPolicy.weakSignalThreshold {
            weakDrops += 1
            ble.recordDiagnostic("weak_drop · \(rssi) dBm; üst üste \(weakDrops)")
        }
        let decision = BleReconnectPolicy.action(
            connectedBefore: hasConnectedOnce,
            awaitingConnection: awaitingConnection,
            needsRepair: ble.needsRepair,
            repairStatus: ble.lastEvent,
            pairingRequired: ble.pairingRequired,
            autoConnectEnabled: autoConnectEnabled,
            radioAvailable: ble.isRadioAvailable,
            radioFailureStatus: ble.failureSummary,
            attempts: attempts,
            pairingAttempts: pairingAttempts,
            lastRSSI: ble.rssi,
            consecutiveWeakDrops: weakDrops
        )

        switch decision {
        case .ignore:
            return
        case .repair(let message):
            status = message
        case .pairingWait:
            schedulePairingRetry()
        case .pairingExhausted(let message):
            status = message
        case .showStatus(let message):
            if !message.isEmpty { status = message }
        case .waitForRadio(let message):
            status = message
            reconnecting = false
        case .stopped(let message):
            reconnecting = false
            status = message
            ble.recordDiagnostic(message)
        case .reconnect(let delay, let attempt):
            silentRecovery = hasConnectedOnce
            scheduleReconnect(delay: delay, attempt: attempt)
        }
    }

    private func scheduleReconnect(delay: TimeInterval, attempt: Int) {
        guard reconnectTask == nil else { return }
        attempts = attempt
        reconnecting = true
        status = hasConnectedOnce ? "Bağlantı yeniden kuruluyor…" : "Araç aranıyor…"
        ble.recordDiagnostic(
            "ble_reconnect · \(TurkishFormat.decimal(delay, digits: 1)) sn sonra deneme \(attempt)/\(BleReconnectPolicy.maxAttempts)"
        )
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.reconnectTask = nil
            guard self.autoConnectEnabled,
                  self.ble.state.isDisconnected || self.ble.state.isFailed else { return }
            guard !self.ble.needsRepair else {
                // Onarım kilidi: otomatik denemeler burada durur, kullanıcı
                // adımları tamamlayıp "Yeniden dene"ye basana kadar sürmez.
                self.reconnecting = false
                self.status = self.ble.lastEvent
                self.ble.recordDiagnostic("ble_reconnect_blocked · eşleşme onarımı gerekli")
                return
            }
            self.lastStartAt = Date()
            self.ble.start(vin: self.vin)
        }
    }

    /// Araç anahtarı yokken hızlı geri çekilme yerine seyrek deneme yapılır.
    /// Kullanıcı araç ekranından eşleştirmeyi başlattığında anahtar bu denemede
    /// yakalanır; Android uygulamasındaki "pending certificate" akışının karşılığı.
    private func schedulePairingRetry() {
        guard pairingTask == nil else { return }
        reconnecting = false
        silentRecovery = hasConnectedOnce
        let message = "Araç eşleştirmesi bekleniyor… Araç ekranından dijital anahtar eşleştirmesini başlatın."
        if status != message {
            status = message
            ble.recordDiagnostic("pairing_wait · araç anahtarı yok; 20 sn'de bir yeniden denenecek")
        }
        pairingAttempts += 1
        pairingTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.pairingTask = nil
            guard self.autoConnectEnabled else { return }
            guard self.ble.pairingRequired || self.ble.state.isDisconnected || self.ble.state.isFailed else { return }
            self.attempts = 0
            self.ble.start(vin: self.vin)
        }
    }

    private func startAutoAuthentication() {        guard authTask == nil, !vin.isEmpty else { return }
        authTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.authenticate(overwriteOwner: false)
            } catch is CancellationError {
                return
            } catch {
                self.authenticatedThisConnection = false
                self.status = "Otomatik kimlik doğrulama başarısız: \(error.localizedDescription)"
                self.ble.recordDiagnostic(self.status)
            }
            self.authTask = nil
        }
    }

    private func authenticate(overwriteOwner: Bool) async throws {
        guard !vin.isEmpty else { throw AppError.message("Araç seçili değil.") }
        let pair = try PhoneKeyStore.keyPair(for: vin)
        let hex = pair.publicKey.hexString
        let record = try await api.ensureCertificate(
            vin: vin,
            phonePublicKeyHex: hex,
            overwriteOwner: overwriteOwner,
            isShared: isSharedVehicle
        )
        try Task.checkCancellation()
        authenticatedThisConnection = true
        ble.recordDiagnostic("Kimlik doğrulama başlatılıyor (sertifika \(record.certificateBase64.count) bayt)")
        try ble.beginAuthentication(
            vin: vin,
            certificateBase64: record.certificateBase64,
            carKey: record.carPublicKey
        )
    }
}
