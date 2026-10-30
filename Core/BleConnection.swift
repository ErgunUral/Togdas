import CoreBluetooth
import CryptoKit
import Foundation
import Security

private func bleLog(_ message: String) {
    NSLog("[ToqdasBLE] %@", message)
}

/// BLE taşıma + dijital anahtar el sıkışması.
/// Paket biçimleri Garajm/BleProtocol.kt ile aynıdır. Komutlar ancak araç kimliği
/// doğrulandıktan (READY) sonra gönderilir.
final class BleConnection: NSObject, ObservableObject, CBPeripheralDelegate {
    enum State {
        case disconnected, connecting, discovering, certificate, challenge, authenticated, ready, failed(BLEIssue)
    }

    @Published private(set) var state = State.disconnected {
        didSet {
            bleLog("durum: \(state.description)")
            recordDiagnostic("Bağlantı durumu: \(state.description)")
        }
    }
    @Published private(set) var channels: [String] = []
    @Published private(set) var lastEvent = ""
    @Published private(set) var vin = ""
    @Published private(set) var phonePublicKeyHex = ""
    @Published private(set) var carPublicKeyHex = ""
    @Published private(set) var telemetry: BleTelemetry?
    @Published private(set) var rssi: Int?
    @Published private(set) var rssiUpdatedAt: Date?
    @Published private(set) var needsRepair = false
    /// Araç anahtarı yok: araç ekranından eşleştirme başlatılması gerekiyor.
    /// Bu durumda yeniden bağlanma döngüsü hızlı geri çekilmeyi bırakır ama
    /// eşleştirme başlatıldığında anahtarı yakalamak için seyrek denemeye devam eder.
    @Published private(set) var pairingRequired = false
    /// Panoda gösterilen tek satır hata özeti. Android 1.0.24.42'deki GATT
    /// hata gruplarının iOS karşılığı; ayrıntı `diagnosticEvents` içinde.
    @Published private(set) var failureSummary: String?
    @Published private(set) var lastCommandReceipt: BLECommandReceipt?
    @Published private(set) var commandHistory = BLECommandHistoryStore.load()
    @Published private(set) var lockConfirmationCount = 0
    @Published private(set) var diagnosticEvents = BLEDiagnosticStore.load()
    private var lastLoggedTelemetrySummary: String?
    private var lastRSSIDiagnosticAt: Date?
    private var lastRSSIDiagnosticValue: Int?

    private let transport: any BLETransporting
    private var peripheral: CBPeripheral?
    private var commandChar: CBCharacteristic?
    private var telemetryChar: CBCharacteristic?
    private var timeChar: CBCharacteristic?

    private let serviceUUID = CBUUID(string: "f0002412-0451-4000-b000-000000000000")
    private let commandUUID = CBUUID(string: "f0002413-0451-4000-b000-000000000000")
    private let telemetryUUID = CBUUID(string: "f0002415-0451-4000-b000-000000000000")
    private let timeServiceUUID = CBUUID(string: "00001805-0000-1000-8000-00805f9b34fb")
    private let timeUUID = CBUUID(string: "00002a2b-0000-1000-8000-00805f9b34fb")

    private struct PendingWrite {
        let data: Data
        let characteristic: CBCharacteristic
    }

    private struct PendingCommand {
        let code: UInt8
        let action: String
    }

    private var connectedAt: Date?

    private var writeQueue: [PendingWrite] = []
    private var writing = false
    private var wantsScan = false
    /// Kullanıcı "bağlı tut" dediyse radyo kapanıp açıldığında kendiliğinden
    /// yeniden bağlanılır (Android'deki Bluetooth STATE_ON davranışı).
    private var shouldStayConnected = false
    private var radioWasPoweredOff = false
    private var failureCounter = BleFailureCounter()
    private var discoveryPending = Set<CBUUID>()
    private var targetVIN = ""
    private var lastPeripheral: CBPeripheral?
    private var lastPeripheralVIN = ""
    private var scanTimeoutTask: Task<Void, Never>?

    // El sıkışma durumu
    private var phoneKey: SecKey?
    private var currentChallenge: Data?
    private var phoneNonce: Data?
    private var trustedCarKey: P256.Signing.PublicKey?
    private var expectedCarKey: Data?
    private var carTimeAtRead: Date?
    private var carTimeReadAt: Date?
    private var pendingCommand: PendingCommand?
    private var pendingCommandNonce: Data?
    private var lockAfterWindowsClose = false
    private var waitingForCommandTime = false
    private var waitingForCommandNonce = false
    private var pendingLockVerification: Bool?
    private var commandTimeoutTask: Task<Void, Never>?
    private var commandVerificationTask: Task<Void, Never>?
    private var certificateQueued = false
    private var certificateWritesFinished = false
    private var certificateFrames: [Data] = []
    private var certificateFrameIndex = 0
    private var waitingForInitialKeyRequest = false
    private var initialKeyRequestSeen = false
    private var certificateFrame2AckReceived = false
    private var keyRequestPending = false
    private var lastWrittenLength = 0
    private var challengeRequestSent = false
    private var waitingForVehicleKey = false
    private var waitingForPhoneAck = false
    private var waitingForCarProof = false
    private var vehicleKeyFrameLength = 0
    private var challengeDelayTask: Task<Void, Never>?
    private var initialRequestFallbackTask: Task<Void, Never>?
    private var frameTwoFallbackTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var rssiTimer: Timer?
    private var rssiPollingInterval: TimeInterval = 6

    var hasFreshSignedTelemetry: Bool {
        guard let telemetry else { return false }
        let age = Date().timeIntervalSince(telemetry.receivedAt)
        return age >= 0 && age < BLECommandPolicy.telemetryFreshness
    }

    /// Common UI gate for lock/unlock and watch commands.
    var canSendVehicleCommands: Bool {
        BLECommandPolicy.rejection(code: 2, linkReady: state.isReady, telemetry: telemetry) == nil
            && commandChar != nil && phoneKey != nil
    }

    override convenience init() {
        self.init(transport: BLETransport())
    }

    init(transport: any BLETransporting) {
        self.transport = transport
        super.init()
        // Arka planda sistem uygulamayı sonlandırırsa bağlantı bilgisi geri
        // yüklenir; aksi halde her geri dönüşte sıfırdan tarama gerekiyordu.
        transport.delegate = self
    }

    func recordDiagnostic(_ message: String) {
        let safeMessage: String
        if !vin.isEmpty {
            safeMessage = message.replacingOccurrences(of: vin, with: "…\(vin.suffix(4))")
        } else {
            safeMessage = message
        }
        diagnosticEvents.append(BLEDiagnosticEvent(id: UUID(), timestamp: Date(), message: safeMessage))
        if diagnosticEvents.count > BLEDiagnosticStore.limit {
            diagnosticEvents.removeFirst(diagnosticEvents.count - BLEDiagnosticStore.limit)
        }
        BLEDiagnosticStore.save(diagnosticEvents)
        bleLog("tanı: \(safeMessage)")
    }

    func clearDiagnosticEvents() {
        diagnosticEvents.removeAll()
        BLEDiagnosticStore.save([])
    }

    // MARK: - Bağlantı

