import Foundation
import WatchConnectivity
import Combine

/// Saatten iPhone'a gönderilen kilit isteği. Komut kimliği, hedef araç ve son
/// kullanma zamanı taşır; iPhone tarafı süresi geçmiş isteği çalıştırmaz.
struct WatchCommandRequest: Codable {
    let id: String
    let action: String
    let vin: String
    let createdAt: TimeInterval
    let expiresAt: TimeInterval

    var isExpired: Bool { Date().timeIntervalSince1970 > expiresAt }
    var isLock: Bool { action == "lock" }
}

struct WatchCommandResult: Codable {
    let id: String
    let status: String
    let message: String
    let at: TimeInterval
}

/// Saate giden, yalnızca gösterim amaçlı araç anlık görüntüsü.
/// Token, sertifika veya özel anahtar bu kanaldan geçmez.
struct WatchSnapshot: Codable {
    let vin: String
    let vehicleName: String
    let locked: Bool?
    let doorCount: Int
    let openDoors: Int
    let trunkAjar: Bool?
    let powerState: Int?
    let ready: Bool
    let bleState: String
    let updatedAt: TimeInterval
    let telemetryAge: TimeInterval?
    /// Togg bulut telemetrisi. Sunucu döndürmediyse nil; saat 0 göstermez.
    let batteryPercent: Double?
    let rangeKM: Double?
    let outsideTemperatureC: Double?
    let auxiliaryBatteryPercent: Double?
    let odometerKM: Double?
    /// Ham sunucu değeri ("Charging" vb.); saat yalnızca "charging" eşleşmesine rozet basar.
    let chargingState: String?
    /// Panodaki yakınlık otomasyonu ayarı; saatte yalnızca durum gösterilir.
    let proximityEnabled: Bool
    /// Telefon oturumu sessizce yeniden kuruyorsa saat "yeniden bağlanıyor" der.
    let recovering: Bool?

    private enum CodingKeys: String, CodingKey {
        case vin, vehicleName, locked, doorCount, openDoors, trunkAjar, powerState
        case ready, bleState, updatedAt, telemetryAge
        case batteryPercent, rangeKM, outsideTemperatureC
        case auxiliaryBatteryPercent, odometerKM, chargingState, proximityEnabled
        case recovering
    }

    init(vin: String, vehicleName: String, locked: Bool?, doorCount: Int, openDoors: Int,
         trunkAjar: Bool?, powerState: Int?, ready: Bool, bleState: String,
         updatedAt: TimeInterval, telemetryAge: TimeInterval?,
         batteryPercent: Double?, rangeKM: Double?, outsideTemperatureC: Double?,
         auxiliaryBatteryPercent: Double? = nil, odometerKM: Double? = nil,
         chargingState: String? = nil, proximityEnabled: Bool = false,
         recovering: Bool? = nil) {
        self.vin = vin
        self.vehicleName = vehicleName
        self.locked = locked
        self.doorCount = doorCount
        self.openDoors = openDoors
        self.trunkAjar = trunkAjar
        self.powerState = powerState
        self.ready = ready
        self.bleState = bleState
        self.updatedAt = updatedAt
        self.telemetryAge = telemetryAge
        self.batteryPercent = batteryPercent
        self.rangeKM = rangeKM
        self.outsideTemperatureC = outsideTemperatureC
        self.auxiliaryBatteryPercent = auxiliaryBatteryPercent
        self.odometerKM = odometerKM
        self.chargingState = chargingState
        self.proximityEnabled = proximityEnabled
        self.recovering = recovering
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        vin = try c.decode(String.self, forKey: .vin)
        vehicleName = try c.decode(String.self, forKey: .vehicleName)
        locked = try c.decodeIfPresent(Bool.self, forKey: .locked)
        doorCount = try c.decodeIfPresent(Int.self, forKey: .doorCount) ?? 0
        openDoors = try c.decodeIfPresent(Int.self, forKey: .openDoors) ?? 0
        trunkAjar = try c.decodeIfPresent(Bool.self, forKey: .trunkAjar)
        powerState = try c.decodeIfPresent(Int.self, forKey: .powerState)
        ready = try c.decodeIfPresent(Bool.self, forKey: .ready) ?? false
        bleState = try c.decodeIfPresent(String.self, forKey: .bleState) ?? ""
        updatedAt = try c.decodeIfPresent(TimeInterval.self, forKey: .updatedAt) ?? 0
        telemetryAge = try c.decodeIfPresent(TimeInterval.self, forKey: .telemetryAge)
        batteryPercent = try c.decodeIfPresent(Double.self, forKey: .batteryPercent)
        rangeKM = try c.decodeIfPresent(Double.self, forKey: .rangeKM)
        outsideTemperatureC = try c.decodeIfPresent(Double.self, forKey: .outsideTemperatureC)
        auxiliaryBatteryPercent = try c.decodeIfPresent(Double.self, forKey: .auxiliaryBatteryPercent)
        odometerKM = try c.decodeIfPresent(Double.self, forKey: .odometerKM)
        chargingState = try c.decodeIfPresent(String.self, forKey: .chargingState)
        proximityEnabled = try c.decodeIfPresent(Bool.self, forKey: .proximityEnabled) ?? false
        recovering = try c.decodeIfPresent(Bool.self, forKey: .recovering)
    }
}

