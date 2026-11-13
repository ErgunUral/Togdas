import Foundation

/// Senaryolar rehberi — uygulamanın tüm kullanıcı senaryolarının saf içerik
/// modeli. UI'sızdır (yalnız Foundation + VisualTone); Widget/Watch
/// hedefleri bu dosyayı derlemez (yalnız App hedefine eklenir), bu yüzden
/// SwiftUI'dan bağımsız tutuldu.
///
/// Doğruluk kaynağı: metinler uygulamanın gerçek davranışını yansıtır —
/// yakınlık kuralları `ProximityAutomation` (`ProximityCalibration`
/// minimumSeparation = 14 dB, `ProximityGate` uzak taban şartı) +
/// `ProximityCycleGuard` (tek bilet, 30 sn hold) + `DashboardView.
/// processProximityRSSI` (taze telemetri, bekleme durumu, arka plan sınırı)
/// akışından; komutlar `BLECommandPolicy` + `VoiceIntent`'ten; saat/widget
/// salt görüntü ilkesinden türetildi. Metni değiştirmeden önce ilgili
/// davranışı doğrula.

// MARK: - Bölüm

/// Rehber bölümleri; `ScenarioGuideSheet` odaklı açılışta bu id'ye kaydırır.
enum ScenarioSection: String, CaseIterable, Identifiable {
    case setup
    case link
    case proximity
    case commands
    case watchWidget
    case energy
    case notifications
    case troubleshooting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .setup: return "Kurulum"
        case .link: return "Bağlantı & Anahtar"
        case .proximity: return "Yakınlık Otomasyonu"
        case .commands: return "Komutlar"
        case .watchWidget: return "Saat & Widget"
        case .energy: return "Enerji & Şarj"
        case .notifications: return "Bildirimler"
        case .troubleshooting: return "Sık Karşılaşılan Durumlar"
        }
    }

    var icon: String {
        switch self {
        case .setup: return "checklist"
        case .link: return "point.3.connected.trianglepath.dotted"
        case .proximity: return "dot.radiowaves.left.and.right"
        case .commands: return "waveform"
        case .watchWidget: return "applewatch"
        case .energy: return "bolt.fill"
        case .notifications: return "bell.badge"
        case .troubleshooting: return "wrench.and.screwdriver"
        }
    }

    var summary: String {
        switch self {
        case .setup: return "Giriş, izinler, Bluetooth, widget/saat ekleme ve geofence kurulumu."
        case .link: return "Telefon ile araç arasında güvenli eşleşme nasıl kurulur. Kurulum bölümündeki izinler ön şarttır."
        case .proximity: return "Yaklaşınca aç, uzaklaşınca kilitle — koşulları ile birlikte."
        case .commands: return "Komutlar yalnız hazır bağlantı ve taze telemetri ile gönderilir."
        case .watchWidget: return "Saat ve widget yalnız görüntüler; komut göndermez."
        case .energy: return "Şarj bütçesi, 12 V akü ve istasyon bilgisi takibi."
        case .notifications: return "Aynı uyarı günde en fazla bir kez bildirilir."
        case .troubleshooting: return "Beklenmeyen durumda ne olmuş olabilir, ne yapmalı."
        }
    }
}

// MARK: - Senaryo öğesi

/// Tek senaryo: tetikleyici → ne olur → kullanıcının şartı → aksarsa.
struct ScenarioItem: Identifiable, Equatable {
    /// Bölüm içinde benzersiz kısa kimlik ("proximity-lock" gibi); testler
    /// kritik senaryoların varlığını bu id ile doğrular.
    let id: String
    let title: String
    /// Tetikleyici: senaryoyu başlatan kullanıcı eylemi/durumu.
    let trigger: String
    /// Ne olur: uygulamanın yapacağı iş.
    let effect: String
    /// Kullanıcının uyması gereken şart.
    let requirement: String
    /// Şart aksarsa davranış.
    let onBreak: String
}