    func start(vin: String? = nil) {
        if let vin, !vin.isEmpty { targetVIN = vin.uppercased() }
        wantsScan = true
        shouldStayConnected = true
        needsRepair = false
        pairingRequired = false
        failureSummary = nil
        switch transport.state {
        case .poweredOn:
            state = .connecting
            // Araç oturumu 60 sn'de kapatıyor; yeniden taramak yerine bilinen
            // çevrebirime doğrudan bağlanmak kopma boşluğunu ~4 sn kısaltır.
            if let known = lastPeripheral, known.state == .disconnected, lastPeripheralVIN == targetVIN {
                lastEvent = "Araç yeniden bağlanıyor…"
                recordDiagnostic("gatt_direct_reconnect · tarama atlandı")
                connect(to: known)
                armConnectWatchdog()
                return
            }
            lastEvent = "Araç aranıyor…"
            beginScanPhase(0)
        case .poweredOff, .unauthorized, .unsupported:
            lastEvent = "Bluetooth kullanılamıyor"
            state = .failed(.radioUnavailable)
            wantsScan = false
        default:
            lastEvent = "Bluetooth hazırlanıyor…"
        }
    }

    func stop(keepTelemetry: Bool = false) {
        wantsScan = false
        // Beklenmeyen kopmada niyet korunur: radyo geri gelince yeniden bağlanılır.
        if !keepTelemetry { shouldStayConnected = false }
        cancelScanTimeout()
        writeQueue.removeAll()
        writing = false
        certificateQueued = false
        challengeDelayTask?.cancel()
        challengeDelayTask = nil
        initialRequestFallbackTask?.cancel()
        initialRequestFallbackTask = nil
        frameTwoFallbackTask?.cancel()
        frameTwoFallbackTask = nil
        disarmTimeout()
        stopRSSI()
        connectedAt = nil
        transport.stop()
        resetSession()
        state = .disconnected
        lastEvent = keepTelemetry ? "Bağlantı yeniden kuruluyor…" : "Bağlantı durduruldu"
        channels = []
        // Beklenmeyen kopmada son telemetri korunur: pano boşalıp "koptu"
        // görüntüsü oluşmasın. Tazelik `receivedAt` ile denetlenir.
        if !keepTelemetry { telemetry = nil }
    }

    func disconnect() { stop() }

    /// Son komutları ve ekrandaki son komut kartını temizler.
    func clearCommandHistory() {
        commandHistory = []
        lastCommandReceipt = nil
        BLECommandHistoryStore.save([])
    }

    /// Elle bağlantı kesildiğinde doğrudan yeniden bağlanma hedefini unutur.
    func forgetLastPeripheral() {
        lastPeripheral = nil
        lastPeripheralVIN = ""
    }

    private func resetSession() {
        peripheral = nil
        commandChar = nil
        telemetryChar = nil
        timeChar = nil
        discoveryPending.removeAll()
        currentChallenge = nil
        phoneNonce = nil
        carTimeAtRead = nil
        carTimeReadAt = nil
        lastLoggedTelemetrySummary = nil
        pendingCommand = nil
        pendingCommandNonce = nil
        lastCommandReceipt = nil
        lockAfterWindowsClose = false
        waitingForCommandTime = false
        waitingForCommandNonce = false
        pendingLockVerification = nil
        commandTimeoutTask?.cancel()
        commandTimeoutTask = nil
        commandVerificationTask?.cancel()
        commandVerificationTask = nil
        trustedCarKey = nil
        expectedCarKey = nil
        certificateQueued = false
        certificateWritesFinished = false
        certificateFrames = []
        certificateFrameIndex = 0
        waitingForInitialKeyRequest = false
        initialKeyRequestSeen = false
        certificateFrame2AckReceived = false
        keyRequestPending = false
        challengeRequestSent = false
        waitingForVehicleKey = false
        waitingForPhoneAck = false
        waitingForCarProof = false
        vehicleKeyFrameLength = 0
        challengeDelayTask?.cancel()
        challengeDelayTask = nil
        initialRequestFallbackTask?.cancel()
        initialRequestFallbackTask = nil
        frameTwoFallbackTask?.cancel()
        frameTwoFallbackTask = nil
        phoneKey = nil
        vin = ""
        phonePublicKeyHex = ""
        carPublicKeyHex = ""
        rssi = nil
        rssiUpdatedAt = nil
    }

    func connect(to peripheral: CBPeripheral) {
        guard transport.isRadioOn else { return }
        wantsScan = false
        needsRepair = false
        cancelScanTimeout()
        transport.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        transport.connect(peripheral)
        bleLog("bağlanılıyor: \(peripheral.name ?? "isimsiz") id=\(peripheral.identifier)")
        state = .connecting
        lastEvent = "Bağlanıyor…"
        print("[BLE] connecting to \(peripheral.name ?? "?") id=\(peripheral.identifier)")
    }

    // MARK: - Dijital anahtar / el sıkışma

    /// API'den alınan sertifikayı araca sunar ve kimlik doğrulamayı başlatır.
    func beginAuthentication(vin: String, certificateBase64: String, carKey: String) throws {
        guard state.isCertificate || state.isChallenge else {
            throw AppError.message("Önce araca bağlanın.")
        }
        guard commandChar != nil else {
            throw AppError.message("Araç komut kanalı bulunamadı.")
        }
        guard let certificateData = Data(base64Encoded: certificateBase64) else {
            throw AppError.message("Sertifika çözümlenemedi.")
        }
        let certificate: Data
        if certificateData.count == 255, certificateData.starts(with: BLEProtocol.certificateHeader) {
            certificate = Data(certificateData.dropFirst(8))
        } else {
            certificate = certificateData
        }
        let pair = try PhoneKeyStore.keyPair(for: vin)
        let publicKey = pair.publicKey
        _ = try BLEProtocol.boundCertificate(certificate, vin: vin, devicePublicKey: publicKey)

        phoneKey = pair.key
        self.vin = vin
        phonePublicKeyHex = publicKey.hexString
        expectedCarKey = normalizedCarKey(carKey)
        carPublicKeyHex = expectedCarKey?.hexString ?? ""
        if let expectedCarKey {
            do { trustedCarKey = try BLEProtocol.publicKey(expectedCarKey) }
            catch { throw AppError.message("Araç doğrulama anahtarı geçersiz.") }
        }
        currentChallenge = nil
        phoneNonce = nil
        pendingCommand = nil
        pendingCommandNonce = nil
        lastCommandReceipt = nil
        lockAfterWindowsClose = false
        waitingForCommandTime = false
        waitingForCommandNonce = false
        pendingLockVerification = nil
        commandTimeoutTask?.cancel()
        commandTimeoutTask = nil
        commandVerificationTask?.cancel()
        commandVerificationTask = nil
        challengeRequestSent = false
        certificateWritesFinished = false
        certificateFrames = try BLEProtocol.certificateFrames(certificate)
        certificateFrameIndex = 0
        certificateFrame2AckReceived = false
        waitingForInitialKeyRequest = false
        waitingForVehicleKey = false
        waitingForPhoneAck = false
        waitingForCarProof = false
        vehicleKeyFrameLength = 0
        certificateQueued = false
        state = .certificate
        lastEvent = "Sertifika araca sunuluyor…"
        recordDiagnostic("cert_present · sertifika sunumu başladı; sunucu araç anahtarı \(trustedCarKey == nil ? "yok" : "var")")
        print("[BLE] presenting certificate vin=…\(vin.suffix(4)) frames=\(certificateFrames.count) firstTime=\(trustedCarKey == nil) initialRequestSeen=\(initialKeyRequestSeen)")

        // Resmî akış: araç önce 1000000001000000 ile sertifika isteğini gönderir,
        // ardından iki sertifika çerçevesi sırayla yazılır ve her çerçevenin
        // onayı beklenir. Onaylar gelmeden araç anahtarı istenmez.
        if initialKeyRequestSeen {
            startCertificateFrames()
        } else {
            waitingForInitialKeyRequest = true
            armTimeout(6, .handshakeTimeout("Araç sertifika isteği göndermedi."))
            armInitialRequestFallback()
        }
    }

