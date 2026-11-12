import Foundation
import UserNotifications

/// Yerel bildirim gönderiminin tek noktası.
///
/// Neden gerekli: aynı "izin iste (sessiz) → içerik kur → gönder → başarıda
/// kaydet" deseni 4 ayrı yerde tekrarlanıyordu (DashboardView tire/12 V,
/// kalibrasyon önerisi, `MaintenanceNotifier`, `ChargingBudgetNotifier`);
/// `UNMutableNotificationContent` kurulumu kopyalanıyordu ve davranış
/// test edilemezdi.
///
/// Kasıtlı sınırlar:
/// - Bildirim **kararı** burada değildir: tekrar tekniği
///   (`NotificationDedupe`, `ChargingSpendStore`, eşik politikaları)
///   çağırandadır. Sonuç: gönderimden önce ya da başarıdan sonra kayıt
///   yapan iki farklı mevcut semantik korunur (`onSuccess` yalnız
///   başarılı `add` sonrasında çağrılır).
/// - İzin isteme fire-and-forget kalır (mevcut davranış); izin durumuna
///   göre akış değiştiren tek çağrı (`ChargingBudgetNotifier`) kendi
///   `getNotificationSettings` mantığını korur.
/// - `timeSensitive` yalnız açıkça istenirse kurulur (12 V kritik);
///   Critical Alerts yetkisi yok.
/// - `SystemNotificationPoster` yalnız App içinden kullanılır; testler
///   `NotificationPosting` protokolüne sahte merkez verir.
protocol NotificationPosting {
    func add(_ request: UNNotificationRequest, completion: ((Error?) -> Void)?)
    func requestAuthorization(options: UNAuthorizationOptions, completion: ((Bool) -> Void)?)
}

/// Üretim merkezi sarmalayıcı.
struct SystemNotificationPoster: NotificationPosting {
    func add(_ request: UNNotificationRequest, completion: ((Error?) -> Void)?) {
        UNUserNotificationCenter.current().add(request, withCompletionHandler: completion)
    }

    func requestAuthorization(options: UNAuthorizationOptions, completion: ((Bool) -> Void)?) {
        UNUserNotificationCenter.current().requestAuthorization(options: options) { granted, _ in
            completion?(granted)
        }
    }
}

enum NotificationPoster {
    struct Draft {
        var identifier: String
        var title: String
        var body: String
        /// 12 V kritik bandı gibi yoğun olmayan time-sensitive gösterim.
        var timeSensitive = false
        var sound = true
    }

    /// Sessiz izin isteği (mevcut fire-and-forget davranışı).
    static func requestAuthorization(using center: NotificationPosting) {
        center.requestAuthorization(options: [.alert, .sound], completion: nil)
    }

    /// Bildirim gönderir; `onSuccess` yalnız sistem kabul ederse çağrılır
    /// (kayıt yalnız başarılı gönderimde semantiği).
    static func post(
        _ draft: Draft,
        using center: NotificationPosting,
        onSuccess: (() -> Void)? = nil
    ) {
        let content = UNMutableNotificationContent()
        content.title = draft.title
        content.body = draft.body
        if draft.sound {
            content.sound = .default
        }
        if draft.timeSensitive {
            content.interruptionLevel = .timeSensitive
        }
        let request = UNNotificationRequest(
            identifier: draft.identifier,
            content: content,
            trigger: nil
        )
        center.add(request) { error in
            guard error == nil else { return }
            onSuccess?()
        }
    }
}
