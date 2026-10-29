import Foundation
import Combine
import UserNotifications

/// Arka planda yalnızca algılama yapan yakınlık izleyici.
///
/// Sınırlar (kasıtlı):
/// - Kapı komutu asla göndermez; geçişler yalnızca günlüğe yazılır ve bildirim düşer.
/// - Ön planda çalışmaz; ön plandaki komut otomasyonu DashboardView'dedir.
/// - Arka plan ölçümü aracın imzalı telemetri bildirimleriyle uyanmaya bağlıdır;
///   iOS uyanma sıklığını kendisi belirler, ölçüm aralığı garanti edilemez.
@MainActor
final class ProximityDetectionMonitor: ObservableObject {
    struct Transition: Codable, Identifiable, Equatable {
        let id: UUID
        let at: Date
        let approached: Bool
        let rssi: Int
    }

    @Published private(set) var backgroundActive = false
    @Published private(set) var transitions: [Transition] = []

    private let ble: BleConnection
    private var vin = ""
    private var gate: ProximityGate?

    init(ble: BleConnection) {
        self.ble = ble
    }

    private var enabledKey: String { GaragePreferences.proximityKey(for: vin) }
    private var nearKey: String { "toqdas.proximity.near.\(vin)" }
    private var farKey: String { "toqdas.proximity.far.\(vin)" }
    private var profileKey: String { "toqdas.proximity.profile.\(vin)" }

    static func logKey(for vin: String) -> String { "toqdas.proximity.log.\(vin)" }

    /// Panodaki kalibrasyon/ayar anahtarları DashboardView ile aynıdır;
    /// geçiş günlüğü okuma amaçlı paylaşılır.
    static func transitionsLog(for vin: String) -> [Transition] {
        loadLog(key: logKey(for: vin))
    }

    func configure(vin: String) {
        guard !vin.isEmpty, vin != self.vin else { return }
        self.vin = vin
        transitions = Self.loadLog(key: Self.logKey(for: vin))
        rebuildGate()
    }

    var detectionAvailable: Bool { gate != nil }

    func appDidEnterBackground() {
        rebuildGate()
        backgroundActive = gate != nil
        guard backgroundActive else { return }
        requestNotificationPermission()
        ble.recordDiagnostic("Arka plan yakınlık algısı etkin; yalnızca izleme, komut gönderilmez")
    }

    func appWillEnterForeground() {
        backgroundActive = false
        gate?.reset()
    }

    func feed(rssi: Int) {
        guard backgroundActive, var current = gate else { return }
        let transition = current.update(rssi: rssi)
        gate = current
        guard let transition else { return }
        let entry = Transition(id: UUID(), at: Date(), approached: transition == .approached, rssi: rssi)
        transitions.append(entry)
        if transitions.count > 50 { transitions.removeFirst(transitions.count - 50) }
        Self.saveLog(transitions, key: Self.logKey(for: vin))
        ble.recordDiagnostic(transition == .approached
            ? "Arka plan algısı: yaklaşma (\(rssi) dBm); komut gönderilmedi"
            : "Arka plan algısı: uzaklaşma (\(rssi) dBm); komut gönderilmedi")
        postNotification(for: entry)
    }

    private func rebuildGate() {
        let defaults = UserDefaults.standard
        guard !vin.isEmpty,
              defaults.bool(forKey: enabledKey),
              let near = defaults.object(forKey: nearKey) as? Int,
              let far = defaults.object(forKey: farKey) as? Int else {
            gate = nil
            return
        }
        let calibration = ProximityCalibration(nearSample: near, farSample: far)
        let profile = defaults.string(forKey: profileKey).flatMap(ProximityProfile.init(rawValue:)) ?? .balanced
        gate = calibration.isValid ? ProximityGate(calibration: calibration, profile: profile) : nil
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func postNotification(for entry: Transition) {
        let content = UNMutableNotificationContent()
        content.title = entry.approached ? "Araç yakında algılandı" : "Araçtan uzaklaşıldı"
        content.body = "Sinyal \(entry.rssi) dBm. Yalnızca algılama; kapı komutu gönderilmedi."
        content.sound = .default
        let request = UNNotificationRequest(identifier: entry.id.uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private static func loadLog(key: String) -> [Transition] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let items = try? JSONDecoder().decode([Transition].self, from: data) else { return [] }
        return items
    }

    private static func saveLog(_ items: [Transition], key: String) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