    private func armInitialRequestFallback() {
        initialRequestFallbackTask?.cancel()
        initialRequestFallbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                guard self.waitingForInitialKeyRequest else { return }
                print("[BLE] initial certificate request not seen; presenting after fallback")
                self.lastEvent = "Araç sertifika isteği görülmedi; sertifika yine de sunuluyor"
                self.startCertificateFrames()
            }
        }
    }

    private func startCertificateFrames() {
        initialRequestFallbackTask?.cancel()
        initialRequestFallbackTask = nil
        disarmTimeout()
        waitingForInitialKeyRequest = false
        initialKeyRequestSeen = false
        certificateFrame2AckReceived = false
        keyRequestPending = false
        certificateWritesFinished = false
        guard commandChar != nil, !certificateFrames.isEmpty else {
            state = .failed(.certificatePreparationFailed)
            return
        }
        // Resmî akış: önce 1. çerçeve yazılır ve `1001ef…` onayı beklenir,
        // ardından 2. çerçeve yazılır. Bazı araç yazılımları 1. çerçeveyi
        // tek başına onaylamazsa 2 sn sonra 2. çerçeve yine de gönderilir.
        certificateFrameIndex = 0
        sendNextCertificateFrame()
        lastEvent = "Sertifika araca sunuluyor…"
        armTimeout(10, .handshakeTimeout("Araç sertifikayı yanıtlamadı."))
    }

    private func sendNextCertificateFrame() {
        guard let commandChar, certificateFrameIndex < certificateFrames.count else { return }
        let number = certificateFrameIndex + 1
        let frame = certificateFrames[certificateFrameIndex]
        certificateFrameIndex += 1
        print("[BLE] certificate frame \(number)/\(certificateFrames.count) len=\(frame.count)")
        enqueue(frame, to: commandChar)
        if number == 1, certificateFrames.count > 1 {
            armFrameTwoFallback()
        }
    }

    private func armFrameTwoFallback() {
        frameTwoFallbackTask?.cancel()
        frameTwoFallbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                guard self.certificateFrameIndex == 1, !self.certificateFrame2AckReceived else { return }
                print("[BLE] frame 1 ack not seen; sending frame 2 after fallback")
                self.sendNextCertificateFrame()
            }
        }
    }

    private func markCertificateWritesFinished() {
        guard certificateFrameIndex == certificateFrames.count,
              !certificateWritesFinished,
              !certificateFrames.isEmpty else { return }
        certificateWritesFinished = true
        print("[BLE] certificate frames written")
    }

    private func requestVehicleKey(force: Bool = false) {
        guard let commandChar else { return }
        guard force || !waitingForVehicleKey else { return }
        waitingForVehicleKey = true
        state = .certificate
        lastEvent = "Sertifika sunuldu; araç doğrulama anahtarı isteniyor"
        print("[BLE] vehicle key request (force=\(force))")
        enqueue(BLEProtocol.vehicleKeyRequest, to: commandChar)
        armPairingTimeout(10)
    }

    /// Araç anahtarı gelmezse bunu "eşleştirme gerekiyor" olarak işaretler.
    /// Android uygulaması da aynı durumu `vehicleKeyMissing` olarak saklayıp
    /// eşleştirme tamamlanınca akışı kaldığı yerden sürdürür.
    private func armPairingTimeout(_ seconds: Double) {
        disarmTimeout()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                guard !self.state.isReady else { return }
                self.pairingRequired = true
                self.state = .failed(.vehicleKeyMissing)
                self.lastEvent = "Araç doğrulama anahtarı yok. Araç ekranından dijital anahtar eşleştirmesini başlatın."
                self.recordDiagnostic("vehicleKeyMissing · araç doğrulama anahtarı gönderilmedi")
            }
        }
    }

    /// Sertifika yerine yalnızca aracın açık anahtarını bekler (tanılama).
    func expectVehicleKey(_ key: String) {
        expectedCarKey = normalizedCarKey(key)
        carPublicKeyHex = expectedCarKey?.hexString ?? ""
    }

    // MARK: - Komutlar

    @discardableResult
    func lock() -> Bool {
        lockAfterWindowsClose = true
        if !sendCommand(code: 7, action: "Kapı kilidinden önce camları kapat") {
            lockAfterWindowsClose = false
            return false
        }
        return true
    }
    @discardableResult func unlock() -> Bool { sendCommand(code: 2, action: "Kilidi aç") }
    @discardableResult func trunkOpen() -> Bool { sendCommand(code: 4, action: "Bagajı aç") }
    @discardableResult func trunkClose() -> Bool { sendCommand(code: 5, action: "Bagajı kapat") }
    @discardableResult func windowsOpen() -> Bool { sendCommand(code: 6, action: "Yan camları aç") }
    @discardableResult func windowsClose() -> Bool { sendCommand(code: 7, action: "Yan camları kapat") }
    @discardableResult func driveAuthorize() -> Bool { sendCommand(code: 14, action: "Sürüş yetkilendir") }

    @discardableResult
    private func sendCommand(code: UInt8, action: String) -> Bool {
        let hasActiveCommand = pendingCommand != nil || pendingLockVerification != nil
        if let rejection = BLECommandPolicy.rejection(code: code, linkReady: state.isReady, telemetry: telemetry) {
            lastEvent = rejection.message
            if !hasActiveCommand {
                recordCommandReceipt(code: code, action: action, phase: .failed, detail: rejection.message)
            }
            recordDiagnostic("command_gate_rejected · \(action): \(rejection.diagnosticCode)")
            return false
        }
        guard commandChar != nil else {
            lastEvent = "Komut kanalı yok."
            if !hasActiveCommand {
                recordCommandReceipt(code: code, action: action, phase: .failed, detail: "Komut kanalı yok.")
            }
            return false
        }
        guard phoneKey != nil else {
            lastEvent = "Telefon imza anahtarı yok."
            if !hasActiveCommand {
                recordCommandReceipt(code: code, action: action, phase: .failed, detail: "Telefon imza anahtarı yok.")
            }
            return false
        }
        guard !hasActiveCommand else {
            lastEvent = "Önceki komut yanıtı bekleniyor."
            return false
        }

        pendingCommand = PendingCommand(code: code, action: action)
        pendingCommandNonce = nil
        pendingLockVerification = nil
        commandTimeoutTask?.cancel()
        commandVerificationTask?.cancel()
        commandVerificationTask = nil
        lastEvent = "Araç saati ve tek kullanımlık komut sorusu alınıyor"
        recordCommandReceipt(code: code, action: action, phase: .queued, detail: lastEvent)

        if let readAt = carTimeReadAt,
           Date().timeIntervalSince(readAt) < 30 {
            requestCommandNonce()
            return true
        } else if let timeChar, let peripheral {
            waitingForCommandTime = true
            armCommandTimeout(8, "Araç saati okunamadı; komut gönderilmedi.")
            peripheral.readValue(for: timeChar)
            return true
        } else {
            pendingCommand = nil
            lastEvent = "Araç saati kanalı kullanılamıyor; komut gönderilmedi."
            advanceCommandReceipt(.failed, detail: lastEvent)
            return false
        }
    }

    private func recordCommandReceipt(
        code: UInt8,
        action: String,
        phase: BLECommandReceipt.Phase,
        detail: String?
    ) {
        let receipt = BLECommandReceipt(
            code: code,
            action: action,
            phase: phase,
            detail: detail,
            updatedAt: Date()
        )
        lastCommandReceipt = receipt
        commandHistory = BLECommandHistoryStore.append(receipt, to: commandHistory)
        BLECommandHistoryStore.save(commandHistory)
    }

    private func advanceCommandReceipt(_ phase: BLECommandReceipt.Phase, detail: String? = nil) {
        guard var receipt = lastCommandReceipt else { return }
        receipt.phase = phase
        receipt.detail = detail
        receipt.updatedAt = Date()
        lastCommandReceipt = receipt
        commandHistory = BLECommandHistoryStore.update(receipt, in: commandHistory)
        BLECommandHistoryStore.save(commandHistory)
    }

    private func requestCommandNonce() {
        guard pendingCommand != nil, let commandChar else { return }
        waitingForCommandTime = false
        waitingForCommandNonce = true
        lastEvent = "Araçtan tek kullanımlık komut sorusu isteniyor"
        advanceCommandReceipt(.queued, detail: lastEvent)
        print("[BLE] command nonce request 1300000001000000")
        enqueue(BLEProtocol.commandNonce, to: commandChar)
        recordDiagnostic("nonce_requested · tek kullanımlık komut sorusu")
        armCommandTimeout(8, "Araç tek kullanımlık komut sorusu göndermedi.")
    }

    private func sendSignedCommand(nonce: Data) {
        guard let pendingCommand, let commandChar, let phoneKey,
              let carTimeAtRead, let carTimeReadAt else {
            finishPendingCommand(error: "İmzalı komut hazırlanamadı.")
            return
        }
        do {
            let commandTime = carTimeAtRead.addingTimeInterval(Date().timeIntervalSince(carTimeReadAt))
            let body = try BLEProtocol.commandBody(
                code: pendingCommand.code,
                date: commandTime,
                challenge: nonce
            )
            let signature = try PhoneKeyStore.sign(body, with: phoneKey)
            let packet = try BLEProtocol.commandPacket(
                code: pendingCommand.code,
                date: commandTime,
                challenge: nonce,
                signature: signature
            )
            print("[BLE] signed command action=\(pendingCommand.action) code=\(pendingCommand.code) len=\(packet.count)")
            recordDiagnostic("nonce_packet_prepared · imzalı komut gönderildi: \(pendingCommand.action)")
            lastEvent = "İmzalı \(pendingCommand.action.lowercased()) komutu gönderiliyor"
            advanceCommandReceipt(.sent, detail: "Araç yanıtı bekleniyor.")
            enqueue(packet, to: commandChar)
            armCommandTimeout(8, "Araç komut yanıtı göndermedi.")
        } catch {
            finishPendingCommand(error: "Komut imzalanamadı: \(error.localizedDescription)")
        }
    }

    private func armCommandTimeout(_ seconds: Double, _ message: String) {
        commandTimeoutTask?.cancel()
        commandTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                guard self.pendingCommand != nil else { return }
                self.finishPendingCommand(error: message)
            }
        }
    }

    private func finishPendingCommand(error: String) {
        let hadPendingCommand = pendingCommand != nil
        if pendingCommand?.code == 7 { lockAfterWindowsClose = false }
        commandTimeoutTask?.cancel()
        commandTimeoutTask = nil
        pendingCommand = nil
        pendingCommandNonce = nil
        waitingForCommandTime = false
        waitingForCommandNonce = false
        lastEvent = error
        if hadPendingCommand {
            advanceCommandReceipt(.failed, detail: error)
        }
        recordDiagnostic("protocol_response_timeout · \(error)")
    }

    private func acceptCommandAck() {
        commandTimeoutTask?.cancel()
        commandTimeoutTask = nil
        waitingForCommandTime = false
        waitingForCommandNonce = false
        pendingCommandNonce = nil
        guard let command = pendingCommand else {
            lastEvent = "Araç komut paketini onayladı; fiziksel durum ayrıca doğrulanmalı."
            recordDiagnostic("Araç komut onayı geldi; bekleyen komut yok")
            return
        }
        pendingCommand = nil
        recordDiagnostic("command_ack · \(command.action)")
        if command.code == 7, lockAfterWindowsClose {
            lockAfterWindowsClose = false
            lastEvent = "Cam kapatma komutu alındı; cam konumu doğrulanmıyor. Kapılar kilitleniyor."
            advanceCommandReceipt(.acknowledged, detail: "Cam kapatma alındı; kapı kilidi başlatılıyor.")
            recordDiagnostic("Cam kapatma komutu onaylandı; konum bilinmiyor, kilitleme başlatılıyor")
            if !sendCommand(code: 1, action: "Kilitle") {
                lastEvent = "Cam kapatma komutu alındı ancak kapı kilitleme komutu gönderilemedi."
            }
            return
        }

        let targetLocked: Bool? = command.code == 1 ? true : (command.code == 2 ? false : nil)
        guard let targetLocked else {
            if command.code == 6 || command.code == 7 {
                lastEvent = "\(command.action) komutu araç tarafından alındı; cam konumu ayrıca doğrulanmalı."
                advanceCommandReceipt(.acknowledged, detail: "Cam konumu ayrıca doğrulanmalı.")
            } else {
                lastEvent = "\(command.action) komutu araç tarafından alındı."
                advanceCommandReceipt(.acknowledged, detail: "Araç komutu aldı.")
            }
            return
        }
        if let telemetry,
           Date().timeIntervalSince(telemetry.receivedAt) < 15,
           telemetry.isLocked == targetLocked {
            if targetLocked {
                lockConfirmationCount += 1
                print("[BLE] lock state confirmed by fresh signed telemetry")
                recordDiagnostic("Kilitli durum taze imzalı telemetriyle doğrulandı")
            }
            lastEvent = "Araç komutu onayladı; kilit durumu hedef değerle eşleşiyor."
            advanceCommandReceipt(.verified, detail: "Kilit durumu telemetriyle doğrulandı.")
            return
        }
        pendingLockVerification = targetLocked
        lastEvent = "Araç komutu aldı; kilit durumu değişikliği doğrulanıyor…"
        advanceCommandReceipt(.acknowledged, detail: "Kilit durumu doğrulanıyor…")
        commandVerificationTask?.cancel()
        commandVerificationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                guard self.pendingLockVerification == targetLocked else { return }
                self.pendingLockVerification = nil
                self.commandVerificationTask = nil
                self.lastEvent = "Araç komutu onayladı ancak kilit değişikliği doğrulanamadı."
                self.advanceCommandReceipt(.failed, detail: "Kilit değişikliği doğrulanamadı.")
                self.recordDiagnostic("automatic_command_failed · kilit durumu komut sonrasında doğrulanamadı")
            }
        }
    }

    // MARK: - Yazma kuyruğu

    private func enqueue(_ data: Data, to characteristic: CBCharacteristic) {
        writeQueue.append(PendingWrite(data: data, characteristic: characteristic))
        pump()
    }

    private func pump() {
        guard !writing, !writeQueue.isEmpty,
              let peripheral, peripheral.state == .connected else { return }
        let item = writeQueue.removeFirst()
        writing = true
        let type: CBCharacteristicWriteType = item.characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        if type == .withoutResponse {
            print("[BLE] warning: \(item.characteristic.uuid.uuidString) has no write-with-response")
        }
        lastWrittenLength = item.data.count
        peripheral.writeValue(item.data, for: item.characteristic, type: type)
        if type == .withoutResponse {
            writing = false
            if !writeQueue.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.pump() }
            }
        }
    }

    /// Araç sertifika çerçevelerini işlesin diye kısa bir bekleme bırakır.
    private func scheduleChallengeRequest() {
        guard !challengeRequestSent else { return }
        challengeDelayTask?.cancel()
        challengeDelayTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            await MainActor.run { self.sendChallengeRequest() }
        }
    }

    private func sendChallengeRequest() {
        guard !challengeRequestSent, let commandChar else { return }
        challengeRequestSent = true
        state = .challenge
        lastEvent = "Araç kimlik doğrulama sorusu isteniyor"
        var packet = BLEProtocol.challengeRequest
        if vehicleKeyFrameLength == 72 || vehicleKeyFrameLength == 73 {
            packet[2] = UInt8(vehicleKeyFrameLength - 8)
        }
        print("[BLE] challenge request len=\(packet[2])")
        enqueue(packet, to: commandChar)
        armTimeout(8, .handshakeTimeout("Araç kimlik doğrulama sorusu göndermedi."))
    }

    /// Android ile aynı ad eşleşmesi: "MY T-SAS <VIN>", "<son 8>" veya "<son 6>".
    private func matchesTarget(_ rawName: String) -> Bool {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard name.hasPrefix("MY T-SAS") else { return false }
        guard !targetVIN.isEmpty else { return true }
        let vin = targetVIN.uppercased()
        let candidates = [vin, String(vin.suffix(8)), String(vin.suffix(6))]
        return candidates.contains { name == "MY T-SAS \($0)" }
    }

    /// Taramayı evreli yürütür: ilk evre normal tarama, sonuçsuz kalırsa ikinci
    /// evre ısrarlı (yinelenen reklamlı) tarama. Android 1.0.24.42'nin
    /// "PI → normal devir" davranışının iOS karşılığı; tek seferlik taramanın
    /// kaçırdığı reklamı ikinci evre yakalar.
    private func beginScanPhase(_ index: Int) {
        guard transport.isRadioOn else { return }
        cancelScanTimeout()
        let phase = BleScanPolicy.phases[index]
        transport.stopScan()
        recordDiagnostic("gatt_scan_start · \(phase.name) tarama \(Int(phase.seconds)) sn")
        // Android ile aynı: servis filtresi kullanılmaz. Araç reklamında
        // f0002412 görünmediğinde filtreli tarama cihazı hiç bulamıyor.
        transport.startScan(allowDuplicates: phase.allowDuplicates)
        scanTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(phase.seconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                guard self.wantsScan, !self.state.isReady, self.state.isConnecting else { return }
                if index + 1 < BleScanPolicy.phases.count {
                    let next = BleScanPolicy.phases[index + 1]
                    self.recordDiagnostic("scan_rotate · \(phase.name) tarama sonuçsuz; \(next.name) taramaya geçildi")
                    self.beginScanPhase(index + 1)
                    return
                }
                self.transport.stopScan()
                self.wantsScan = false
                self.state = .failed(.vehicleNotFound)
                self.failureSummary = "Araç bulunamadı · araç yakında mı?"
                self.lastEvent = "Araç bulunamadı. Araç ve iPhone Bluetooth'unun açık olduğundan, aracın yakınında olduğundan emin olup yeniden dene."
                self.recordDiagnostic("scan_exhausted · iki evre de sonuçsuz")
            }
        }
    }

    /// Radyo kullanılabilir mi? (Bluetooth kapalıyken yeniden bağlanma
    /// denemeleri deneme sayacını tüketmemeli.)
    var isRadioAvailable: Bool { transport.isRadioOn }

    private func noteFailure(_ kind: BleFailureKind) {
        let count = failureCounter.record(kind)
        failureSummary = count >= 3
            ? "\(kind.summary) · son 1 dk'da \(count) kopma"
            : kind.summary
        recordDiagnostic("failure_kind · \(kind.detail)")
    }

    private func cancelScanTimeout() {
        scanTimeoutTask?.cancel()
        scanTimeoutTask = nil
    }

    /// Doğrudan (taramasız) bağlanma denemesi yanıt vermezse temiz bir hata üretir;
    /// bir sonraki deneme taramaya döner.
    private func armConnectWatchdog() {
        cancelScanTimeout()
        scanTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                guard self.state.isConnecting else { return }
                self.lastPeripheral = nil
                self.lastPeripheralVIN = ""
                self.state = .failed(.connectionTimeout)
                self.lastEvent = "Araç bağlantısı kurulamadı; yeniden taranacak"
                self.recordDiagnostic("gatt_timeout_connect · doğrudan bağlanma zaman aşımı")
            }
        }
    }

    /// Kopma nedenini kullanıcıya anlaşılır biçimde eşler.
    /// Kod 6 = bağlantı zaman aşımı: sinyal çok zayıf ya da araç yanıt vermiyor.
    private static func disconnectReason(_ error: Error?) -> String {
        guard let error = error as NSError? else { return "bağlantı kapatıldı" }
        guard error.domain == CBErrorDomain else { return "\(error.domain) \(error.code)" }
        switch error.code {
        case CBError.Code.connectionTimeout.rawValue:
            return "bağlantı zaman aşımı (sinyal zayıf veya araç yanıt vermiyor)"
        case CBError.Code.peripheralDisconnected.rawValue:
            return "araç bağlantıyı kapattı"
        case CBError.Code.connectionLimitReached.rawValue:
            return "bağlantı sınırına ulaşıldı"
        case CBError.Code.encryptionTimedOut.rawValue:
            return "şifreli bağlantı zaman aşımı"
        default:
            return "CBError \(error.code)"
        }
    }

    /// Araç sistemdeki eşleşme bilgisini sildiğinde iOS yeni bağlantıyı şifreleyemez.
    /// Sistem eşleşmesi uygulama tarafından silinemediği için kullanıcıya net adımlar gösterilir.
    private func pairingGuidance(_ error: Error?) -> String? {
        guard let error = error as NSError? else { return nil }
        if error.domain == CBErrorDomain,
           error.code == CBError.Code.peerRemovedPairingInformation.rawValue {
            return "Araç eşleşme bilgisini sildi. iPhone'da Ayarlar > Bluetooth'tan aracı unut, araç ekranından telefonu kaldır, iki cihazı yeniden başlat ve uygulamadan tekrar bağlan."
        }
        if error.domain == CBATTErrorDomain,
           error.code == CBATTError.Code.insufficientAuthentication.rawValue {
            return "Araç kimlik doğrulaması istedi ancak eşleşme geçersiz. Aracı iPhone'dan unutup yeniden eşleştir."
        }
        if error.domain == CBErrorDomain,
           error.code == CBError.Code.encryptionTimedOut.rawValue {
            return "Araçla şifreli bağlantı kurulamadı. iPhone'da Ayarlar > Bluetooth'tan aracı unut, araç ekranından telefonu kaldır, iki cihazı yeniden başlat ve uygulamadan tekrar bağlan."
        }
        return nil
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard peripheral === self.peripheral else { return }
        guard error == nil, let services = peripheral.services else {
            print("[BLE] service discovery error: \(String(describing: error))")
            noteFailure(.serviceDiscovery)
            state = .failed(.serviceDiscoveryFailed)
            lastEvent = "Araç servisleri bulunamadı; yeniden denenecek"
            return
        }
        print("[BLE] services: \(services.map { $0.uuid.uuidString })")
        discoveryPending = Set(services.map(\.uuid))
        for service in services {
            if service.uuid == serviceUUID {
                peripheral.discoverCharacteristics([commandUUID, telemetryUUID], for: service)
            } else if service.uuid == timeServiceUUID {
                peripheral.discoverCharacteristics([timeUUID], for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard peripheral === self.peripheral else { return }
        guard error == nil else {
            print("[BLE] characteristic discovery error: \(String(describing: error))")
            state = .failed(.characteristicDiscoveryFailed); return
        }
        for char in service.characteristics ?? [] {
            print("[BLE] char \(char.uuid.uuidString) \(characteristicCaps(char))")
            switch char.uuid {
            case commandUUID: commandChar = char
            case telemetryUUID: telemetryChar = char
            case timeUUID: timeChar = char
            default: break
            }
            channels.append("\(char.uuid.uuidString.prefix(8)): \(characteristicCaps(char).joined(separator: ", "))")
        }
        discoveryPending.remove(service.uuid)
        guard discoveryPending.isEmpty else { return }

        let maxWrite = peripheral.maximumWriteValueLength(for: .withResponse)
        print("[BLE] max write withResponse=\(maxWrite)B withoutResponse=\(peripheral.maximumWriteValueLength(for: .withoutResponse))B")
        if maxWrite < 247 {
            print("[BLE] warning: MTU write limit \(maxWrite)B < certificate frame 247B")
        }
        if let commandChar, commandChar.properties.contains(.notify) {
            peripheral.setNotifyValue(true, for: commandChar)
        }
        if let telemetryChar, telemetryChar.properties.contains(.notify) {
            peripheral.setNotifyValue(true, for: telemetryChar)
        }
        if let timeChar, timeChar.properties.contains(.read) {
            peripheral.readValue(for: timeChar)
        }
        startRSSI()
        state = .certificate
        lastEvent = "Kanallar hazır; dijital anahtar bekleniyor"
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral else { return }
        writing = false
        if let error {
            print("[BLE] write error \(characteristic.uuid.uuidString) len=\(lastWrittenLength) \(error)")
            if let guidance = pairingGuidance(error) {
                needsRepair = true
                state = .failed(.pairingLost)
                lastEvent = guidance
                return
            }
            lastEvent = "Yazma hatası: \(error.localizedDescription)"
            state = .failed(.writeFailed)
            return
        }
        print("[BLE] wrote \(lastWrittenLength)B \(characteristic.uuid.uuidString)")
        pump()
        if writeQueue.isEmpty {
            markCertificateWritesFinished()
            if certificateFrame2AckReceived, !waitingForVehicleKey {
                if trustedCarKey == nil {
                    requestVehicleKey()
                } else if !challengeRequestSent {
                    sendChallengeRequest()
                }
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard peripheral === self.peripheral, error == nil, let data = characteristic.value else { return }
        if characteristic.uuid == timeUUID {
            if let time = BLEProtocol.carTime(data) {
                carTimeAtRead = time
                carTimeReadAt = Date()
                print("[BLE] vehicle time refreshed")
                if waitingForCommandTime { requestCommandNonce() }
            } else if waitingForCommandTime {
                finishPendingCommand(error: "Araç saati okunamadı; komut gönderilmedi.")
            }
            return
        }
        handleIncoming(data)
    }

    func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        guard peripheral === self.peripheral, error == nil else { return }
        rssiUpdatedAt = Date()
        rssi = RSSI.intValue
        print("[BLE] connected RSSI=\(RSSI.intValue) dBm")
        let now = Date()
        let changedMeaningfully = lastRSSIDiagnosticValue.map { abs($0 - RSSI.intValue) >= 5 } ?? true
        let intervalElapsed = lastRSSIDiagnosticAt.map { now.timeIntervalSince($0) >= 30 } ?? true
        if changedMeaningfully || intervalElapsed {
            lastRSSIDiagnosticAt = now
            lastRSSIDiagnosticValue = RSSI.intValue
            recordDiagnostic("Bağlı RSSI: \(RSSI.intValue) dBm")
        }
    }

    // MARK: - Gelen paketler

    private func handleIncoming(_ data: Data) {
        print("[BLE] rx \(data.count)B")
        if data == BLEProtocol.vehicleKeyRequest {
            if certificateFrames.isEmpty, !waitingForInitialKeyRequest {
                initialKeyRequestSeen = true
                print("[BLE] certificate request buffered until authentication")
                return
            }
            if waitingForInitialKeyRequest {
                print("[BLE] initial certificate request received")
                startCertificateFrames()
            } else if certificateFrameIndex >= certificateFrames.count {
                if !certificateWritesFinished {
                    keyRequestPending = true
                    print("[BLE] vehicle key request pending until certificate writes finish")
                } else if !certificateFrame2AckReceived {
                    print("[BLE] vehicle key request early; waiting for frame 2 ack")
                } else {
                    if waitingForVehicleKey {
                        print("[BLE] vehicle repeated key request; waiting for key response")
                        lastEvent = "Araç anahtar yanıtı bekleniyor; ilk eşleştirme gereksinimini kontrol edin"
                    } else {
                        print("[BLE] vehicle requests key after certificate acks")
                        requestVehicleKey()
                    }
                }
            } else {
                initialKeyRequestSeen = true
                print("[BLE] certificate request buffered until authentication")
            }
            return
        }
        if BLEProtocol.isVehicleKeyFrame(data) {
            acceptVehicleKey(data)
            return
        }
        if data.starts(with: BLEProtocol.certificateAck) {
            lastEvent = "Araç sertifika çerçevesini kabul etti"
            print("[BLE] certificate frame 1 ack")
            recordDiagnostic("cert_frame1_ack · sertifika çerçevesi 1 onaylandı")
            frameTwoFallbackTask?.cancel()
            frameTwoFallbackTask = nil
            if certificateFrameIndex < certificateFrames.count {
                sendNextCertificateFrame()
            }
            return
        }
        if data == BLEProtocol.certificateFrame2Ack {
            lastEvent = "Araç sertifikayı kabul etti"
            print("[BLE] certificate frame 2 ack")
            recordDiagnostic("cert_frame2_ack · sertifika çerçevesi 2 onaylandı")
            frameTwoFallbackTask?.cancel()
            frameTwoFallbackTask = nil
            certificateFrame2AckReceived = true
            if certificateWritesFinished {
                if trustedCarKey == nil {
                    requestVehicleKey()
                } else {
                    challengeDelayTask?.cancel()
                    sendChallengeRequest()
                }
            }
            return
        }
        if BLEProtocol.isChallenge(data) {
            if waitingForCommandNonce {
                do {
                    pendingCommandNonce = try BLEProtocol.challenge(data)
                    waitingForCommandNonce = false
                    print("[BLE] one-time command nonce received")
                    recordDiagnostic("Araç tek kullanımlık komut sorusu gönderdi")
                    sendSignedCommand(nonce: pendingCommandNonce!)
                } catch {
                    finishPendingCommand(error: "Araçtan geçerli komut sorusu gelmedi.")
                }
            } else {
                acceptChallenge(data)
            }
            return
        }
        if BLEProtocol.isPhoneAck(data) {
            acceptPhoneAck()
            return
        }
        if data.starts(with: BLEProtocol.carProofHeader) {
            acceptCarProof(data)
            return
        }
        if BLEProtocol.isReady(data) {
            disarmTimeout()
            failureSummary = nil
            failureCounter.reset()
            state = .ready
            lastEvent = "Araç kimliği doğrulandı; komutlar hazır"
            recordDiagnostic("Araç kimliği doğrulandı; komut kanalı hazır")
            return
        }
        if BLEProtocol.isCommandAck(data) {
            acceptCommandAck()
            return
        }
        if data.count == 93, data.first == 0x26 {
            acceptTelemetry(data)
            return
        }
        if data.count >= 8 {
            lastEvent = "Bilinmeyen araç paketi (\(data.count) byte)"
        }
    }

    private func acceptVehicleKey(_ packet: Data) {
        do {
            let key = try BLEProtocol.vehicleKeyFrame(packet)
            if let expectedCarKey, expectedCarKey != key.x963Representation {
                state = .failed(.vehicleKeyMismatch)
                lastEvent = state.description
                return
            }
            trustedCarKey = key
            vehicleKeyFrameLength = packet.count
            carPublicKeyHex = key.x963Representation.hexString
            CertificateCache.updateCarKey(
                vin: vin,
                phonePublicKeyHex: phonePublicKeyHex,
                carKey: carPublicKeyHex
            )
            waitingForVehicleKey = false
            pairingRequired = false
            lastEvent = "Araç doğrulama anahtarı alındı"
            if certificateWritesFinished { scheduleChallengeRequest() }
        } catch {
            lastEvent = "Araç anahtar paketi geçersiz"
        }
    }

    private func acceptChallenge(_ packet: Data) {
        do {
            let challenge = try BLEProtocol.challenge(packet)
            currentChallenge = challenge
            guard let phoneKey else {
                state = .failed(.phoneKeyMissing)
                return
            }
            let signature = try PhoneKeyStore.sign(challenge, with: phoneKey)
            let proof = try BLEProtocol.phoneProofPacket(challenge: challenge, signature: signature)
            state = .authenticated
            lastEvent = "Kimlik doğrulama sorusu imzalanıyor"
            waitingForPhoneAck = true
            if let commandChar { enqueue(proof, to: commandChar) }
            armTimeout(8, .handshakeTimeout("Araç telefon imzasını yanıtlamadı."))
        } catch {
            disarmTimeout()
            state = .failed(.authenticationFailed(error.localizedDescription))
            lastEvent = state.description
        }
    }

    private func acceptPhoneAck() {
        guard waitingForPhoneAck else { return }
        waitingForPhoneAck = false
        lastEvent = "Telefon imzası kabul edildi; araç imzası isteniyor"
        var nonce = Data(count: 10)
        let result = nonce.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, 10, buffer.baseAddress!)
        }
        guard result == errSecSuccess else {
            disarmTimeout()
            state = .failed(.secureRandomFailed)
            return
        }
        phoneNonce = nonce
        waitingForCarProof = true
        if let commandChar {
            enqueue(BLEProtocol.challengeHeader + nonce, to: commandChar)
            enqueue(BLEProtocol.carProofRequest, to: commandChar)
        }
        armTimeout(8, .handshakeTimeout("Araç doğrulama kanıtı göndermedi."))
    }

    private func acceptCarProof(_ packet: Data) {
        guard waitingForCarProof, let nonce = phoneNonce, let trustedCarKey else {
            state = .failed(.carProofUnavailable)
            return
        }
        do {
            try BLEProtocol.verifyCarProof(packet, expectedChallenge: nonce, trustedKey: trustedCarKey)
            if let commandChar { enqueue(BLEProtocol.ready, to: commandChar) }
            disarmTimeout()
            failureSummary = nil
            failureCounter.reset()
            state = .ready
            lastEvent = "Araç kimliği doğrulandı; komutlar hazır"
        } catch {
            disarmTimeout()
            state = .failed(.carProofInvalid)
            lastEvent = state.description
        }
    }

    private func acceptTelemetry(_ packet: Data) {
        guard let trustedCarKey else { return }
        guard let payload = try? BLEProtocol.verifiedTelemetryPayload(packet, trustedKey: trustedCarKey) else {
            lastEvent = "Araç durum paketi doğrulanamadı"
            recordDiagnostic("telemetry_verify_failed · imza/biçim doğrulaması başarısız")
            return
        }
        let b = [UInt8](payload)
        guard b.count >= 16 else { return }
        let updatedTelemetry = BleTelemetry(
            locked: Int(b[2]), doors: [Int(b[3]), Int(b[4]), Int(b[5]), Int(b[6])],
            trunkAjar: Int(b[7]), powerState: Int(b[14]), counter: Int(b[15]),
            receivedAt: Date()
        )
        telemetry = updatedTelemetry
        // Arka planda zamanlayıcı çalışmaz; telemetri bildirimiyle uyanınca
        // RSSI örneğini burada alıyoruz (yakınlık algısı buna dayanır).
        peripheral?.readRSSI()
        let summary = "lock=\(updatedTelemetry.lockText) doors=\(updatedTelemetry.doors) trunk=\(updatedTelemetry.trunkAjar) power=\(updatedTelemetry.powerStateText)"
        if summary != lastLoggedTelemetrySummary {
            lastLoggedTelemetrySummary = summary
            print("[BLE] verified telemetry \(summary)")
            recordDiagnostic("İmzalı araç durumu: \(summary)")
        }
        if let target = pendingLockVerification, updatedTelemetry.isLocked == target {
            pendingLockVerification = nil
            commandVerificationTask?.cancel()
            commandVerificationTask = nil
            if target {
                lockConfirmationCount += 1
                print("[BLE] lock state confirmed by fresh signed telemetry")
            }
            lastEvent = target ? "Kapılar kilitli; araç durumuyla doğrulandı." : "Kapı kilitleri açık; araç durumuyla doğrulandı."
            advanceCommandReceipt(.verified, detail: target ? "Kilitli durum doğrulandı." : "Açık durum doğrulandı.")
            recordDiagnostic("lock_verified · kilit durumu imzalı telemetriyle doğrulandı: \(target ? "kilitli" : "açık")")
        }
    }

    // MARK: - Yardımcılar

    private func normalizedCarKey(_ text: String) -> Data? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let hex = trimmed.lowercased().hasPrefix("0x") ? String(trimmed.dropFirst(2)) : trimmed
        if let raw = Data(hexBytes: hex) {
            return PhoneKeyStore.normalizedPublicKey(raw)
        }
        if let raw = Data(base64Encoded: trimmed) {
            return PhoneKeyStore.normalizedPublicKey(raw)
        }
        return nil
    }

    // MARK: - Zaman aşımı ve sinyal

    private func armTimeout(_ seconds: Double, _ issue: BLEIssue) {
        disarmTimeout()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                guard !self.state.isReady else { return }
                self.state = .failed(issue)
                self.lastEvent = issue.message
            }
        }
    }

    private func disarmTimeout() {
        timeoutTask?.cancel()
        timeoutTask = nil
    }

    private func startRSSI() {
        stopRSSI()
        peripheral?.readRSSI()
        rssiTimer = Timer.scheduledTimer(withTimeInterval: rssiPollingInterval, repeats: true) { [weak self] _ in
            guard let self, let peripheral = self.peripheral, peripheral.state == .connected else { return }
            peripheral.readRSSI()
        }
    }

    func setProximityRSSIPollInterval(_ interval: TimeInterval?) {
        let updated = interval ?? 6
        guard updated != rssiPollingInterval else { return }
        rssiPollingInterval = updated
        if peripheral?.state == .connected { startRSSI() }
    }

    private func stopRSSI() {
        rssiTimer?.invalidate()
        rssiTimer = nil
    }

    private func characteristicCaps(_ char: CBCharacteristic) -> [String] {
        var out: [String] = []
        if char.properties.contains(.read) { out.append("read") }
        if char.properties.contains(.write) { out.append("write") }
        if char.properties.contains(.writeWithoutResponse) { out.append("writeNoResponse") }
        if char.properties.contains(.notify) { out.append("notify") }
        if char.properties.contains(.indicate) { out.append("indicate") }
        return out
    }
}

