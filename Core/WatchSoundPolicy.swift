import Foundation

/// Saat ses/bildirim kararlarının tek kaynağı.
///
/// Neden gerekli: kararlar `ToqdasWatchApp` içine dağılmıştı — hangi olayda
/// ses çalınacağı, ne kadar sönümleneceği, bildirim metni ve anahtar adları
/// ayrı ayrı yerlerdeydi; kilit duyurusu tazelik kontrolü yapmıyordu ve
/// gövde metni "imzalı telemetriyle doğrulandı" diyordu (eski veriyle de).
///
/// Kasıtlı sınırlar (platform gerçekleri, değiştirilemez):
/// - watchOS `UNNotificationSound(named:)` **desteklemez** → arka planda
///   olay ayrımı yalnız bildirim **sayısıyla** yapılır (kilit 1, açık 2).
/// - watchOS kendi yerel bildirimini **ön planda sessiz** işler → ön plan
///   sesi `WatchChime` tonuyla verilir.
/// - Ses kararı hiçbir zaman "araç hazır/başarılı" iddiası üretmez; metin
///   yalnız imzalı telemetrinin söylediğini aktarır ve tazelik şartına
///   bağlıdır. Komut **onayı** (ack) uygulandı anlamına gelmez.
enum WatchSoundPolicy {

    /// Ses/bildirim üreten olaylar.
    enum Event: String, CaseIterable {
        /// Araç verisi ready oldu (false → true).
        case connected
        /// Veri akışı uzun boşluktan sonra geri geldi.
        case resumed
        case locked
        case unlocked
        /// Saatten verilen komut iPhone köprüsünce iletildi (ack değil).
        case commandForwarded
        /// Komut iletilemedi / başlatılamadı.
        case commandFailed
    }

    /// Kullanıcı ayarı grupları (saatte üç anahtar).
    enum Toggle: String, CaseIterable {
        case connection
        case lock
        case command

        var title: String {
            switch self {
            case .connection: return "Bağlantı sesi"
            case .lock: return "Kilit sesi"
            case .command: return "Komut sesi"
            }
        }

        var detail: String {
            switch self {
            case .connection: return "Araç verisi akmaya başlayınca kısa ton"
            case .lock: return "Kilitlenme ve kilit açılma sesleri"
            case .command: return "Komut iletildi / tamamlanmadı"
            }
        }

        /// Kullanıcı tercihi anahtarı (VIN yok).
        var key: String { "toqdas.watch.sound.\(rawValue)" }

        /// Varsayılan açık: kullanıcı "ses gelmiyor" dediği için kapalı
        /// başlamak yanlış olur; kapatmak tek dokunuş.
        var isEnabledByDefault: Bool { true }
    }

    /// Ön planda çalınan ton (bellek içi üretim; varlık/telif yok).
    enum Tone: String {
        case connected
        case lock
        case unlock
        case commandOK
        case commandFail
    }

    enum Channel: Equatable {
        case chime(Tone)
        /// Arka plan: bildirim sayısı (bip sayısı).
        case notification(Int)
        case none
    }

    enum Decision: Equatable {
        case announce(Channel)
        /// `reason` tanı günlüğüne yazılır (Türkçe, kısa).
        case suppressed(String)
    }

    /// Duyuru için gereken en fazla telemetri yaşı.
    static let freshWindow: TimeInterval = 15

    /// Komut sonucu beklemeden önce kilit durumu değişimi "yön" olayıdır;
    /// kısa sönümleme flap'te tekrarı önler.
    static func toggle(for event: Event) -> Toggle {
        switch event {
        case .connected, .resumed: return .connection
        case .locked, .unlocked: return .lock
        case .commandForwarded, .commandFailed: return .command
        }
    }

    static func tone(for event: Event) -> Tone? {
        switch event {
        case .connected, .resumed: return .connected
        case .locked: return .lock
        case .unlocked: return .unlock
        case .commandForwarded: return .commandOK
        case .commandFailed: return .commandFail
        }
    }

    /// Arka planda iletilecek bildirim sayısı. watchOS özel bildirim sesi
    /// desteklemediği için "açıldı" çift bip ile ayrılır.
    static func notificationCount(for event: Event) -> Int {
        switch event {
        case .connected, .resumed: return 1
        case .locked: return 1
        case .unlocked: return 2
        case .commandForwarded, .commandFailed: return 1
        }
    }

