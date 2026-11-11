import Foundation
import UserNotifications

/// Bakım hatırlatıcıları için yerel bildirim planlayıcı.
///
/// Core katmanındaki `MaintenanceStore` salt veridir; bildirim üretimi burada
/// yapılır. Aynı bakım için tekrar tekrar bildirim göndermemek üzere
/// `lastNotifiedKey` ile günlük sınır uygulanır.
enum MaintenanceNotifier {

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Yaklaşan ve gecikmiş bakımlar için bildirim gönderir.
    /// Aynı bakım aynı gün içinde ikinci kez bildirilmez
    /// (`NotificationDedupe`; kayıt yalnız başarılı gönderimde yapılır).
    static func notify(items: [MaintenanceItem], odometer: Double, vin: String) {
        let center = UNUserNotificationCenter.current()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let dedupe = NotificationDedupe(store: UserDefaults.standard)

        for item in items {
            let notifyKey = StorageKeys.maintenanceNotified(vin, itemID: item.id)
            guard dedupe.shouldNotify(key: notifyKey, now: today) else { continue }

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
                    dedupe.record(key: notifyKey, now: today)
                }
            }
        }
    }

    /// Bakım silindiğinde/tamamlandığında bekleyen bildirimleri temizler.
    static func cancel(itemIDs: [UUID], vin: String) {
        let identifiers = itemIDs.flatMap { id -> [String] in
            NotificationDedupe(store: UserDefaults.standard).reset(key: StorageKeys.maintenanceNotified(vin, itemID: id))
            return [id.uuidString]
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