extension BleConnection: BLETransportDelegate {
    func transportDidUpdateState(_ managerState: CBManagerState) {
        bleLog("merkezi bluetooth durumu=\(managerState.rawValue)")
        switch managerState {
        case .poweredOn:
            lastEvent = "Bluetooth hazır"
            if radioWasPoweredOff {
                // Android 1.0.24.42 "Bluetooth radyo değişimi / STATE_ON":
                // eski çevrebirim tanıtıcıları geçersiz, tarama sıfırdan kurulur.
                radioWasPoweredOff = false
                lastPeripheral = nil
                lastPeripheralVIN = ""
                recordDiagnostic("radio_on · Bluetooth yeniden açıldı; tarama sıfırlandı")
                if shouldStayConnected {
                    recordDiagnostic("radio_on_reconnect · bağlantı yeniden kurulacak")
                    start()
                    return
                }
            }
            if wantsScan { start() }
        case .poweredOff:
            lastEvent = "Bluetooth kapalı — açılınca yeniden bağlanacak"
            radioWasPoweredOff = true
            wantsScan = false
            cancelScanTimeout()
            self.transport.stopScan()
            state = .failed(.radioOff)
            noteFailure(.radioOff)
        case .unauthorized:
            lastEvent = "Bluetooth izni yok"
            state = .failed(.bluetoothUnauthorized)
            noteFailure(.radioOff)
        default:
            break
        }
    }

