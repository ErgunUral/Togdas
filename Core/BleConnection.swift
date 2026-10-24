import CoreBluetooth
import CryptoKit
import Foundation
import Security

private func bleLog(_ message: String) {
    NSLog("[ToqdasBLE] %@", message)
}

struct BLEDiagnosticEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let message: String
}

private enum BLEDiagnosticStore {
    private static let key = "toqdas.ble.diagnostics.v1"
    private static let limit = 200

    static func load() -> [BLEDiagnosticEvent] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let events = try? JSONDecoder().decode([BLEDiagnosticEvent].self, from: data) else { return [] }
        return Array(events.suffix(limit))
    }

    static func save(_ events: [BLEDiagnosticEvent]) {
        guard let data = try? JSONEncoder().encode(Array(events.suffix(limit))) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

struct BleTelemetry: Equatable {
    let locked: Int
    let doors: [Int]
    let trunkAjar: Int
    let powerState: Int
    let counter: Int
    let receivedAt: Date

    /// Resmî web uygulamasındaki eşleme: 1 kilitli, 2 kilit açık.
    var isLocked: Bool? {
        switch locked {
        case 1: return true
        case 2: return false
        default: return nil
        }
    }

    var lockText: String {
        switch isLocked {
        case true: return "Kilitli"
        case false: return "Kilit açık"
        case nil: return "Kilit durumu doğrulanıyor"
        }
    }

    var hasDoorReadings: Bool { doors.count == 4 }

    /// door1–door4 alanları sırasıyla 1–4 olarak gösterilir. Fiziksel kapı
    /// konumları resmî uygulamada doğrulanmadığı için sol/sağ etiketi kullanılmaz.
    func isDoorOpen(_ index: Int) -> Bool? {
        guard doors.indices.contains(index) else { return nil }
        return doors[index] != 0
    }

    var openDoorCount: Int {
        doors.filter { $0 != 0 }.count
    }

    var doorsText: String {
        guard hasDoorReadings else { return "Kapı durumu doğrulanıyor" }
        let open = doors.indices.filter { doors[$0] != 0 }.map { "Kapı \($0 + 1)" }
        return open.isEmpty ? "Tüm kapılar kapalı" : open.joined(separator: ", ") + " açık"
    }

    /// Kilit/kapı/bagaj telemetrisinden türetilen güvenlik özeti.
    var securityWarning: String? {
        var openItems: [String] = []
        if hasDoorReadings, openDoorCount > 0 {
            openItems.append(doorsText)
        }
        if trunkAjar == 1 {
            openItems.append("Bagaj açık")
        }
        if !openItems.isEmpty { return openItems.joined(separator: " · ") }
        if powerState == 2, isLocked == false { return "Araç beklemede ve kilit açık" }
        return nil
    }

    /// Resmî web uygulamasındaki eşleme: 2 bekleme, 3 aksesuar, 4 hazır.
    var powerStateText: String {
        switch powerState {
        case 2: return "Bekleme"
        case 3: return "Aksesuar"
        case 4: return "Hazır"
        default: return "Durum doğrulanıyor"
        }
    }
}

/// BLE taşıma + dijital anahtar el sıkışması.
/// Paket biçimleri Garajm/BleProtocol.kt ile aynıdır. Komutlar ancak araç kimliği
/// doğrulandıktan (READY) sonra gönderilir.
final class BleConnection: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    enum State {
        case disconnected, connecting, discovering, certificate, challenge, authenticated, ready, failed(String)
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
    @Published private(set) var needsRepair = false
    @Published private(set) var lockConfirmationCount = 0
    @Published private(set) var diagnosticEvents = BLEDiagnosticStore.load()
    private var lastLoggedTelemetrySummary: String?

    private var central: CBCentralManager?
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

    private var writeQueue: [PendingWrite] = []
    private var writing = false
    private var wantsScan = false
    private var discoveryPending = Set<CBUUID>()
    private var targetVIN = ""
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

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func recordDiagnostic(_ message: String) {
        let safeMessage: String
        if !vin.isEmpty {
            safeMessage = message.replacingOccurrences(of: vin, with: "…\(vin.suffix(4))")
        } else {
            safeMessage = message
        }
        diagnosticEvents.append(BLEDiagnosticEvent(id: UUID(), timestamp: Date(), message: safeMessage))
        if diagnosticEvents.count > 200 {
            diagnosticEvents.removeFirst(diagnosticEvents.count - 200)
        }
        BLEDiagnosticStore.save(diagnosticEvents)
    }

    func clearDiagnosticEvents() {
        diagnosticEvents.removeAll()
        BLEDiagnosticStore.save([])
    }

    // MARK: - Bağlantı

    func start(vin: String? = nil) {
        if let vin, !vin.isEmpty { targetVIN = vin.uppercased() }
        wantsScan = true
        needsRepair = false
        guard let central else { return }
        switch central.state {
        case .poweredOn:
            state = .connecting
            lastEvent = "Araç aranıyor…"
            recordDiagnostic("Araç taraması başladı")
            // Android ile aynı: servis filtresi kullanılmaz. Araç reklamında
            // f0002412 görünmediğinde filtreli tarama cihazı hiç bulamıyor.
            central.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
            armScanTimeout()
        case .poweredOff, .unauthorized, .unsupported:
            lastEvent = "Bluetooth kullanılamıyor"
            state = .failed("Bluetooth kapalı veya izin yok.")
            wantsScan = false
        default:
            lastEvent = "Bluetooth hazırlanıyor…"
        }
    }

    func stop() {
        wantsScan = false
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
        if let peripheral, peripheral.state == .connected {
            central?.cancelPeripheralConnection(peripheral)
        }
        central?.stopScan()
        resetSession()
        state = .disconnected
        lastEvent = "Bağlantı durduruldu"
        channels = []
        telemetry = nil
    }

    func disconnect() { stop() }

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
    }

    func connect(to peripheral: CBPeripheral) {
        guard central?.state == .poweredOn else { return }
        wantsScan = false
        needsRepair = false
        cancelScanTimeout()
        central?.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        central?.connect(peripheral, options: nil)
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
        recordDiagnostic("Dijital anahtar sertifika sunumu başladı; sunucu araç anahtarı \(trustedCarKey == nil ? "yok" : "var")")
        print("[BLE] presenting certificate vin=\(vin) frames=\(certificateFrames.count) firstTime=\(trustedCarKey == nil) initialRequestSeen=\(initialKeyRequestSeen)")

        // Resmî akış: araç önce 1000000001000000 ile sertifika isteğini gönderir,
        // ardından iki sertifika çerçevesi sırayla yazılır ve her çerçevenin
        // onayı beklenir. Onaylar gelmeden araç anahtarı istenmez.
        if initialKeyRequestSeen {
            startCertificateFrames()
        } else {
            waitingForInitialKeyRequest = true
            armTimeout(6, "Araç sertifika isteği göndermedi.")
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
            state = .failed("Sertifika çerçevesi hazırlanamadı.")
            return
        }
        // Resmî akış: önce 1. çerçeve yazılır ve `1001ef…` onayı beklenir,
        // ardından 2. çerçeve yazılır. Bazı araç yazılımları 1. çerçeveyi
        // tek başına onaylamazsa 2 sn sonra 2. çerçeve yine de gönderilir.
        certificateFrameIndex = 0
        sendNextCertificateFrame()
        lastEvent = "Sertifika araca sunuluyor…"
        armTimeout(10, "Araç sertifikayı yanıtlamadı.")
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
        armTimeout(
            10,
            "Araç doğrulama anahtarını göndermedi. İlk kurulumda araç ekranından dijital anahtar eşleştirmesini başlatıp iPhone'da çıkan Bluetooth isteğini onaylayın."
        )
    }

    /// Sertifika yerine yalnızca aracın açık anahtarını bekler (tanılama).
    func expectVehicleKey(_ key: String) {
        expectedCarKey = normalizedCarKey(key)
        carPublicKeyHex = expectedCarKey?.hexString ?? ""
    }

    // MARK: - Komutlar

    func lock() {
        lockAfterWindowsClose = true
        if !sendCommand(code: 7, action: "Kapı kilidinden önce camları kapat") {
            lockAfterWindowsClose = false
        }
    }
    func unlock() { sendCommand(code: 2, action: "Kilidi aç") }
    func trunkOpen() { sendCommand(code: 4, action: "Bagajı aç") }
    func trunkClose() { sendCommand(code: 5, action: "Bagajı kapat") }
    func windowsOpen() { sendCommand(code: 6, action: "Yan camları aç") }
    func windowsClose() { sendCommand(code: 7, action: "Yan camları kapat") }
    func driveAuthorize() { sendCommand(code: 14, action: "Sürüş yetkilendir") }

    @discardableResult
    private func sendCommand(code: UInt8, action: String) -> Bool {
        guard state.isReady else {
            lastEvent = "Komut için önce kimlik doğrulama gerekli."
            return false
        }
        guard commandChar != nil else {
            lastEvent = "Komut kanalı yok."; return false
        }
        guard phoneKey != nil else {
            lastEvent = "Telefon imza anahtarı yok."; return false
        }
        guard pendingCommand == nil, pendingLockVerification == nil else {
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
            return false
        }
    }

    private func requestCommandNonce() {
        guard pendingCommand != nil, let commandChar else { return }
        waitingForCommandTime = false
        waitingForCommandNonce = true
        lastEvent = "Araçtan tek kullanımlık komut sorusu isteniyor"
        print("[BLE] command nonce request 1300000001000000")
        enqueue(BLEProtocol.commandNonce, to: commandChar)
        recordDiagnostic("Komut için tek kullanımlık nonce istendi")
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
            recordDiagnostic("İmzalı komut gönderildi: \(pendingCommand.action)")
            lastEvent = "İmzalı \(pendingCommand.action.lowercased()) komutu gönderiliyor"
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
        if pendingCommand?.code == 7 { lockAfterWindowsClose = false }
        commandTimeoutTask?.cancel()
        commandTimeoutTask = nil
        pendingCommand = nil
        pendingCommandNonce = nil
        waitingForCommandTime = false
        waitingForCommandNonce = false
        lastEvent = error
        recordDiagnostic("Komut sonucu: \(error)")
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
        recordDiagnostic("Araç komutu onayladı: \(command.action)")
        if command.code == 7, lockAfterWindowsClose {
            lockAfterWindowsClose = false
            lastEvent = "Cam kapatma komutu alındı; cam konumu doğrulanmıyor. Kapılar kilitleniyor."
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
            } else {
                lastEvent = "\(command.action) komutu araç tarafından alındı."
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
            return
        }
        pendingLockVerification = targetLocked
        lastEvent = "Araç komutu aldı; kilit durumu değişikliği doğrulanıyor…"
        commandVerificationTask?.cancel()
        commandVerificationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                guard self.pendingLockVerification == targetLocked else { return }
                self.pendingLockVerification = nil
                self.commandVerificationTask = nil
                self.lastEvent = "Araç komutu onayladı ancak kilit değişikliği doğrulanamadı."
                self.recordDiagnostic("Kilit durumu komut sonrasında doğrulanamadı")
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
        armTimeout(8, "Araç kimlik doğrulama sorusu göndermedi.")
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bleLog("merkezi bluetooth durumu=\(central.state.rawValue)")
        switch central.state {
        case .poweredOn:
            lastEvent = "Bluetooth hazır"
            if wantsScan { start() }
        case .poweredOff:
            lastEvent = "Bluetooth kapalı"
            state = .disconnected
        case .unauthorized:
            lastEvent = "Bluetooth izni yok"
            state = .disconnected
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard wantsScan || state.isConnecting else { return }
        let advertised = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = peripheral.name ?? advertised ?? "bilinmiyor"
        guard matchesTarget(name) else { return }
        print("[BLE] found \(name) rssi=\(RSSI) id=\(peripheral.identifier)")
        recordDiagnostic("Araç bulundu; RSSI \(RSSI) dBm")
        lastEvent = "Araç bulundu: \(name) (\(RSSI))"
        central.stopScan()
        connect(to: peripheral)
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

    private func armScanTimeout() {
        cancelScanTimeout()
        scanTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 18_000_000_000)
            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                guard self.wantsScan, !self.state.isReady else { return }
                self.central?.stopScan()
                self.wantsScan = false
                self.state = .failed("Araç bulunamadı")
                self.lastEvent = "Araç bulunamadı. Araç ve iPhone Bluetooth'unun açık olduğundan, aracın yakınında olduğundan emin olup yeniden dene."
            }
        }
    }

    private func cancelScanTimeout() {
        scanTimeoutTask?.cancel()
        scanTimeoutTask = nil
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard peripheral === self.peripheral else { return }
        state = .discovering
        lastEvent = "Bağlandı, servisler keşfediliyor"
        print("[BLE] connected; discovering services")
        recordDiagnostic("BLE bağlantısı kuruldu; servisler keşfediliyor")
        peripheral.discoverServices([serviceUUID, timeServiceUUID])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard peripheral === self.peripheral else { return }
        if let error = error as NSError? {
            print("[BLE] connect failed \(error.domain) code=\(error.code) \(error.localizedDescription)")
        }
        if let guidance = pairingGuidance(error) {
            needsRepair = true
            state = .failed("Eşleşme hatası")
            lastEvent = guidance
            return
        }
        state = .failed("Bağlantı hatası: \(error?.localizedDescription ?? "bilinmiyor")")
        lastEvent = state.description
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        guard peripheral === self.peripheral else { return }
        if let error = error as NSError? {
            print("[BLE] disconnected \(error.domain) code=\(error.code) \(error.localizedDescription)")
            recordDiagnostic("BLE bağlantısı kesildi (\(error.domain) \(error.code))")
        } else {
            recordDiagnostic("BLE bağlantısı kesildi")
        }
        stop()
        if let guidance = pairingGuidance(error) {
            needsRepair = true
            state = .failed("Eşleşme hatası")
            lastEvent = guidance
            return
        }
        lastEvent = "Araç bağlantısı kesildi"
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
            state = .failed("Servis keşif hatası"); return
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
            state = .failed("Karakteristik keşif hatası"); return
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
                state = .failed("Eşleşme hatası")
                lastEvent = guidance
                return
            }
            lastEvent = "Yazma hatası: \(error.localizedDescription)"
            state = .failed("Yazma hatası")
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
        rssi = RSSI.intValue
        print("[BLE] connected RSSI=\(RSSI.intValue) dBm")
        recordDiagnostic("Bağlı RSSI: \(RSSI.intValue) dBm")
        recordDiagnostic("RSSI: \(RSSI.intValue) dBm")
    }

    // MARK: - Gelen paketler

    private func handleIncoming(_ data: Data) {
        print("[BLE] rx \(data.count)B \(data.prefix(8).map { String(format: "%02x", $0) }.joined())")
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
            recordDiagnostic("Araç sertifika çerçevesi 1'i onayladı")
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
            recordDiagnostic("Araç sertifika çerçevesi 2'yi onayladı")
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
                state = .failed("Araç anahtarı sunucu kaydıyla eşleşmiyor")
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
                state = .failed("Telefon anahtarı yok")
                return
            }
            let signature = try PhoneKeyStore.sign(challenge, with: phoneKey)
            let proof = try BLEProtocol.phoneProofPacket(challenge: challenge, signature: signature)
            state = .authenticated
            lastEvent = "Kimlik doğrulama sorusu imzalanıyor"
            waitingForPhoneAck = true
            if let commandChar { enqueue(proof, to: commandChar) }
            armTimeout(8, "Araç telefon imzasını yanıtlamadı.")
        } catch {
            disarmTimeout()
            state = .failed("Kimlik doğrulama hatası: \(error.localizedDescription)")
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
            state = .failed("Güvenli rastgele sayı üretilemedi")
            return
        }
        phoneNonce = nonce
        waitingForCarProof = true
        if let commandChar {
            enqueue(BLEProtocol.challengeHeader + nonce, to: commandChar)
            enqueue(BLEProtocol.carProofRequest, to: commandChar)
        }
        armTimeout(8, "Araç doğrulama kanıtı göndermedi.")
    }

    private func acceptCarProof(_ packet: Data) {
        guard waitingForCarProof, let nonce = phoneNonce, let trustedCarKey else {
            state = .failed("Araç imzası için anahtar veya soru yok")
            return
        }
        do {
            try BLEProtocol.verifyCarProof(packet, expectedChallenge: nonce, trustedKey: trustedCarKey)
            if let commandChar { enqueue(BLEProtocol.ready, to: commandChar) }
            disarmTimeout()
            state = .ready
            lastEvent = "Araç kimliği doğrulandı; komutlar hazır"
        } catch {
            disarmTimeout()
            state = .failed("Araç imzası doğrulanamadı")
            lastEvent = state.description
        }
    }

    private func acceptTelemetry(_ packet: Data) {
        guard let trustedCarKey else { return }
        guard let payload = try? BLEProtocol.verifiedTelemetryPayload(packet, trustedKey: trustedCarKey) else {
            lastEvent = "Araç durum paketi doğrulanamadı"
            recordDiagnostic("Araç telemetrisi imza/biçim doğrulamasından geçmedi")
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
            recordDiagnostic("Kilit durumu imzalı telemetriyle doğrulandı: \(target ? "kilitli" : "açık")")
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

    private func armTimeout(_ seconds: Double, _ message: String) {
        disarmTimeout()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                guard !self.state.isReady else { return }
                self.state = .failed(message)
                self.lastEvent = message
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
        case .failed(let message): return "Hata: \(message)"
        }
    }
}