/// Bir bölümün senaryoları.
struct ScenarioGroup: Identifiable, Equatable {
    let section: ScenarioSection
    let items: [ScenarioItem]

    var id: String { section.id }
}

// MARK: - Katalog

enum ScenarioCatalog {
    /// 8 bölüm; sıra UI'da göründüğü sıradır.
    static let groups: [ScenarioGroup] = [
        ScenarioGroup(section: .setup, items: [
            ScenarioItem(
                id: "setup-login",
                title: "Togg ID girişi",
                trigger: "Uygulama ilk kez açıldığında.",
                effect: "Togg ID ile giriş yapılır; araçlar çekilir, başlık menüsünden araç seçilir.",
                requirement: "Geçerli bir Togg ID hesabı.",
                onBreak: "Giriş başarısız olursa hata gerekçesi ekranda gösterilir."
            ),
            ScenarioItem(
                id: "setup-permissions",
                title: "İzinler",
                trigger: "İlgili özellik ilk kez kullanıldığında.",
                effect: "Bluetooth (araç servislerini bulmak), bildirim, mikrofon (sesli komut) ve konum (EPDK istasyonları + geofence) izinleri istenir.",
                requirement: "Her izni ilk soruda verin; daha sonra Ayarlar > Toqdas'tan da açabilirsiniz.",
                onBreak: "İzin kapalıysa ilgili özellik çalışmaz: Bluetooth araç bulamaz, mikrofon sesli komutu duymaz, bildirim gösterilmez."
            ),
            ScenarioItem(
                id: "setup-bluetooth",
                title: "Bluetooth kurulumu (5 adım)",
                trigger: "Bluetooth Dijital Anahtar kartında 'Kurulumu adım adım dinle' seçildiğinde.",
                effect: "Sesli anlatımlı rehber açılır: araca yaklaş, bağlantıyı başlat, eşleştirmeyi araçtan başlat, kimlik doğrulamayı bekle, yeşil 'Komut hazır' durumunu doğrula.",
                requirement: "iPhone Bluetooth'u açık ve uygulama ekranda kalsın.",
                onBreak: "Araç anahtarı eksik uyarısı görünürse eşleştirme araç ekranından başlatılır."
            ),
            ScenarioItem(
                id: "setup-widget",
                title: "Ana ekran widget'ı",
                trigger: "Ana ekranda widget galerisinden Toqdas widget'ı eklendiğinde.",
                effect: "Kilit durumu, 12 V akü ve telemetri tazeliği gösterilir; veri telefon uygulamasından gelir.",
                requirement: "Telefon uygulamasının app group'a veri yazması için arada bir ön plana gelmesi gerekir.",
                onBreak: "Veri yoksa 'bilgi yok' gösterilir; widget komut göndermez."
            ),
            ScenarioItem(
                id: "setup-watch",
                title: "Saat kurulumu",
                trigger: "Apple Watch'a kurulum yapıldığında.",
                effect: "Saat uygulaması ve kadran complication'ı kilit/akü durumunu gösterir.",
                requirement: "Watch uygulamasını telefona kurun; complication'ı kadran düzenleme ekranından ekleyin.",
                onBreak: "Complication eklenmemişse kadran boş görünür."
            ),
            ScenarioItem(
                id: "setup-geofence",
                title: "Geofence (ev otomasyonu)",
                trigger: "Geofence kartında ev konumu ayarlandığında.",
                effect: "Bölgeye girince açma, çıkınca kilitleme denenir; konum cihazda değerlendirilir.",
                requirement: "'Ev konumunu ayarla' düğmesini kullanın, yarıçapı seçin; konum izni 'Her zaman' olmalı.",
                onBreak: "Ev konumu veya 'Her zaman' izni eksikse etkinleştirilmez; kartta readiness uyarısı gösterilir."
            ),
        ]),
        ScenarioGroup(section: .link, items: [
            ScenarioItem(
                id: "link-pairing",
                title: "Telefonu araca eşleştir",
                trigger: "Bağlantı kurulup sertifika sunulduğunda.",
                effect: "Uygulama sertifika akışını yürütür; araç onay bekler.",
                requirement: "Araç ekranında dijital anahtar eşleştirmesini onaylamanız gerekir.",
                onBreak: "Onay gelmezse durum 'Araç eşleştirmesi gerekiyor' kalır; uygulama seyrek aralıklarla yeniden dener."
            ),
            ScenarioItem(
                id: "link-certflow",
                title: "Sertifika akışı",
                trigger: "Bağlantı kurulduğunda.",
                effect: "Sertifika çerçeveleri sunulur, araç anahtarı alınır, oturum açılır.",
                requirement: "Araç uyku modundan uyanmış ve BLE reklamlarını yayınlıyor olsun.",
                onBreak: "Araç yanıt vermezse bağlantı zaman aşımıyla kapanır; tekrar denemek için araca yaklaşın."
            ),
            ScenarioItem(
                id: "link-keydiscovery",
                title: "Yeni telefon / yeniden eşleştirme",
                trigger: "Bluetooth taramasından geçerli aday seçildiğinde.",
                effect: "Seçilen araçla bağlantı ve anahtar öğrenme akışı başlar.",
                requirement: "Araç ekranından eşleştirmeyi onaylayın.",
                onBreak: "Eşleşme bilgisi geçersizse sertifika akışına gidilmez; yeniden eşleştirme gerekir."
            ),
            ScenarioItem(
                id: "link-keepconnected",
                title: "Bağlantıyı canlı tutma",
                trigger: "Uygulama açıkken.",
                effect: "Bağlantı koptuğunda uygulama otomatik yeniden bağlanmayı dener.",
                requirement: "Bluetooth açık ve uygulama ön planda olsun.",
                onBreak: "Uygulama arka plandaysa otomatik yeniden bağlanma yapılmaz."
            ),
        ]),
        ScenarioGroup(section: .proximity, items: [
            ScenarioItem(
                id: "proximity-calibration",
                title: "Önce kalibrasyon",
                trigger: "Yakınlık otomasyonunu ilk kez açmak istediğinizde.",
                effect: "Yakın/uzak ölçümlerden eşikler türetilir.",
                requirement: "Yakın ölçüm uzak ölçümden en az 14 dB güçlü olmalı; otomasyon ancak geçerli kalibrasyonla açılır.",
                onBreak: "Fark 14 dB'nin altındaysa otomasyon açılmaz; farklı mesafelerle yeniden ölçün."
            ),
            ScenarioItem(
                id: "proximity-near",
                title: "Yaklaşınca kapılar açılır",
                trigger: "Yakın eşiği geçtiniz (iki ardışık taze örnek).",
                effect: "Uygulama tek bir kilit açma isteği gönderir; sonuç imzalı telemetriyle doğrulanır.",
                requirement: "Otomasyon açık, kalibrasyon geçerli, BLE bağlantısı 'Komut hazır' ve araç kilit telemetrisi güncel olsun.",
                onBreak: "Koşul eksikse eylem atlanır ve gerekçesi durum metnine yazılır; komut gönderilmez."
            ),
            ScenarioItem(
                id: "proximity-lock",
                title: "Uzaklaşınca kapılar kilitlenir",
                trigger: "Uzak eşiğini geçtiniz.",
                effect: "Cam kapatma ve kilit komut akışı başlatılır.",
                requirement: "Uygulama ekranda kalsın; 4 kapının da kapalı olduğunu doğrulayın.",
                onBreak: "Kapı açıksa kilitlenme denenmez ('kapılar kapalı doğrulanmadı')."
            ),
            ScenarioItem(
                id: "proximity-confirm",
                title: "Kilitlenme teyidi",
                trigger: "Kilit komutu gönderildikten sonra.",
                effect: "Araç çift bip sesiyle kilitlenmeyi imzalı telemetriyle teyit eder; teyit sonrası oto-kapatma sayacı başlar.",
                requirement: "Araç sesini duyacak kadar yakın olun; telemetri aksın.",
                onBreak: "Teyit 30 saniye içinde gelmezse sayaç başlamaz ('Kilit telemetrisi doğrulanmadı'); komut yeniden gönderilmez."
            ),
            ScenarioItem(
                id: "proximity-ticket",
                title: "Tek bilet kuralı",
                trigger: "Bir yaklaşımda açma isteği gönderildiğinde.",
                effect: "Aynı döngüde ikinci yaklaşma yeni komut üretmez.",
                requirement: "Yeni açma için önce teyitli biçimde uzaklaşın; bağlantı yenilendiyse önce uzak taban görülür.",
                onBreak: "Belirsizlik varsa bilet iptal edilir ve 30 saniye boyunca açma yapılmaz."
            ),
            ScenarioItem(
                id: "proximity-foreground",
                title: "Uygulama ekranda kalmalı",
                trigger: "Yakınlık algılaması sürekli çalışır (ön planda).",
                effect: "Ön planda algılama + komut; arka planda yalnız bildirim.",
                requirement: "Otomasyonun komut gönderebilmesi için uygulamanın ekranda açık kalması gerekir.",
                onBreak: "Uygulama arka plandaysa komut gönderilmez; yalnız bildirim gösterilir."
            ),
            ScenarioItem(
                id: "proximity-autooff",
                title: "Otomatik kapanma",
                trigger: "Kilitlenme teyidi alındıktan sonra sayaç başlar.",
                effect: "Seçtiğiniz süre dolunca otomasyon kendini pasife alır.",
                requirement: "Süreyi yakınlık ayarından seçin (özel dakika tercihi 0–1440 dk).",
                onBreak: "Süre dolunca otomasyon kapanır ve komut gönderilmez; tekrar açmak isterseniz ayardan aktive edin."
            ),
        ]),
        ScenarioGroup(section: .commands, items: [
            ScenarioItem(
                id: "commands-gate",
                title: "Komut kapısı",
                trigger: "Kilit/aç, klima, cam veya bagaj komutu denediğinizde.",
                effect: "Komut yalnız bağlantı hazır ve telemetri tazeyken gönderilir.",
                requirement: "BLE durumu 'Komut hazır' ve araç telemetrisi güncel olsun.",
                onBreak: "Kapı kapatır: bağlantı yok (link_not_ready), telemetri yok/bozuk (telemetry_missing/stale) veya kilit durumu bilinmiyor (lock_state_unknown)."
            ),
            ScenarioItem(
                id: "commands-result",
                title: "Komut sonucunun doğrulanması",
                trigger: "Komut gönderildikten sonra.",
                effect: "Sonuç, imzalı araç telemetrisiyle doğrulanır; klima/cam durumları telemetri güncellenince yansır.",
                requirement: "Komuttan sonra telemetri akışını bekleyin (birkaç saniye).",
                onBreak: "Telemetri gelmezse sonuç doğrulanamaz; düğme durumunu bekleyerek yenileyin."
            ),
            ScenarioItem(
                id: "commands-voice",
                title: "Sesli komutlar",
                trigger: "Ses panelinde cümle söylediğinizde.",
                effect: "Kilit/aç, bagaj aç/kapat, cam aç/kapat, klima aç/kapat ve durum sorguları çalışır.",
                requirement: "Mikrofon izni verin; komut kapısı koşulları geçerli.",
                onBreak: "Koşul eksikse komut aynı kapıdan engellenir; panel gerekçeyi gösterir."
            ),
        ]),
        ScenarioGroup(section: .watchWidget, items: [
            ScenarioItem(
                id: "watch-readonly",
                title: "Saat ve widget salt görüntü",
                trigger: "Saat kadranını veya ana ekran widget'ını açtığınızda.",
                effect: "Kilit durumu, akü ve telemetri tazeliği gösterilir.",
                requirement: "Veri, telefon uygulamasının app group'a yazdığı son anlık görüntüden gelir.",
                onBreak: "— (komut gönderilmez; gizlilik ilkesi gereği VIN/token yazılmaz)."
            ),
            ScenarioItem(
                id: "watch-freshness",
                title: "Veri tazeliği",
                trigger: "Anlık görüntü güncellendiğinde (30 sn'de en fazla bir kez).",
                effect: "Renk tazeliği anlatır: yeşil canlı, turuncu eski, gri bilgi yok.",
                requirement: "Telefon uygulamasının en az arada bir ön plana gelmesi gerekir.",
                onBreak: "Uygulama hiç açılmadıysa widget/saat 'bilgi yok' gösterir."
            ),
        ]),
        ScenarioGroup(section: .energy, items: [
            ScenarioItem(
                id: "energy-budget",
                title: "Şarj bütçesi",
                trigger: "Şarj işlemi ve fiyat bilgisi girildiğinde.",
                effect: "Harcanan tutar ve tahmini maliyet takip edilir.",
                requirement: "Kapasite ve birim fiyatı ayarlardan doğru girin.",
                onBreak: "Yanlış girişte tahminler kayar; ayarı düzeltmeniz yeterli."
            ),
            ScenarioItem(
                id: "energy-aux",
                title: "12 V akü izleme",
                trigger: "Araç telemetrisi 12 V ölçümü gönderdiğinde.",
                effect: "Akü durumu kartta gösterilir; düşükse uyarı üretilir.",
                requirement: "Telemetri taze olsun.",
                onBreak: "Telemetri yoksa kart '—' gösterir; tahmin üretmez."
            ),
        ]),
        ScenarioGroup(section: .notifications, items: [
            ScenarioItem(
                id: "notify-daily",
                title: "Günde bir kez kuralı",
                trigger: "Aynı uyarı koşulu aynı gün içinde tekrar oluştuğunda.",
                effect: "Yalnız ilk oluşum bildirilir; tekrarları sessizce kaydeder.",
                requirement: "Bildirim izni verilmiş olsun.",
                onBreak: "İzin yoksa bildirim gösterilmez; kart içi uyarılar çalışmaya devam eder."
            ),
            ScenarioItem(
                id: "notify-calibration",
                title: "Kalibrasyon önerisi",
                trigger: "Kalibrasyon geçersizken yakınlık otomasyonu denendiğinde.",
                effect: "Ölçüm yapmanız için rehber açılması önerilir.",
                requirement: "Ölçümü araç yakınında ve uzakta olmak üzere iki adımda yapın.",
                onBreak: "Ölçüm yapılmazsa otomasyon kapalı kalır."
            ),
        ]),
        ScenarioGroup(section: .troubleshooting, items: [
            ScenarioItem(
                id: "trouble-pairing-wait",
                title: "'Araç eşleştirmesi gerekiyor'",
                trigger: "Sertifika sunuldu ama araç onayı gelmedi.",
                effect: "Uygulama bekleme durumuna geçer; seyrek yeniden dener.",
                requirement: "Araç ekranından dijital anahtar eşleştirmesini onaylayın.",
                onBreak: "Onay gelmezse bağlantı zaman aşımıyla kapanır."
            ),
            ScenarioItem(
                id: "trouble-pairing-lost",
                title: "'Eşleşme bilgisi geçersiz'",
                trigger: "Telefonda saklı eşleşme bilgisi artık geçerli değil.",
                effect: "Sertifika akışına gidilemez; bağlantı kurulamaz.",
                requirement: "Bluetooth taramasından yeniden eşleştirme yapın (yeni anahtar öğrenme akışı).",
                onBreak: "Yeniden eşleştirilmezse bu araçla komut gönderilemez."
            ),
            ScenarioItem(
                id: "trouble-timeout",
                title: "Bağlantı zaman aşımı",
                trigger: "Bağlantı kuruldu ama el sıkışma tamamlanamadı.",
                effect: "Bağlantı kapanır, neden 'sinyal zayıf veya araç yanıt vermiyor' diye kayda geçer.",
                requirement: "Araca yaklaşın; araç uyku modundaysa kapıyı açıp kapatın.",
                onBreak: "Tekrar denendiğinde genelde iyileşir."
            ),
            ScenarioItem(
                id: "trouble-lock-verify",
                title: "Kilit teyidi doğrulanmadı",
                trigger: "Uzaklaşma sonrası imzalı çift bip teyidi 30 sn içinde gelmedi.",
                effect: "Oto-kapatma sayacı başlamaz; komut yeniden gönderilmez.",
                requirement: "Kapıların kapalı olduğunu ve araç sesini duyacağınız mesafede olduğunuzu kontrol edin.",
                onBreak: "Kapı açıksa kilitlenme bilinçli olarak denenmez."
            ),
            ScenarioItem(
                id: "trouble-near-skip",
                title: "Yaklaşma eylemi atlandı",
                trigger: "RSSI bayat (30 sn guard), uzak taban görülmedi veya telemetri eski.",
                effect: "Kilit açma gönderilmez; gerekçe durum metnine yazılır.",
                requirement: "Uygulamayı ekranda tutun, uzaklaş-yaklaş döngüsünü tamamlayın.",
                onBreak: "Guard süresi dolana kadar yeni bilet verilmez."
            ),
            ScenarioItem(
                id: "trouble-command-gate",
                title: "Komut düğmesi pasif",
                trigger: "BLECommandPolicy koşulu sağlanmıyor.",
                effect: "Komut engellenir; nedeni (bağlantı yok / telemetri eski / kilit durumu bilinmiyor) gösterilir.",
                requirement: "Bağlantıyı 'Komut hazır' duruma getirin, telemetri tazelenmesini bekleyin.",
                onBreak: "— (koşullar sağlanınca düğme kendiliğinden açılır)."
            ),
        ]),
    ]