// Only display metadata and command requests cross this channel. Tokens and
// digital-key material stay off it.
final class WatchLink: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var vehicleNames: [String] = []
    @Published private(set) var updatedAt: Date?
    @Published private(set) var snapshot: WatchSnapshot?
    @Published private(set) var lastResult: WatchCommandResult?
    @Published private(set) var status = "Telefonla eşitleme bekleniyor"
    @Published private(set) var reachable = false
    @Published private(set) var installed = false

    /// iPhone tarafında ayarlanır; istek ana iş parçacığında işlenir.
    var commandHandler: ((WatchCommandRequest, @escaping (WatchCommandResult) -> Void) -> Void)?

    private var context: [String: Any] = ["schema": 1]

    private var isWatch: Bool {
        #if os(watchOS)
        return true
        #else
        return false
        #endif
    }

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - iPhone tarafı

    func publish(names: [String]) {
        context["vehicles"] = names
        context["updatedAt"] = Date().timeIntervalSince1970
        flush()
    }

    func publish(snapshot: WatchSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        context["snapshot"] = data
        flush()
    }

    private func flush() {
        guard !isWatch, WCSession.isSupported(),
              WCSession.default.activationState == .activated else { return }
        do {
            try WCSession.default.updateApplicationContext(context)
            status = "Saat için güncel veri hazır"
            print("[WATCH] context sent snapshot=\(context["snapshot"] != nil) vehicles=\((context["vehicles"] as? [String])?.count ?? 0) reachable=\(WCSession.default.isReachable)")
        } catch {
            status = "Saat eşitlemesi bekliyor"
            print("[WATCH] context send failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Saat tarafı

    /// Kilit isteğini iPhone'a iletir. Yalnızca telefon erişilebilirse gönderir;
    /// kuyruğa alınmış eski komut asla iletilmez.
    func request(_ action: String, vin: String) {
        guard WCSession.isSupported() else {
            report(WatchCommandResult(id: "", status: "unavailable",
                                      message: "Saat bağlantısı desteklenmiyor.",
                                      at: Date().timeIntervalSince1970))
            return
        }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            report(WatchCommandResult(id: "", status: "unavailable",
                                      message: "iPhone'a ulaşılamıyor. Telefonu açıp tekrar deneyin.",
                                      at: Date().timeIntervalSince1970))
            return
        }
        let now = Date().timeIntervalSince1970
        let request = WatchCommandRequest(id: UUID().uuidString, action: action, vin: vin,
                                          createdAt: now, expiresAt: now + 15)
        guard let data = try? JSONEncoder().encode(request) else { return }
        status = request.isLock ? "Kilit isteği gönderiliyor…" : "Açma isteği gönderiliyor…"
        session.sendMessage(["type": "command", "payload": data]) { [weak self] reply in
            guard let self else { return }
            let result = (reply["payload"] as? Data)
                .flatMap { try? JSONDecoder().decode(WatchCommandResult.self, from: $0) }
            DispatchQueue.main.async {
                if let result {
                    self.report(result)
                } else {
                    self.status = "Telefondan geçersiz yanıt"
                }
            }
        } errorHandler: { [weak self] error in
            DispatchQueue.main.async {
                self?.report(WatchCommandResult(id: request.id, status: "unavailable",
                                                message: "İstek iletilemedi: \(error.localizedDescription)",
                                                at: Date().timeIntervalSince1970))
            }
        }
    }

    private func report(_ result: WatchCommandResult) {
        lastResult = result
        status = result.message
    }

    // MARK: - Gelen veri

    private func accept(_ context: [String: Any]) {
        if let names = context["vehicles"] as? [String] {
            vehicleNames = names
        }
        if let stamp = context["updatedAt"] as? Double {
            updatedAt = Date(timeIntervalSince1970: stamp)
        }
        if let data = context["snapshot"] as? Data,
           let decoded = try? JSONDecoder().decode(WatchSnapshot.self, from: data) {
            snapshot = decoded
        }
        print("[WATCH] context received snapshot=\(snapshot != nil) names=\(vehicleNames.count) keys=\(context.keys.sorted())")
        if let snapshot {
            status = snapshot.ready ? "iPhone bağlı; komut hazır" : "iPhone bağlı; anahtar hazır değil"
        } else {
            status = "Telefondan alınan son araç listesi"
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        #if os(iOS)
        print("[WATCH] activation=\(activationState.rawValue) paired=\(session.isPaired) installed=\(session.isWatchAppInstalled) reachable=\(session.isReachable) error=\(error?.localizedDescription ?? "—")")
        #else
        print("[WATCH] activation=\(activationState.rawValue) companionInstalled=\(session.isCompanionAppInstalled) reachable=\(session.isReachable) error=\(error?.localizedDescription ?? "—")")
        #endif
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.reachable = session.isReachable
            #if os(iOS)
            self.installed = session.isWatchAppInstalled
            #endif
            if error != nil {
                self.status = "Saat bağlantısı kurulamadı: \(error?.localizedDescription ?? "bilinmeyen hata")"
                return
            }
            if self.isWatch {
                self.accept(session.receivedApplicationContext)
            } else {
                self.flush()
            }
        }
    }

    #if os(iOS)
    /// Saat uygulaması kurulduğunda/kaldırıldığında oturum yeniden başlatılmadan
    /// haber verilir; aksi halde `installed` uygulama açılana kadar eski kalıyordu.
    func sessionWatchStateDidChange(_ session: WCSession) {
        let isInstalled = session.isWatchAppInstalled
        print("[WATCH] watchState paired=\(session.isPaired) installed=\(isInstalled)")
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.installed = isInstalled
            self.reachable = session.isReachable
            if isInstalled {
                self.status = "Saat uygulaması kurulu; eşitleme bekleniyor"
                self.flush()
            } else {
                self.status = "Saat uygulaması saate kurulu değil"
            }
        }
    }
    #endif

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard isWatch else { return }
        DispatchQueue.main.async { [weak self] in self?.accept(applicationContext) }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in self?.reachable = session.isReachable }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        guard message["type"] as? String == "command",
              let data = message["payload"] as? Data,
              let request = try? JSONDecoder().decode(WatchCommandRequest.self, from: data) else {
            replyHandler(["type": "result", "error": "geçersiz istek"])
            return
        }
        guard !isWatch, let handler = commandHandler else {
            let result = WatchCommandResult(id: request.id, status: "unavailable",
                                            message: "Telefon tarafı hazır değil.",
                                            at: Date().timeIntervalSince1970)
            replyHandler(["type": "result", "payload": (try? JSONEncoder().encode(result)) ?? Data()])
            return
        }
        DispatchQueue.main.async {
            handler(request) { result in
                replyHandler(["type": "result", "payload": (try? JSONEncoder().encode(result)) ?? Data()])
            }
        }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
