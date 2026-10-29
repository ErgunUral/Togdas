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
    private let api: ToggAPI
    private var vin = ""
    private var isSharedVehicle = false

    private var reconnectTask: Task<Void, Never>?
    private var pairingTask: Task<Void, Never>?
    private var authTask: Task<Void, Never>?
    private var stableTask: Task<Void, Never>?
    private var attempts = 0
    private var pairingAttempts = 0
    private var authenticatedThisConnection = false
    private var connectedAt: Date?
    private var awaitingConnection = false
    private var hasConnectedOnce = false
    private var lastStartAt: Date?

    private let maxAttempts = 8

    init(ble: BleConnection, api: ToggAPI) {
        self.ble = ble
        self.api = api
    }

    /// Otomatik bağlanma izni: kullanıcı "bağlı tut" dediyse veya yakınlık açıksa.
    var autoConnectEnabled: Bool {
        guard !vin.isEmpty else { return false }
        let defaults = UserDefaults.standard
        return defaults.bool(forKey: "toqdas.ble.keepConnected")
            || defaults.bool(forKey: "toqdas.proximity.enabled.\(vin)")
    }

    func configure(vin: String, isShared: Bool = false) {
        guard !vin.isEmpty else { return }
        if vin != self.vin {
            self.vin = vin
            attempts = 0
            status = ""
        }
        // Araç listesi (ownedVins/friendVins) authoritative source'dur.
        // SharedKeyRequestStore yalnızca API verisi henüz yüklenmediğinde fallback'tir.
        isSharedVehicle = isShared
    }

    func start() {
        guard !vin.isEmpty else { return }
        reconnectTask?.cancel()
        reconnectTask = nil
        attempts = 0
        reconnecting = false
        awaitingConnection = true
        lastStartAt = Date()
        status = "Araç aranıyor…"
        ble.recordDiagnostic("Elle bağlantı başlatıldı")
        ble.start(vin: vin)
    }

    /// Uygulama öne geldiğinde bekleyen geri çekilme süresini atlar.
    /// Android 1.0.24.42'deki "ekran açıldı · etkileşimli" davranışının
    /// iOS karşılığı: telefon ekranı açılınca bağlantı hemen yeniden denenir.
    func handleForeground() {
        guard autoConnectEnabled, ble.isRadioAvailable else { return }
        guard ble.state.isDisconnected || ble.state.isFailed else { return }
        if let lastStartAt, Date().timeIntervalSince(lastStartAt) < 3 { return }
        guard reconnectTask != nil || pairingTask != nil
                || ble.state.isFailed || ble.state.isDisconnected else { return }
        reconnectTask?.cancel()
        reconnectTask = nil
        pairingTask?.cancel()
        pairingTask = nil
        attempts = 0
        ble.recordDiagnostic("foreground_retry · uygulama öne geldi; bekleme atlandı")
        start()
    }

    /// Uygulama açıldığında, kullanıcı bağlı tutmayı seçtiyse kendiliğinden bağlanır.
    func startIfDesired() {
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
        attempts = 0
        pairingAttempts = 0
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
            stableTask?.cancel()
            stableTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled else { return }
                self?.attempts = 0
            }

        case .certificate:
            guard autoConnectEnabled, !authenticatedThisConnection else { return }
            startAutoAuthentication()

        case .disconnected, .failed:
            authenticatedThisConnection = false
            connectedAt = nil
            stableTask?.cancel()
            stableTask = nil
            // Combine `@Published` abonelik anında mevcut değeri yayınlar; ilk
            // "bağlı değil" yayını kopma sayılmamalı.
            guard hasConnectedOnce || awaitingConnection else { return }
            if ble.needsRepair {
                status = ble.lastEvent
                return
            }
            if ble.pairingRequired {
                schedulePairingRetry()
                return
            }
            guard autoConnectEnabled else {
                if !hasConnectedOnce { status = ble.state.description }
                return
            }
            // Bluetooth kapalıyken deneme sayacı tüketilmez; radyo açılınca
            // BleConnection kendiliğinden yeniden bağlanır.
            guard ble.isRadioAvailable else {
                status = ble.failureSummary ?? "Bluetooth kapalı"
                reconnecting = false
                return
            }
            silentRecovery = hasConnectedOnce
            scheduleReconnect()

        default:
            break
        }
    }

    private func scheduleReconnect() {
        guard reconnectTask == nil else { return }
        guard attempts < maxAttempts else {
            reconnecting = false
            status = "Otomatik yeniden bağlanma durdu (\(maxAttempts) deneme). Araç yakınında Bluetooth'u kapatıp açıp yeniden deneyin."
            ble.recordDiagnostic(status)
            return
        }
        attempts += 1
        let delay = min(pow(2.0, Double(attempts - 1)) * 1.5, 15.0)
        reconnecting = true
        status = hasConnectedOnce ? "Bağlantı yeniden kuruluyor…" : "Araç aranıyor…"
        ble.recordDiagnostic(
            "ble_reconnect · \(String(format: "%.1f", delay)) sn sonra deneme \(attempts)/\(maxAttempts)"
        )
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.reconnectTask = nil
            guard self.autoConnectEnabled,
                  self.ble.state.isDisconnected || self.ble.state.isFailed else { return }
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
        guard pairingAttempts < 30 else {
            status = "Araç eşleştirmesi tamamlanmadı. Araç ekranından eşleştirmeyi başlatıp yeniden deneyin."
            return
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
