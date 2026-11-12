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
                         vin: vin, store: store)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    guard granted else { return }
                    schedule(budget: budget, threshold: threshold, month: month,
                             vin: vin, store: store)
                }
            default:
                return
            }
        }
    }

    private static func schedule(budget: ChargingBudget, threshold: Int, month: String,
                                 vin: String, store: ChargingSpendStore) {
        let title: String
        let body: String
        if threshold >= 100 {
            title = "Aylık şarj bütçesi aşıldı"
            body = "\(ChargingBudget.money(budget.spentTRY)) harcandı; limit \(ChargingBudget.money(budget.limitTRY))."
        } else {
            title = "Şarj bütçesinin %80'i kullanıldı"
            body = "\(ChargingBudget.money(budget.spentTRY)) / \(ChargingBudget.money(budget.limitTRY)) · \(ChargingBudget.money(budget.remainingTRY)) kaldı."
        }

        let identifier = "toqdas.budget.\(vin).\(month).\(threshold)"
        NotificationPoster.post(
            NotificationPoster.Draft(identifier: identifier, title: title, body: body),
            using: SystemNotificationPoster(),
            onSuccess: { store.markNotified(threshold: threshold, month: month) }
        )
    }
}