    func transportDidRestore(peripheral: CBPeripheral, count: Int) {
        lastPeripheral = peripheral
        lastPeripheralVIN = targetVIN
        print("[BLE] state restored peripherals=\(count)")
        recordDiagnostic("gatt_restore · BLE durumu geri yüklendi (\(count) çevrebirim)")
    }

    func transportDidDiscover(peripheral: CBPeripheral, name: String, rssi: Int) {
        guard wantsScan || state.isConnecting else { return }
        guard matchesTarget(name) else { return }
        print("[BLE] found \(name) rssi=\(rssi) id=\(peripheral.identifier)")
        recordDiagnostic("Araç bulundu; RSSI \(rssi) dBm")
        failureSummary = nil
        lastEvent = "Araç bulundu: \(name) (\(rssi))"
        self.transport.stopScan()
        connect(to: peripheral)
    }

    func transportDidConnect(peripheral: CBPeripheral) {
        guard peripheral === self.peripheral else { return }
        connectedAt = Date()
        lastPeripheral = peripheral
        lastPeripheralVIN = targetVIN
        state = .discovering
        lastEvent = "Bağlandı, servisler keşfediliyor"
        print("[BLE] connected; discovering services")
        recordDiagnostic("BLE bağlantısı kuruldu; servisler keşfediliyor")
        peripheral.discoverServices([serviceUUID, timeServiceUUID])
    }