    static func group(for section: ScenarioSection) -> ScenarioGroup? {
        groups.first { $0.section == section }
    }

    static func item(section: ScenarioSection, id: String) -> ScenarioItem? {
        group(for: section)?.items.first { $0.id == id }
    }
}

// MARK: - Canlı durum rozetleri

/// Rehberin üst şeridindeki kalıcı rozetler. Girdiler UI'dan gelir
/// (BLE durumu, otomasyon tercihi, kalibrasyon geçerliliği, telemetri
/// tazeliği); türetme saf olarak burada yapılır ve test edilir. Bilinmeyen
/// girdi "bilgi yok" der (asla 0/yanlış varsayılmaz).
struct ScenarioLiveStatus: Equatable {
    var bleReady: Bool?
    var automationEnabled: Bool?
    var calibrationValid: Bool?
    var telemetryFresh: Bool?

    static let unknown = ScenarioLiveStatus()
}

struct ScenarioLiveBadge: Identifiable, Equatable {
    let id: String
    let title: String
    let value: String
    let tone: VisualTone
}

extension ScenarioLiveStatus {
    /// Şerit rozetleri; sıra sabittir: BLE · Otomasyon · Kalibrasyon · Telemetri.
    var badges: [ScenarioLiveBadge] {
        [
            badge(id: "live-ble", title: "BLE", value: bleReady, positive: "Komut hazır", negative: "Bağlı değil"),
            badge(id: "live-automation", title: "Otomasyon", value: automationEnabled, positive: "Açık", negative: "Kapalı"),
            badge(id: "live-calibration", title: "Kalibrasyon", value: calibrationValid, positive: "Doğrulandı", negative: "Yok"),
            badge(id: "live-telemetry", title: "Telemetri", value: telemetryFresh, positive: "Taze", negative: "Eski"),
        ]
    }

    private func badge(id: String, title: String, value: Bool?, positive: String, negative: String) -> ScenarioLiveBadge {
        switch value {
        case .some(true):
            return ScenarioLiveBadge(id: id, title: title, value: positive, tone: .positive)
        case .some(false):
            return ScenarioLiveBadge(id: id, title: title, value: negative, tone: .warning)
        case .none:
            return ScenarioLiveBadge(id: id, title: title, value: "bilgi yok", tone: .neutral)
        }
    }
}
