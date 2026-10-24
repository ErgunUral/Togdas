import WatchConnectivity
import Combine

// Only display metadata is transferred. Tokens and digital-key material stay off this channel.
final class WatchLink: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var vehicleNames: [String] = []
    @Published private(set) var updatedAt: Date?
    @Published private(set) var status = "Telefonla eşitleme bekleniyor"
    private var pending: [String: Any]?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func publish(names: [String]) {
        pending = ["schema": 1, "vehicles": names, "updatedAt": Date().timeIntervalSince1970]
        flush()
    }

    private func flush() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated, let pending else { return }
        do {
            try WCSession.default.updateApplicationContext(pending)
            status = "Saat için güncel veri hazır"
        } catch { status = "Saat eşitlemesi bekliyor" }
    }

    private func accept(_ context: [String: Any]) {
        guard context["schema"] as? Int == 1, let names = context["vehicles"] as? [String],
              let timestamp = context["updatedAt"] as? Double else { return }
        vehicleNames = names
        updatedAt = Date(timeIntervalSince1970: timestamp)
        status = "Telefondan alınan son araç listesi"
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        DispatchQueue.main.async { [weak self] in
            if error != nil { self?.status = "Saat bağlantısı kurulamadı"; return }
            self?.accept(context)
            self?.flush()
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async { [weak self] in self?.accept(applicationContext) }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    #endif
}
