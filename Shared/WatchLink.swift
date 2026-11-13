import Foundation
import WatchConnectivity
import Combine
import WidgetKit

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
    /// Saatten gelen "veriyi yenile" isteği; iPhone yeni snapshot yayınlar.
    var refreshHandler: (() -> Void)?

    private var context: [String: Any] = ["schema": 1]
    private enum CacheKey {
        static let snapshot = "toqdas.watch.snapshot.v1"
        static let names = "toqdas.watch.vehicleNames.v1"
        static let updatedAt = "toqdas.watch.updatedAt.v1"
    }

    private var isWatch: Bool {
        #if os(watchOS)
        return true
        #else
        return false
        #endif
    }

    override init() {
        super.init()
        loadCachedState()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Saat, iPhone erişilemezken son bilinen anlık görüntüyü gösterebilsin.
    /// Yalnızca gösterim verisi saklanır; anahtar, token veya komut kuyruğu yok.
    private func loadCachedState() {
        guard isWatch else { return }
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: CacheKey.snapshot),
           let decoded = try? JSONDecoder().decode(WatchSnapshot.self, from: data) {
            snapshot = decoded
        }
        if let names = defaults.stringArray(forKey: CacheKey.names) {
            vehicleNames = names
        }
        if let stamp = defaults.object(forKey: CacheKey.updatedAt) as? Double {
            updatedAt = Date(timeIntervalSince1970: stamp)
        }
        if snapshot != nil {
            status = "Son bilinen veri yüklendi; iPhone bekleniyor"
        }
    }

    private func cache(_ context: [String: Any]) {
        guard isWatch else { return }
        let defaults = UserDefaults.standard
        if let data = context["snapshot"] as? Data,
           let decoded = try? JSONDecoder().decode(WatchSnapshot.self, from: data) {
            defaults.set(data, forKey: CacheKey.snapshot)
            // Complication köprüsü: VIN'siz kopya app group'a yazılır
            // (entitlement yoksa sessiz no-op). Sonra zaman çizelgesi
            // tazelenir; complication yalnız gösterim verisi taşır ve
            // VIN'i hiçbir görünüm kullanmaz (iPhone widget kuralıyla
            // aynı ilke). Saat cache'i gerçek VIN'i korur (komut isteği).
            if let complicationData = try? JSONEncoder().encode(decoded.complicationCopy) {
                WatchComplicationStore.saveSnapshotData(complicationData)
            }
            WidgetCenter.shared.reloadAllTimelines()
            // Saat tanısı: veri gerçekten geldi mi? (VIN yazılmaz)
            WatchDiagnostics.log("snapshot alındı")
        }
        if let names = context["vehicles"] as? [String] {
            defaults.set(names, forKey: CacheKey.names)
        }
        if let stamp = context["updatedAt"] as? Double {
            defaults.set(stamp, forKey: CacheKey.updatedAt)
        }
    }

    private func clearCachedState() {
        guard isWatch else { return }
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: CacheKey.snapshot)
        defaults.removeObject(forKey: CacheKey.names)
        defaults.removeObject(forKey: CacheKey.updatedAt)
        // Complication eski veri göstermesin; zaman çizelgesi boş girdiyle
        // tazelenir.
        WatchComplicationStore.clear()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - iPhone tarafı

    func publish(names: [String]) {
        context["vehicles"] = names
        context["signedOut"] = names.isEmpty
        context["updatedAt"] = Date().timeIntervalSince1970
        flush()
    }

    func publish(snapshot: WatchSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        context["snapshot"] = data
        context["signedOut"] = false
        context["updatedAt"] = Date().timeIntervalSince1970
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

    /// Saatten "güncel veri gönder" isteği. Kuyruk yok: yalnızca telefon
    /// erişilebilirse gönderilir; cevap gelmezse durum metni bilgilendirir.
    func requestRefresh() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            status = "Saat bağlantısı henüz hazır değil."
            WatchDiagnostics.log("yenileme reddedildi · oturum etkin değil")
            return
        }
        guard session.isReachable else {
            status = "iPhone uykuda ya da ulaşılamıyor; veri yenilenemiyor."
            WatchDiagnostics.log("yenileme reddedildi · telefon erişilemiyor")
            return
        }
        status = "Güncel veri isteniyor…"
        WatchDiagnostics.log("yenileme istendi")
        session.sendMessage(["type": "refresh"], replyHandler: { _ in }, errorHandler: { [weak self] error in
            DispatchQueue.main.async {
                WatchDiagnostics.log("yenileme iletilemedi")
                self?.status = "Veri isteği iletilemedi: \(error.localizedDescription)"
            }
        })
    }

    private func report(_ result: WatchCommandResult) {
        lastResult = result
        status = result.message
        // Yalnız durum kodu; mesaj metni uzun olduğu için günlüğe yazılmaz.
        WatchDiagnostics.log("komut sonucu: \(result.status)")
    }

    // MARK: - Gelen veri

    private func accept(_ context: [String: Any]) {
        if context["signedOut"] as? Bool == true {
            snapshot = nil
            vehicleNames = []
            updatedAt = nil
            clearCachedState()
            status = "Telefondan çıkış yapıldı"
            return
        }
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
        cache(context)
        print("[WATCH] context received snapshot=\(snapshot != nil) names=\(vehicleNames.count) keys=\(context.keys.sorted())")
        if let snapshot {
            if reachable {
                status = snapshot.ready ? "iPhone bağlı; komut hazır" : "iPhone bağlı; anahtar hazır değil"
            } else {
                status = "Son bilinen veri; iPhone’a ulaşılamıyor"
            }
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
            if self.isWatch {
                WatchDiagnostics.log("oturum \(error == nil ? "etkin" : "hatalı") · erişilebilir=\(session.isReachable ? "evet" : "hayır")")
            }
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
        if isWatch {
            WatchDiagnostics.log(session.isReachable ? "telefon erişilebilir" : "telefon erişilemiyor")
        }
        DispatchQueue.main.async { [weak self] in self?.reachable = session.isReachable }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        if message["type"] as? String == "refresh" {
            guard !isWatch else {
                replyHandler(["type": "refreshUnavailable"])
                return
            }
            DispatchQueue.main.async { [weak self] in
                self?.refreshHandler?()
                replyHandler(["type": "refreshQueued", "at": Date().timeIntervalSince1970])
            }
            return
        }
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
