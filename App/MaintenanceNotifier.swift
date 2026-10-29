import Foundation
import UserNotifications

/// Bakım hatırlatıcıları için yerel bildirim planlayıcı.
///
/// Core katmanındaki `MaintenanceStore` salt veridir; bildirim üretimi burada
/// yapılır. Aynı bakım için tekrar tekrar bildirim göndermemek üzere
/// `lastNotifiedKey` ile günlük sınır uygulanır.
enum MaintenanceNotifier {
    private static let prefix = "toqdas.maintenance.notify."

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Yaklaşan ve gecikmiş bakımlar için bildirim gönderir.
    /// Aynı bakım aynı gün içinde ikinci kez bildirilmez.
    static func notify(items: [MaintenanceItem], odometer: Double, vin: String) {
        let center = UNUserNotificationCenter.current()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        for item in items {
            let notifyKey = "\(prefix)\(vin).\(item.id.uuidString)"
            let last = UserDefaults.standard.object(forKey: notifyKey) as? Date ?? .distantPast
            guard !calendar.isDate(last, inSameDayAs: today) else { continue }

            let overdue = item.dueKm <= odometer
            let remaining = item.remainingKm(currentOdometer: odometer)

            let content = UNMutableNotificationContent()
            content.title = "Bakım hatırlatıcı"
            content.body = overdue
                ? "\(item.title) zamanı geldi (\(Int(item.dueKm)) km)."
                : "\(item.title) yaklaşıyor: \(Int(remaining.rounded())) km kaldı."
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "\(item.id.uuidString)-\(Int(today.timeIntervalSince1970))",
                content: content,
                trigger: nil
            )
            center.add(request) { error in
                if error == nil {
                    UserDefaults.standard.set(today, forKey: notifyKey)
                }
            }
        }
    }

    /// Bakım silindiğinde/tamamlandığında bekleyen bildirimleri temizler.
    static func cancel(itemIDs: [UUID], vin: String) {
        let identifiers = itemIDs.flatMap { id -> [String] in
            let notifyKey = "\(prefix)\(vin).\(id.uuidString)"
            UserDefaults.standard.removeObject(forKey: notifyKey)
            return [id.uuidString]
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
