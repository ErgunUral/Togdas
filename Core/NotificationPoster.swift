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
        /// Uygulama paketine gömülü özel bildirim sesi (örn. saat kilit
        /// geçişlerinde tek/çift bip). Belirtilirse default sesi geçersiz kılır.
        var soundName: String?
    }

    /// Sessiz izin isteği (mevcut fire-and-forget davranışı).
    static func requestAuthorization(using center: NotificationPosting) {
        center.requestAuthorization(options: [.alert, .sound], completion: nil)
    }

    /// Bildirim gönderir; `onSuccess` yalnız sistem kabul ederse çağrılır
    /// (kayıt yalnız başarılı gönderimde semantiği). `delay` verilirse
    /// zamanlanmış bildirim olur (örn. saatte çift bip simülasyonu:
    /// 0,5 sn arayla ikinci bildirim). watchOS özel bildirim sesini
    /// desteklemez (`soundNamed` API_UNAVAILABLE) → default ses kullanılır.
    static func post(
        _ draft: Draft,
        using center: NotificationPosting,
        delay: TimeInterval? = nil,
        onSuccess: (() -> Void)? = nil
    ) {
        let content = UNMutableNotificationContent()
        content.title = draft.title
        content.body = draft.body
        #if os(watchOS)
        content.sound = draft.sound ? .default : nil
        #else
        if let soundName = draft.soundName {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: soundName))
        } else if draft.sound {
            content.sound = .default
        }
        #endif
        if draft.timeSensitive {
            content.interruptionLevel = .timeSensitive
        }
        let trigger = delay.map {
            UNTimeIntervalNotificationTrigger(timeInterval: $0, repeats: false)
        }
        let request = UNNotificationRequest(
            identifier: draft.identifier,
            content: content,
            trigger: trigger
        )
        center.add(request) { error in
            guard error == nil else { return }
            onSuccess?()
        }
    }
}
