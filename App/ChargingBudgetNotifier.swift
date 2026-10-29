import Foundation
import UserNotifications

/// Aylık şarj bütçesi eşik bildirimleri.
///
/// Core katmanındaki `ChargingBudget` yalnız durumu hesaplar; bildirim üretimi
/// burada yapılır. Aynı ay içinde 80% ve 100% eşikleri en fazla birer kez
/// bildirilir. İzin yoksa kullanıcıdan yalnız eşik aşıldığında istenir.
enum ChargingBudgetNotifier {
    static func notifyIfNeeded(budget: ChargingBudget, vin: String, store: ChargingSpendStore) {
        let threshold = budget.notificationThreshold
        guard threshold > 0 else { return }
        let month = ChargingSpendStore.monthString()
        guard store.lastNotifiedThreshold(for: month) < threshold else { return }

        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                schedule(budget: budget, threshold: threshold, month: month,
                         vin: vin, store: store, center: center)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    guard granted else { return }
                    schedule(budget: budget, threshold: threshold, month: month,
                             vin: vin, store: store, center: center)
                }
            default:
                return
            }
        }
    }

    private static func schedule(budget: ChargingBudget, threshold: Int, month: String,
                                 vin: String, store: ChargingSpendStore,
                                 center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.sound = .default
        if threshold >= 100 {
            content.title = "Aylık şarj bütçesi aşıldı"
            content.body = "\(ChargingBudget.money(budget.spentTRY)) harcandı; limit \(ChargingBudget.money(budget.limitTRY))."
        } else {
            content.title = "Şarj bütçesinin %80'i kullanıldı"
            content.body = "\(ChargingBudget.money(budget.spentTRY)) / \(ChargingBudget.money(budget.limitTRY)) · \(ChargingBudget.money(budget.remainingTRY)) kaldı."
        }

        let identifier = "toqdas.budget.\(vin).\(month).\(threshold)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        center.add(request) { error in
            guard error == nil else { return }
            store.markNotified(threshold: threshold, month: month)
        }
    }
}