    /// Aynı olayın saniyeler içinde tekrar duyurulmasını engelleyen pencere.
    static func damping(for event: Event) -> TimeInterval {
        switch event {
        case .connected: return 90
        case .resumed: return 60
        case .locked, .unlocked: return 15
        case .commandForwarded, .commandFailed: return 5
        }
    }

    /// Sönümleme sayacının kalıcı anahtarı. `resumed` kasten `connected`
    /// anahtarını paylaşır: veri dönüşü bağlantı duyurusunu tekrar etmez.
    static func dampingKey(for event: Event) -> String {
        switch event {
        case .connected, .resumed: return "toqdas.watch.connectAnnouncedAt"
        case .locked: return "toqdas.watch.lockAnnouncedAt"
        case .unlocked: return "toqdas.watch.unlockAnnouncedAt"
        case .commandForwarded, .commandFailed: return "toqdas.watch.commandAnnouncedAt"
        }
    }

    /// Tazelik şartı yalnız araç durumu iddiası taşıyan olaylarda geçerlidir;
    /// komut sonucu bildirimi telemetri tazeliğine bağlı değildir.
    static func requiresFreshData(_ event: Event) -> Bool {
        switch event {
        case .connected, .resumed, .locked, .unlocked: return true
        case .commandForwarded, .commandFailed: return false
        }
    }

    static func title(for event: Event) -> String {
        switch event {
        case .connected: return "Araç bağlandı"
        case .resumed: return "Araç verisi yeniden akıyor"
        case .locked: return "Araç kilitlendi"
        case .unlocked: return "Araç kilidi açıldı"
        case .commandForwarded: return "Komut iletildi"
        case .commandFailed: return "Komut doğrulanamadı"
        }
    }

    /// Gövde metni: yalnız ölçüleni söyler. Kilit/açma metni **yön** ve
    /// **tazelik** bilgisi taşır; "doğrulandı" iddiası ack için kullanılmaz.
    static func body(for event: Event) -> String {
        switch event {
        case .connected:
            return "Kilit verisi akıyor; saat uygulamasından komut verebilirsin."
        case .resumed:
            return "Veri akışı yeniden başladı; son imzalı durum güncel."
        case .locked:
            return "Araçtan gelen imzalı veri: kilitli."
        case .unlocked:
            return "Araçtan gelen imzalı veri: kilit açık."
        case .commandForwarded:
            return "Araç yanıtı bekleniyor; sonuç imzalı telemetriden doğrulanır."
        case .commandFailed:
            return "Ayrıntı saat ekranında; araç gerekçe bildirmiyor."
        }
    }

    /// Ses kararı. Dört girdi: kullanıcı ayarı, tazelik, ön plan/arka plan,
    /// son duyurudan bu yana geçen süre. Karar saf; saat yalnız uygular.
    static func decision(event: Event,
                         enabled: Bool,
                         fresh: Bool,
                         foreground: Bool,
                         sinceLast: TimeInterval?) -> Decision {
        guard enabled else { return .suppressed("ayar kapalı") }
        if requiresFreshData(event), !fresh {
            return .suppressed("imzalı veri eski")
        }
        if let sinceLast, sinceLast >= 0, sinceLast < damping(for: event) {
            return .suppressed("sönümleme penceresi")
        }
        if foreground, let tone = tone(for: event) {
            return .announce(.chime(tone))
        }
        let count = notificationCount(for: event)
        return count > 0 ? .announce(.notification(count)) : .suppressed("kanal yok")
    }
}

/// Saatteki üç ses anahtarının kalıcılığı (VIN yok, tek kaynak).
enum WatchSoundSettings {
    static func isEnabled(_ toggle: WatchSoundPolicy.Toggle,
                          defaults: UserDefaults = .standard) -> Bool {
        guard let stored = defaults.object(forKey: toggle.key) as? Bool else {
            return toggle.isEnabledByDefault
        }
        return stored
    }

    static func set(_ enabled: Bool,
                    for toggle: WatchSoundPolicy.Toggle,
                    defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: toggle.key)
    }

    /// Testler ve "varsayılana dön" için.
    static func reset(defaults: UserDefaults = .standard) {
        for toggle in WatchSoundPolicy.Toggle.allCases {
            defaults.removeObject(forKey: toggle.key)
        }
    }
}