    func transportDidFailToConnect(peripheral: CBPeripheral, error: Error?) {
        guard peripheral === self.peripheral else { return }
        if lastPeripheral === peripheral {
            lastPeripheral = nil
            lastPeripheralVIN = ""
        }
        if let error = error as NSError? {
            print("[BLE] connect failed \(error.domain) code=\(error.code) \(error.localizedDescription)")
        }
        if let guidance = pairingGuidance(error) {
            needsRepair = true
            noteFailure(.pairingLost)
            state = .failed(.pairingLost)
            lastEvent = guidance
            return
        }
        noteFailure(BleFailureClassifier.classify(error))
        state = .failed(.connectionFailed(error?.localizedDescription ?? "bilinmiyor"))
        lastEvent = state.description
    }

    func transportDidDisconnect(peripheral: CBPeripheral, error: Error?) {
        guard peripheral === self.peripheral else { return }
        let elapsed = connectedAt.map { Date().timeIntervalSince($0) } ?? 0
        connectedAt = nil
        let reason = Self.disconnectReason(error)
        if let error = error as NSError? {
            print("[BLE] disconnected \(error.domain) code=\(error.code) \(error.localizedDescription)")
        }
        recordDiagnostic("BLEDisconnected · \(reason); süre \(Int(elapsed.rounded())) sn, son RSSI \(rssi.map { "\($0) dBm" } ?? "—")")
        noteFailure(BleFailureClassifier.classify(error))
        stop(keepTelemetry: true)
        if let guidance = pairingGuidance(error) {
            needsRepair = true
            state = .failed(.pairingLost)
            lastEvent = guidance
            return
        }
        lastEvent = "Araç bağlantısı kesildi (\(reason))"
    }
}

extension BleConnection.State {
    var isDisconnected: Bool { if case .disconnected = self { return true }; return false }
    var isConnecting: Bool { if case .connecting = self { return true }; return false }
    var isCertificate: Bool { if case .certificate = self { return true }; return false }
    var isChallenge: Bool { if case .challenge = self { return true }; return false }
    var isReady: Bool { if case .ready = self { return true }; return false }
    var isFailed: Bool { if case .failed = self { return true }; return false }

    var description: String {
        switch self {
        case .disconnected: return "Bağlı değil"
        case .connecting: return "Bağlanıyor"
        case .discovering: return "Servisler keşfediliyor"
        case .certificate: return "Sertifika akışı"
        case .challenge: return "Kimlik doğrulama sorusu"
        case .authenticated: return "Kimlik doğrulanıyor"
        case .ready: return "Komut hazır"
        case .failed(let issue): return "Hata: \(issue.message)"
        }
    }
}
