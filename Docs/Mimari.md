# Toqdas iOS — Mimari Yol Haritası

Bu belge, mevcut çalışan uygulamayı bozmadan **modüler monolit** hedefe taşımak
için sıralamayı ve sınırları tanımlar. Sıfırdan yeniden yazım bu planın parçası
değildir; BLE protokolü, sertifika akışı ve saha doğrulamaları korunacaktır.

## 1. Mevcut durum

Ölçülen başlangıç noktası:

- `App`: 29 Swift dosyası, yaklaşık 11.258 satır.
- `Core`: 41 Swift dosyası, yaklaşık 7.676 satır.
- `Tests`: 48 dosya, 387 birim testi; `UITests`: 1 dosya, 4 smoke testi.
- `App/DashboardView.swift`: 3.208 satır, 58 `@State`.
- `Core/BleConnection.swift`: 1.445 satır, 17 `@Published`.
- `App/ToqdasApp.swift`: 615 satır; `GarageModel` ve `GarageView` aynı dosyada.

Güçlü yanlar:

- `Core` büyük ölçüde App katmanından ayrılmış.
- BLE protokolü, komut kapıları, yakınlık, şarj ve ses politikaları test edilebilir.
- Gerçek API ile çalışan E2E harness mevcut.
- Hata ve tanı bilgisi kullanıcıya gösteriliyor.

Darboğazlar:

- `DashboardView` hem görünüm hem feature state hem de yan etki taşıyor.
- `BleConnection` taşıma, el sıkışma, komut kuyruğu, tanı ve hata yönetimini birlikte yürütüyor.
- `GarageModel` oturum, araç listesi, BLE, Watch, Widget ve geofence'i birlikte yönetiyor.
- Hata nedenleri çoğunlukla `lastEvent: String`; güvenlik kararları için tipli model yok.
- UI doğrudan servis ve `UserDefaults` erişimi yapıyor.
- `Core` içinde `CoreBluetooth` ve `CoreLocation` var; domain tamamen saf değil.

## 2. Hedef modül haritası

```text
ToqdasApp/                 # kompozisyon kökü, DI, uygulama yaşam döngüsü
Features/
  Garage/
  Dashboard/
  DigitalKey/
  Commands/
  Charging/
  Trips/
  Voice/
  Account/
Domain/
  Models/
  Policies/
  Errors/
Services/
  API/
  BLE/
  Keychain/
  Watch/
  Widget/
  Notifications/
  Location/
  Speech/
DesignSystem/
```

Bağımlılık kuralları:

- `Features -> Domain + Service protokolleri`
- `Services -> Domain`
- `App -> hepsi`
- `Domain -> yalnız Foundation`
- Özellik modülleri birbirini import etmez.
- UI; `ToggAPI`, `BleConnection`, `UserDefaults` gibi somut servisleri doğrudan kullanmaz.

## 3. BLE sınırı

BLE, tek bir sınıftan şu parçalara ayrılacak:

- `BLETransport`: yalnız CoreBluetooth tarama, bağlanma, yazma ve ham olay.
- `BLESession`: sertifika, araç anahtarı, challenge, READY durum makinesi.
- `BLECommandService`: komut kuyruğu, zaman aşımı, onay ve telemetri doğrulaması.
- `BLEDiagnostics`: tanı olayları, RSSI, hata sınıflandırması ve rapor.
- `BLEClient`: SwiftUI için `@MainActor ObservableObject` kabuk.

Durumlar:

```swift
enum BLESessionState {
    case idle
    case scanning
    case connecting
    case certificate
    case awaitingVehicleKey
    case ready
    case failed(BLEIssue)
}
```

Hata nedenleri string yerine tipli olacak:

```swift
enum BLEIssue {
    case ownerKeyConflict
    case vehicleKeyMissing
    case staleTelemetry
    case commandInFlight
    case disconnected
    case transportTimeout
}
```

Komut sonucu `Bool` yerine aşamalı olacak:

```swift
enum CommandReceipt {
    case queued
    case sent
    case acknowledged
    case verified
    case failed(BLEIssue)
}
```

Bu değişiklikler, "kapı açılmadı" durumunda komutun hangi aşamada ve neden
durduğunu kullanıcıya göstermeyi zorunlu hale getirir.

## 4. Feature state sınırı

`DashboardView` yalnız sekme yönlendirmesi ve ortak kabuk olacak. Her sekme
kendi görünümüne ve store'una ayrılacak:

- `OverviewView` + `OverviewStore`
- `ClimateView` + `ClimateStore`
- `ChargingView` + `ChargingStore`
- `HealthView` + `HealthStore`
- `BLEStatusView` + `BLEStatusStore`
- `QuickActionsView`

Store sözleşmesi:

```swift
@MainActor
final class DashboardStore: ObservableObject {
    struct State { /* yükleniyor, veri, hata, seçili araç */ }
    enum Action { case refresh, selectTab, lock, unlock, ... }
    func send(_ action: Action) async
}
```

Görünümler state okur, action gönderir. API/BLE yan etkileri store'da kalır.

## 5. Kompozisyon kökü ve DI

`GarageModel` şu parçalara ayrılacak:

- `SessionStore`: oturum, giriş/çıkış.
- `GarageStore`: araç listesi ve seçim.
- `WatchBridge`: WatchConnectivity.
- `WidgetBridge`: snapshot ve yenileme.
- `GeofenceCoordinator`: bölge giriş/çıkışı.
- `BLEConnectionCoordinator`: bağlantı yaşam döngüsü.

Bağımlılıklar `AppDependencies` üzerinden enjekte edilecek:

```swift
struct AppDependencies {
    let api: any ToggAPIProtocol
    let ble: any BLEClientProtocol
    let clock: any ClockProtocol
    let preferences: GaragePreferences
    let notifications: any NotificationService
}
```

Testlerde `FakeAPI`, `FakeBLE`, `FakeClock` kullanılacak. Tekil (singleton)
servis ve doğrudan `UserDefaults` erişimi azaltılacak.

## 6. Uygulama sırası

Her faz sonunda uygulama çalışır ve mevcut testler yeşil kalır.

1. **Ölç ve dondur**
   - Bu belge ve ADR'ler.
   - Başlangıç metrikleri: build süresi, crash/CPU, READY süresi, kopma sayısı,
     komut başarı oranı.

2. **BLE'yi ayır**
   - Davranış değişmeden transport, session, command ve diagnostics ayrımı.
   - Scripted BLE olaylarıyla state machine testleri.
   - En yüksek fayda burada.

3. **Kompozisyon kökü + DI**
   - `AppDependencies` ve protokoller.
   - `GarageModel`'i parçala.
   - Testlerde fake servisler.

4. **Dashboard'u böl**
   - Sekmeler ve kartlar ayrı dosyalara.
   - `DashboardStore` ile tek yönlü akış.
   - Dosya başına hedef: mümkünse 500 satır altı.

5. **Modülerleştir**
   - Önce `ToqdasDomain`, `ToqdasServices`, `ToqdasUI` local SPM paketleri.
   - Sonra özellik modülleri.
   - `generate_project.rb` kullanılıyorsa paket yapısı oraya işlenmeli.

6. **Kalite kapıları**
   - CI: build + test + SwiftFormat + strict concurrency uyarıları.
   - UI testleri: komut neden kapalı, sahip anahtarı çakışması, eşleştirme bekliyor.
   - Fiziksel BLE testleri ayrı manuel smoke checklist.

## 7. Başarı ölçütleri

- Kapı komutu: gönderilen / onaylanan / telemetriyle doğrulanan oranı.
- READY'ye ulaşma süresi.
- Oturum başına kopma ve yeniden bağlanma sayısı.
- `vehicleKeyMissing` ve `ownerKeyConflict` sayıları.
- Crash-free session ve CPU watchdog olayları.
- En büyük dosya boyutu, build süresi ve test kapsamı.

## 8. İlerleme

- **Arayüz F8 — Enerji (2026-11-18, 649 + 44):** Sekme durum şeridiyle
  başlıyor: şarj hâli (canlı oturum / "Şarj durumu bilinmiyor"), batarya,
  hedef ve hedefe kalan. İlk ekranda dört blok; geçmiş, hesaplama ve
  istasyonlar **"Geçmiş ve araçlar"** aç/kapasının altında. Ölü `chargingTab`
  kopyası silindi. Şarj pill'i `DSStatus.charging/.idle` ile dürüst.
- **Arayüz F9 — Bakım (2026-11-18):** Durum şeridi 12 V, lastik (en düşük
  PSI) ve iç sıcaklığı gösterir. Fren/motor uyarısı, 12 V < %40 veya kritik
  lastik varsa başlık uyarıyı söyler. **Lastik verisi yokken "Araç sağlıklı"
  denmez**, "Lastik verisi yok" yazar. BLE tanısı "Tanı ve bağlantı"
  derinliğinde. Kart zemini uygulama genelinde `dsCard()` tokenına geçti.
- **Arayüz F10 — Hesap ve menü (2026-11-18):** Hesap Merkezi kart dili,
  iskelet yükleme, boş durum ve hata durumunda "Yeniden dene". Üst menü 9
  öğeye indi; **Bluetooth** (komutlar/tarama) ve **Görünüm** (tema, yoğunluk,
  tasarım önizleme) alt menü oldu.
- **Arayüz F11 — "Tüm kontroller" ayrı ekran denemesi (2026-11-18):**
  Sheet olarak sunulduğunda yuvalanmış sunumlar (dijital anahtar kurulumu,
  yakınlık kalibrasyonu, senaryo rehberi) açılmıyordu: sunum sahipliği
  `DashboardView`da, içerik ise sheet'te kalıyordu. **Geri alındı**; derinlik
  satır içi aç/kapa olarak korundu. Ayrı ekran için kartların ve alt
  sheet'lerin kendi görünümüne taşınması gerekir.
- **Arayüz F12 — Widget ve saat (2026-11-18):** Widget zemini `0x0A0F14`,
  vurgu `0x00D2C8`, negatif ton `0xFF3D00`; saat uygulaması aynı vurguyu
  kullanıyor (`ToqdasWatch` şeması `generic/platform=watchOS` ile derlendi).
- **Arayüz F13 — Cila (2026-11-18):** XXXL testi Enerji/Bakım şeritlerini de
  kapsıyor; boş durum eylemleri ve aç/kapa satırları en az 44 pt; erişilebilirlik
  denetimi dört sekmede de temiz.
- **Kilitleme artık tek komut (2026-11-18):** Cihaz kayıtları, kilidin cam
  kapatma adımına zincirlenmesinin kilidi engellediğini gösterdi
  (17.11 22:08 · kod 7 `linkLost`; kilit hiç gönderilmedi; 21:55'te aynı akış
  cam onayı alınca kilit doğrulandı). Artık **"Kilitle" yalnız kod 1**
  gönderir. Kilit onayı alındıktan sonra cam kapatma **otomatik ve
  best-effort** denenir (18.11 kararı: "kilitle = komple kapanma" beklentisi):
  otomatik komut makbuz üretmez, bu yüzden "Son komut" kilitten kopmaz ve cam
  adımının kopması kilit kaydını kirletmez; kilit doğrulaması da kesilmez.
  Yakınlık otomasyonu aynı akışı kullanır. Cam konumu imzalı telemetride
  **yok**; uygulama yalnız aracın komut onayını görür, camın fiziksel olarak
  kapandığını doğrulayamaz.
- **Cam açma ikincil (2026-11-18):** Protokolde cam açma var (kod 6,
  17.11 21:09:11'de bir kez ACK). Park hâlinde açık cam bırakmak yağmur ve
  hırsızlık riski taşıdığı için **"Yan camları kapat" birincil** (dolu accent,
  onay ister), **"Yan camları aç" ikincil** (düz satır, "Onay ister"); açma
  onay metni riski söyler. Cam konumu doğrulanamadığı notu ikisinin altında
  tek yerde durur.
- **Kopmada "iletilmedi" iddiası kaldırıldı (2026-11-18):** Saat günlüğü +
  telefon kaydı: 18.11 16:54:04'te "Kilitle" gönderildi, 16:54:06'da bağlantı
  koptu (kayıt: "komut araca iletilmedi"), 16:56:14'te imzalı telemetri
  **kilitli** dedi. Yani kopma ack'i yutmuş olabilir; komut ulaşmış olabilir.
  Artık kopmada metin "komutun araca ulaştığı doğrulanamadı" der ve
  `LockVerificationPolicy.window` (90 sn) içinde gelen imzalı telemetri hedefi
  gösterirse aynı kayıt **"doğrulandı · gecikmeli"** olur (not: bağlantı komut
  sırasında koptu). Yeni komut bu niyeti iptal eder; retry yok.
- **Arayüz F7 — durum yokken "Hızlı kontroller" (2026-11-18, 649 + 43):**
  Dört karo da "Bilinmiyor" iken bölüm ölü görünüyordu. Artık kilit/bagaj/
  sürüş/iklim değerlerinden **hiçbiri** yoksa dört karo yerine tek eylem
  kartı çıkar: "Araç durumu henüz okunmadı" + **Araçla bağlan** (BLE hazırsa
  "Durumu oku" → sertifika/oturum). En az bir değer varsa karolar gösterilir
  ve yalnız bilinmeyenler "Bilinmiyor" der. `EmptyState` birincil (dolu)
  eylem düğmesi kazandı (`prominentAction`).
  Karo son hâli — canlı → son bilinen (yaşlı) → (hiçbiri yoksa kart):
  **Kapılar** "Kilitli"/"Kilit açık" · **İklimlendirme** "Açık · 22,0 °C" /
  "Kapalı" (komut sonucu; özetlenmez) · **Arka Bagaj** "Açık"/"Kapalı" ·
  **Sürüş** "Hazır" (yalnız `powerState == 4`) / "Hazır değil".
- **Arayüz F6 — "son bilinen" araç durumu (2026-11-18, 649 birim + 43 UI):**
  Hızlı kontrol karoları canlı BLE verisi yokken hep "Bilinmiyor" kalıyordu;
  gerçek kullanımda BLE oturumları 3–60 sn olduğu için ekran fiilen boş
  görünüyordu. `Core/VehicleStateSnapshot` + `VehicleStateSnapshotStore`:
  son **imzalı** telemetrinin kilit/bagaj/sürüş değerleri VIN başına diske
  yazılır, yaş etiketiyle gösterilir ("Kilitli · 2 saat önce", "Hazır değil ·
  2 saat önce"). 90 sn altı yaş yazılmaz; **24 saatten eski kayıt yüklenmez
  ve diskten silinir**; kayıt yoksa "Bilinmiyor" (değer uydurulmaz).
  Durum şeridi de aynı önceliği kullanır (canlı → son bilinen → bilinmiyor)
  ve alt not "Gösterilen değer N saat önce alınan imzalı telemetriden" der.
  İklimlendirme karo durumu bilinçli olarak "Bilinmiyor": klima bir ölçüm
  değil, komut sonucu; ack uygulandı anlamına gelmediği için eski değer
  "son bilinen" diye sunulmaz. DEBUG: `-seedStateSnapshot` (2 saatlik kayıt).
- **Arayüz F5 — cila ve UI test turu (2026-11-18, 643 birim + 43 UI test):**
  "Hızlı kontroller" karoları ters kurulmuştu (büyük yazı değer, küçük yazı
  ad; veri yoksa büyük yazı "—" kalıyordu) → **ad büyük, durum küçük**
  ("Kapılar · Kilit bilinmiyor", "Sürüş · Hazır değil"). Bilinmeyen değer
  "Bilinmiyor" der; uydurma yok. Eski `VehicleVisualCard` (kalan menzil)
  kaldırıldı: yeni `StatusHero` ile aynı veriyi tekrarlıyor ve **her sekmede**
  görünüyordu. Palet göçü tamamlandı: `themeName` varsayılanı `corporate`;
  kayıtlı eski değer (togg/ocean/graphite) açılışta kurumsala yazılır
  (VoiceOver "seçili" bildirir, seçici boş görünmez). Hesap Merkezi'ndeki
  dekoratif ikonlar `accessibilityHidden` (denetim "bell.badge.fill"
  okumasını yakaladı). UI testleri yeni bilgi mimarisine göre düzeltildi:
  `Tüm kontroller` derinliği (`vehicle.allControls`), menzil "365 km",
  bütçe → Enerji, bakım → Bakım, hesap → sekme; "düzen" testleri
  **yoğunluk** (Rahat/Sıkı) kalıcılığına dönüştü. Hata ayıklama argümanları:
  `-openTab=<vehicle|energy|care|account>`, `-scrollQuickActions`,
  `-scrollCamControls`.
  **Sonuç: 43/43 UI testi yeşil** (iPhone 17 Pro Max simülatörü, iOS 18.6).
- **Arayüz yenilemesi F1–F4 — kabuk, Araç sekmesi, dinamik öncelik
  (2026-11-18, 643 test):** Gezinme tek amaçlı dörde indirildi:
  **Araç · Enerji · Bakım · Hesap** (`DashboardTab` üyeleri
  `vehicle/energy/care/account`; iklimlendirme ayrı sekme değil,
  "Araç → Tüm kontroller" derinliğinde ve hızlı karolarda). Alt bar:
  seçili sekme için yumuşak vurgu kapsülü + 44pt hedef (erişilebilirlik
  kimlikleri `tab.<raw>` korunur). "Hesap" artık gerçek sekme
  (`AccountCenterView` kendi `NavigationStack`'inde); menüdeki
  "Bildirimler & destek" sekmeye yönlendirir.
  **Araç ekranı** (`vehicleTab`): güvenlik şeridi → `StatusHero` (kilit,
  son görülme, batarya/menzil/12 V, durum rozeti) → **"Şimdi önemli"**
  (en fazla 3 kart) → `ActionTile` 2 sütun (Kapılar/İklim/Bagaj/Sürüş) →
  son komut kartı → **"Tüm kontroller"** (aşamalı açıklama: klima, uzaklaşma
  bileti, cam/kontrol, yakınlık, geofence, son görülme, Bluetooth).
  Dinamik sıralama `Core/DashboardPriorityEngine` (saf, 13 test): bağlantı
  yok, 12 V kritik/uyarı, komut doğrulanamadı, kapı/bagaj açık, veri eski,
  sinyal zayıf, şarj hedefi, hazır (yalnız `powerState == 4`). Metinler
  ölçüleni söyler; eksik değer için yüzde/süre uydurulmaz, "araç reddetti"
  yazılmaz. Öncelik yoksa dürüst boş durum: "Şimdi acil bir şey yok".
  Eski 4 "düzen" seçimi 2 gerçek tercihe indi: **Yoğunluk (Rahat/Sıkı)**;
  kayıtlı `classic/sport/technical` → Rahat, `minimal` → Sıkı (sessiz
  sıfırlama yok). Enerji sekmesi: canlı oturum + hedef + bütçe + geçmiş +
  hesap + istasyonlar. Bakım: sağlık + servis + sürüş istatistikleri +
  teknik özet. **İlk açılış tanıtımı** (`App/FirstRunSheet.swift`, 3 adım,
  atlanabilir, `toqdas.onboarding.seen.v1`; UI testlerinde atlanır) ve
  Reduce Motion uyumlu kart girişi (`dsAppear`) eklendi. UI testleri yeni
  sekme adlarına ve iklimlendirmenin derinliğine güncellendi.
- **Arayüz yenilemesi F0 — kurumsal tasarım sistemi (2026-11-18):**
  `App/DesignSystem.swift` (spacing 4/8/12/16/24/32, radius 12/16/20,
  elevation, `StatusPill`/`DSStatus` tek durum dili, `StatusHero`,
  `PriorityCard`, `ActionTile` 2 sütun ≥56pt, `MetricCell`, `DataRow`,
  `SectionHeader`, `EmptyState`, `SkeletonRow`, `ToastBanner`, `SheetShell`,
  Reduce Motion uyumlu `dsAppear`) + `App/DesignPreviewView.swift`
  (menü → "Tasarım önizleme"; veri okumaz, komut göndermez). Palet göçü:
  3 dağınık palet (Togg Gece/Okyanus/Grafit) → **Kurumsal** ve
  **Yüksek Kontrast**; eski `StorageKeys.theme` değerleri kurumsala
  eşlenir (kayıt silinmez). Seçici yalnız iki paleti gösterir.
- **Saat ses/bildirim katmanı (2026-11-18, 630 test):** Ses kararları
  `ToqdasWatchApp` içine dağılmıştı (3 olay, 3 magic `UserDefaults`
  anahtarı, tek ton) ve **kilit duyurusu tazelik kontrolü yapmıyordu** —
  gövde metni eski snapshot'tan bile "imzalı telemetriyle doğrulandı"
  diyordu. Eklendi: `Core/WatchSoundPolicy` (olay → kanal/ton/sönümleme/
  metin, saf ve testli; 6 olay: connected, resumed, locked, unlocked,
  commandForwarded, commandFailed) + `WatchSoundSettings` (üç anahtar:
  bağlantı/kilit/komut, varsayılan açık, VIN yok). Ön planda watchOS kendi
  bildirimini sessiz işlediği için **kilit ve açılma tonları** eklendi
  (alçalan/yükselen çift nota; bağlantı 880→1175 Hz); arka planda ayrım
  hâlâ bildirim sayısıyla (kilit 1, açık 2). Tazelik şartı yalnız araç
  durumu iddiası taşıyan olaylarda (`requiresFreshData`), komut sonucunda
  değil. "forwarded" metni "Komut iletildi" der — ack uygulandı anlamına
  gelmez. `AVAudioSession` artık çalma bitince kapatılıyor
  (`mixWithOthers`, `notifyOthersOnDeactivation`) — eskiden
  `setActive(false)` hiç çağrılmıyordu. Saatte **"Ses ve bildirimler"**
  bölümü (watchOS'ta `DisclosureGroup` yok → aç/kapa düğmesi): üç anahtar,
  bildirim izni durumu ("Arka planda ses kapalı · Ayarlar > Bildirimler")
  ve "Sesi dene". Tanı: `ses · <olay> · <kanal|susturma nedeni>` saat
  günlüğüne yazılır. Yeni Core dosyası saat hedefine eklendi (Sources fazı
  `995D61EAA56DA73CB212EB4A`).
- **UI/UX planı Faz U1–U3 (2026-11-12, 437 test):**
  - U1 tip ölçeği: `ToggText` (7 semantik stil, `ToggTheme.text`) — 158
    sabit `.system(size:)` taşıma; monospace meta sabit kalır; ClimateCard
    hero sayısı `@ScaledMetric`; Dynamic Type xxxLarge ile sınır (`eca1d69`).
  - U2 durum renk sözlüğü: `Core/VisualTone` (positive/warning/negative/
    neutral) + `LockVisual.tone` + `BleConnection.State.visualTone`
    (BleConnection.swift'te — Widget/Watch hedefleri BleConnection'sız
    derler); `ToggTheme.color(for:)`; Widget lockTint/canlılık ve saat
    lockColor aynı tonlardan (`c1bd83a`).
  - U3 erişilebilirlik: kapı kutucukları VoiceOver, ≥44pt vurma hedefleri
    (sekmeler, BLE düğmeleri, klima toggle/cam komutları), Reduce Motion
    desteği (`8ad220b`).
- **Watch planı Faz W1–W3 (2026-11-12):**
  - W1 cihaz kurulumu: Watch Ultra 2 Mac'e eşleşti, Geliştirici Modu; watch
    build `buildWatch/` ile kurulu (UDID takıma kayıtlı).
  - W2 saat UI denetimi (`2b6558e`): kilit ikonu `.largeTitle.weight(.semibold)`,
    complication `lockColor` `LockVisual`'dan (eski veri → turuncu, bilgi yok
    → gri); köşe gauge 8pt kasıtlı sabit.
  - W3 app group provizyonu (`1c151ee` + `e594746`): `group.com.toqdas.ios`
    4 entitlements dosyasına yazıldı; Xcode 27.2 GUI'de 4 hedefe
    DEVELOPMENT_TEAM=2QAL5894CY seçildi → otomatik imzalama portal kaydını
    yaptı, 4 profil app group'lu doğrulandı. App group'lu build'ler kuruldu
    (17, 14, Watch Ultra 2). Kısıt: Personal Team profilleri ~7 gün ömürlü.
  - W4 araç başı doğrulaması: `Docs/W4-Yakinlik-Dogrulama.md` (bekliyor).
- **Senaryolar Rehberi (2026-11-13, 447 test, `8a7aec6`):**
  - `Core/ScenarioContent` (saf, testli): 7 bölüm — Bağlantı & Anahtar,
    Yakınlık Otomasyonu, Komutlar, Saat & Widget, Enerji & Şarj,
    Bildirimler, Sık Karşılaşılan Durumlar; her senaryo
    tetik→ne olur→şart→aksarsa kalıbında; `ScenarioLiveStatus`
    rozetleri (BLE/otomasyon/kalibrasyon/telemetri, bilgi yok → nötr).
  - `App/ScenarioGuideSheet` (U1/U2/U3 uyumlu) + girişler: header
    menüsü ve yakınlık kartı `book` düğmesi (odaklı açılış); `?`
    kalibrasyon sheet'i değişmedi.
    - Kurulum bölümü eklendi (2026-11-13, 450 test, `9e6468b`): 8. bölüm
    ilk sırada — Togg ID girişi, izinler (Bluetooth/bildirim/mikrofon/
    konum), Bluetooth 5 adımlı rehber (`BLESetupGuideSheet` özeti, gerçek
    düğme adı "Kurulumu adım adım dinle"), widget/saat ekleme, geofence
    (resmî metin: "Bölgeye girince açma, çıkınca kilitleme denenir";
    'Her zaman' izni şart).
- **Yakınlık otomatik komut bildirimi (2026-11-13, 459 test, `a53d1be`):**
  - `Core/ProximityCommandNotice` (saf, testli): `BleConnection.lastEvent`
    metnini verified/failed olarak yorumlar (doğrulama: "araç durumuyla
    doğrulandı" / "hedef değerle eşleşiyor"; başarısızlık: "kilit
    değişikliği doğrulanamadı"). Başarısız otomatik komut için bildirim
    taslağı — "doğrulanamadı" ve "başlatılamadı" ayrımı; metin "komut
    yeniden gönderilmedi" der (davranışa sadık). Kimlik VIN içerir,
    başlık/gövde VIN'siz.
  - Dashboard: yalnız yakınlık kaynaklı komutlar için 60 sn penceresiyle
    bildirim; manuel komutlar hariç. Not: açma tarafını BLE katmanı zaten
    `pendingLockVerification` ile doğruluyordu — eksik olan sonucun
    bildirime dönüşmesiydi.
  - Repo hijyeni: `build17/`, `buildWatch/` git takibinden çıkarıldı
    (`.gitignore`, `cd1deba`; önceki commit'lerde birikmişti).
- **Eşleşme kurtarma rehberi (2026-11-13, 464 test, `83d62bd`):**
  - `Core/PairingRecovery` (saf, testli): `pairingLost` için başlık +
    3 adım + özet tek kaynak; banner ve bildirim aynı metni kullanır
    ("Bu tamamlanana kadar otomatik komut gönderilmez"). iOS bağı OS
    seviyesinde olduğundan kurtarma cihaz ayarlarından unutup yeniden
    eşleştirmedir; uygulama kendi silemez.
  - Dashboard `needsRepair` banner'ı Core metinlerine bağlandı; kurtarma
    bildirimi araç başına günde bir (`StorageKeys.pairingRecoveryNotified`).
- **Geofence ↔ yakınlık çakışma koruması (2026-11-13, 471 test, `22dbfc4`):**
  - `Core/AutomaticCommandLedger` (saf, testli): kaynak + eylem başına son
    otomatik komut zamanı. Geofence giriş/çıkışı artık yakınlık guard'larını
    atlamıyor; iki kaynak 30 sn içinde aynı eylemi tekrarlamıyor
    (`geofence_*_skipped`, `proximity_*_skipped` tanı satırları).
- **Kalibrasyon eskimesi (2026-11-13, 477 test, `9543964`):**
  - `Core/ProximityCalibrationAge` (saf, testli): 30 gün eşiği; hiç kalibre
    edilmemiş durum uyarı üretmez. `ProximitySettings` ölçüm anını VIN
    bazlı saklar (`toqdas.proximity.calibrationAt.<vin>`, sıfırlamada
    temizlenir). Yakınlık kartında turuncu bilgilendirme notu; otomasyonu
    kapatmaz, komut göndermez.
- **Saat tanısı (2026-11-13, 483 test, `26486ea`):**
  - `Core/WatchDiagnostics` (saf, testli): saat UserDefaults'unda halka
    tampon (40 olay, `toqdas.watch.diagnostics.v1`). `WatchLink` kayıt
    noktaları: snapshot alındı, yenileme isteği/reddi, komut sonucu
    (`status`), oturum ve erişilebilirlik değişimi. VIN/token yazılmaz;
    UI etkisi yok, komut/ağ kullanımı yok (saha tanısı plist'ten okunur).
- **Eşleşme onarım kilidi + zayıf sinyal seyreltmesi (2026-11-13, 486 test, `02fc072`):**
  - `BleReconnectPolicy.shouldStartConnection`: `needsRepair` varken yalnız
    kullanıcı onayı (`clearRepair: true`) bağlantı başlatır. `BleConnection.start`
    artık onarım durumunu kendiliğinden **sıfırlamaz**; sonsuz
    `pairing_lost` döngüsü biter. Yeni `BleLinkCoordinator.retryAfterRepair()`
    ve Dashboard kurtarma kartındaki “yeniden dene” düğmesi tek açma yolu.
  - `BleReconnectPolicy.weakDropLimit = 3`: üst üste 3 zayıf sinyal
    kopmasından sonra yeniden bağlanma 60 sn’ye seyreltilir (`weak_drop`
    tanısı); 60 sn kararlı bağlantıda veya uygulama öne gelince sıfırlanır.
    Log kanıtı: RSSI −89…−98, oturum 59/44 sn, 8/8 doğrulama başarılı.
- **Tutarlı bağlantı yapısı (2026-11-13, 511 test, `c987c60`):**
  - Tek yaşam döngüsü sahibi: pano içindeki yeniden bağlanma/sayaç durumu
    kaldırıldı; `BleLinkCoordinator` tek kaynak.
  - `Core/BlePhase` + `BlePhaseMachine`: tek faz modeli (idle, searching,
    connecting, authenticating, ready, degraded, repairRequired,
    pairingWait, radioOff, stopped); öncelik sırası sabit ve testli.
  - `Core/KeyIdentity`: dijital imza anahtarının kısa parmak izi (SHA-256/4
    bayt). Anahtar değişimi sessizce kabul edilmez → onarım akışı.
    Sertifika rotasyonu yalnız tanı (`certificate_rotated`).
  - `Core/PairingRepairState` + `PairingRepairStore`: onarım durumu oturumlar
    arası kalıcı (`toqdas.pairing.repair.<vin>`); `Core/ReconnectBudget`:
    deneme/zayıf/eşleştirme sayaçları tek değer tipi.
  - `Core/BlePhaseLog`: son 20 faz geçişi (`toqdas.ble.phase.v1`).
- **Kilit doğrulamasının saate görünürlüğü (2026-11-17, 579
  test):** Belirti: "aracın kilitlendiğini görmüyorum" — kanıtta
  komutlar başarıyla gidiyordu ama sonucu saat yansımamıyordu. Üç
  kopukluk kapatıldı: (1) saatten gönderilen kilit/aç komutu artık
  widget/saat "son komut" kaydına da yazılıyor (önceden yalnız
  panodan gönderim yazıyordu); (2) imzalı telemetri doğrulaması
  (`lastCommandReceipt` .verified) saat snapshot'ına anında gidiyor;
  (3) doğrulanamayan komut (.failed — bağlantı komuttan sonra koptu
  dahil) "doğrulanamadı" etiketiyle kayda yazılıyor; sessiz kaybolma
  yok. Yön eşleşmesi: "Kilidi aç" → "Kilit açma", "Kilitle"/cam
  akışı → "Kilitleme".
- **Saat kilit geçişi sesleri (2026-11-17, 579 test):** Anahtarlık
  davranışı: kilit AÇILDIĞINDA çift bildirim (0,5 sn arayla, çift bip
  hissi), KİLİTLENDİĞİNDE tek bildirim (tek bip). watchOS özel
  bildirim sesini desteklemez (`soundNamed` API_UNAVAILABLE — SDK
  başlığıyla doğrulandı) → ayrım bildirim sayısıyla üretilir, default
  ses. Saatte `previousLocked` geçiş izleme + yön başına 15 sn
  sönümleme (`toqdas.watch.lockAnnouncedAt` /
  `toqdas.watch.unlockAnnouncedAt`); ön planda haptik (.success /
  .notification). `NotificationPoster.post`'a `delay` parametresi
  eklendi (zamanlanmış tetikleyici); `Draft.soundName` iOS tarafında
  saklı (watchOS guard'lı). Metinler: "Araç kilitlendi" / "Araç
  kilidi açıldı" (telemetri kilit durumu; VIN yok).
- **Saat "eski / süre bilinmiyor" yapışkanlığı düzeltmesi
  (2026-11-17, 577 test):** Belirti: telefon bağlıyken saat "Kilit
  verisi eski / iPhone'a ulaşılamıyor · son veri süre bilinmiyor"
  gösteriyordu. Kök neden: bağlantı kurulunca önemli durum (ready)
  anında gider ama telemetri henüz yoktur (`telemetryAge=nil`);
  1-2 sn sonra telemetri gelince düzeltici güncelleme 30 sn
  darboğaza takılır, sonra da gösterim değerleri sabitlenince
  parmak izi değişmez → nil snapshot saatte yapışır. Düzeltmeler:
  (1) `importantFingerprint`'e kilit durumu eklendi (nil→bilinen ve
  true↔false geçişi anında gider); (2) saatte saat sapmasından
  doğan küçük negatif yaş 0'a kelepçelendi ("süre bilinmiyor"
  yazmıyor); (3) metinler dürüstleştirildi: reachable=false normal
  arka plan davranışı olduğundan "ulaşılamıyor" yerine "iPhone
  uygulaması arka planda · son veri X" ve "Komut için iPhone
  uygulaması açık olmalı".
- **Zayıf sinyalde yeniden bağlanma yumuşatması (2026-11-17,
  576 test):** Cihaz kanıtı (ort. −93 dBm, zayıf %100) döngünün her
  dakika tekrarlandığını gösteriyordu; gece boyu radyo/pil yükü.
  `BleReconnectPolicy`'e derin zayıflık kademesi eklendi: 3+ ardışık
  zayıf kopmada 60 sn (mevcut), **5+ ardışıkta 120 sn**. Ön plana
  gelme/kararlı bağlantı sayaçları sıfırladığından kullanıcı etkileşimi
  ve yaklaşma anında toparlanma korunur. Komut akışına etkisi yok.
- **Saat: şarj hedefi gözcüsü + kurtarma onayı + bağlantı sesi
  (2026-11-17, 574 test):** (1) `WatchSnapshot`'a `chargingActive`/
  `chargingTargetPercent`/`chargingStartedAt` eklendi (eski snapshot
  kayıpsız açılır). Saatte şarj banner'ı ("Şarj sürüyor · %x · hedef %80
  · kalan %y"); hedefe ulaşıldığında saatte yerel bildirim + haptik —
  oturum başına bir kez (dedupe anahtarı oturum başlangıcını içerir,
  VIN yok; Core `ChargingTargetPolicy` ile aynı taban). (2) Sessiz
  kurtarma bitip READY'ye geçince tek `.success` haptiği. (3) Bağlantı
  duyurusu: READY'ye geçişte (false→true) sesli bildirim ("Araç
  bağlandı") + haptik; 90 sn sönümleme; ses yalnız saat uygulaması
  arka plandayken duyulur (platform davranışı — ön planda haptik kalır).
  (4) `NotificationPoster` saat hedefine pbxproj'dan eklendi (watch
  build'i bu dosya olmadan derlenemiyordu).
- **Saat bağlantı metni katmanlaması + kuyruklu tazeleme (2026-11-17,
  574 test):** (1) "Kopma" algısı için metin netleşti: telefon uygulaması
  arka plandayken WCSession `reachable` false olur (platform davranışı);
  saat artık "iPhone uygulaması arka planda; açınca tazelenir" der.
  (2) Tazeleme isteği canlı bağlantı yoksa `transferUserInfo` ile
  **kuyruklu** gönderilir — telefon uygulaması uyandığında teslim
  edilir (`didReceiveUserInfo` işleyicisi + `refreshHandler`).
  KOMUTLAR kuyruksuz kalır (eski komut asla iletilmez invariant'ı
  korunur). (3) Gösterim tazeliği komut eşiğinden ayrıldı: komut 15 sn
  (değişmedi), gösterimde 15–45 sn "bekleniyor" der (imzalı telemetri
  ~30 sn dönemli; sağlıklı bağlantıda "eski" flap yapmaz), 45 sn üstü
  "eski". `displayStale` + `lockText`/`lockSymbol`/`connectionText`
  katmanları saate uygulandı.
- **Saatte "Son görülme" + oturum kalitesi (2026-11-17, 574 test):**
  Saat metrik ızgarasına iki satır eklendi: "Son görülme" (`3 dakika
  önce · BLE` — BLE telemetrisi ile son bilinen bulut anlık görüntüsünün
  en yenisi, `LastSeenSummary`) ve oturum kalitesi özeti (`8 oturum ·
  2 zayıf · ort −93 dBm` — `BleSessionQualitySummary`). Telefon
  `publishWatchSnapshot`'ta üretir; `WatchSnapshot`'a `lastSeenText`/
  `sessionQualityText` alanları eklendi (eski snapshot'lar
  `decodeIfPresent` ile kayıpsız açılır; alanlar display fingerprint'te).
  Hiç veri yoksa saat "—" gösterir; asla "0 dakika önce" yazılmaz.
- **Saatten yakınlık otomasyonu anahtarı (2026-11-17, 572 test):**
  Saat uygulaması otomasyonu artık görüntülemekle kalmayıp açıp
  kapatıyor. Kanal: `WatchLink` komut isteklerine `proximityOn`/
  `proximityOff` eylemleri — aynı ömür (15 sn) + VIN eşleşme kontrolü;
  **araç komutu değildir** → `canSendVehicleCommands` şartı istenmez.
  iPhone: `ToqdasApp.proximityToggleHandler` panodaki
  `setProximityEnabled`'e delegasyon; `setProximityEnabled` artık
  `Bool` döner (kalibrasyon geçersizse açma reddedilir ve saat
  "kalibrasyon kontrol edin" der). Saat: durum satırı + Aç/Kapat
  düğmeleri, kendi onay diyaloğu ("araç komutu göndermez"), haptik ve
  sonuç metni mevcut desenle. Core: `WatchProximityAutomationAction`
  (parse/confirmation/result metinleri, 2 testli). Dürüstlük: açmak
  hiçbir komut göndermez; "gönderilmedi" metinleri açık.
- **Klima denetimi (2026-11-17, 570 test):** Uzaktan klima akışı
  gözden geçirildi; sağlamlıklar korundu (komut öncesi 90 sn tazelik
  sorgusu, tek uçuş kilidi, retry yok, 16–30 °C çift doğrulama, 240 sn
  akış okuması). Düzeltmeler: (1) araç değişince klima durumu/hedefi
  sıfırlanıp yeni araçtan yüklenir — eski aracın "taze" durumuyla yeni
  araca komut gitmesi engellendi; (2) `refreshClimate`/`toggleClimate`/
  `applyClimateTemperature` VIN'i çağrı başında yakalar — işlem sürerken
  araç değişse de yanıt karışmaz; (3) sıcaklık uygulaması artık
  `COMPLETED` sonrası tek okumayla doğrulanır (±0,25 °C tolerans),
  toggle ile aynı dürüstlük; (4) VoiceSheet alt yazısı güncellendi
  ("klima durumu sesli sorulabilir, komut panodan verilir").
- **Son görülme (2026-11-16, 570 test):** Genel Bakış sekmesinin üstünde
  kart: araçla en son iletişimin zamanı ve kanalı — BLE telemetrisi ile
  bulut `updatedAt`'ın **en yenisi** ("1 dakika önce · BLE" / "2 saat
  önce · bulut" / "az önce"). Hiç iletişim yoksa "Araç henüz görülmedi"
  (asla "0 dakika önce" yazılmaz). Core: `LastSeenSummary.make` (en yeni
  kanal seçimi + göreceli zaman kovaları, 2 testli). Tahmin yok: yalnız
  kayıtlı iletişim zamanı söylenir.
- **Şarj hedefi (2026-11-16, 568 test):** Şarj sekmesinde seçim kartı
  (Kapalı / %50 / %80 / %90, VIN başına `toqdas.charging.target.<vin>`).
  Canlı şarj kartında "Hedefe kalan (%80)" satırı; hedef aşılınca
  **oturum başına bir kez** yerel bildirim (anahtar oturum başlangıcını
  içerir: `toqdas.chargingtarget.notified.<vin>.<başlangıç>.<hedef>`,
  günlük `NotificationDedupe` ile). Dürüstlük: uygulama araca durdurma
  komutu göndermez — bildirim ve kart metni bunu açıkça söyler; eksik
  yüzde asla "ulaşıldı" üretmez. Core: `ChargingTargetPolicy` (remaining/
  reached) + `ChargingTargetStore`, 3 testli.
- **12 V trendi (2026-11-16, 565 test):** Sağlık sekmesinde 3 günlük metin
  satırı 7 günlük mini bar grafiği + trend satırına yükseldi. Core'da
  `AuxiliaryBatteryTrend.make`: bilinen günler arasında net fark ±3 puan
  bandının dışına çıkarsa yön üretir (düşüş / kararlı / toparlanıyor),
  tek bilinen gün trend üretmez; eksik günler nil ("bilgi yok" ≠ 0).
  Özet satırı: "−8 puan, düşüş eğilimi · en düşük %72 / en yüksek %80".
  Düşük akü bildirimi (zayıf/kritik, günde bir, time-sensitive kritik)
  aynen korunur — uyarı zaten vardı, bu tur yalnız trend/görsel ekledi.
- **Şarj geçmişi (2026-11-16, 562 test):** tamamlanan her şarj oturumu
  `ChargingHistoryEntry` olarak kayda yazılır (en yeni sonda, en fazla 20):
  başlangıç/bitiş, ilk/son yüzde, oturum sonunda gözlemlenen hız. Hız
  geçmişte oturumun **tamamının** eğiminden gelir (canlı karttaki 15 dk
  penceresinden farklı; kısa oturumlar böylece ölçülebilir). Eski kalıcı
  kayıtlarda `history` anahtarı yoktur; `decodeIfPresent` ile kayıpsız
  açılır. Şarj sekmesinde canlı kartın altında "Şarj geçmişi" kartı: son
  8 oturum (tarih aralığı · süre · %başlangıç → %bitiş · hız), ölçülemeyen
  değer "—". Enerji (kWh) telemetrisi olmadan enerji gösterilmez.
- **Bağlantı sağlığı kartı (2026-11-16, 558 test):** `BleSessionQuality`
  verisi artık ekranda: Komutlar sayfasında "Bağlantı sağlığı · son
  oturumlar" bölümü — kayıtlı oturum sayısı + zayıf (ort. −85 dBm altı)
  oturum sayısı, ortalama süre, ortalama RSSI, en sık kopma nedeni ve son
  6 oturumun satırları (tarih · süre · min/ort/maks RSSI · neden).
  Özetleme `BleSessionQualitySummary.make` ile Core'da, 3 testli; eksik
  veri `—`. 3 konum sinyal testinde bölüm ekran görüntüsüyle kanıtlanır.
- **Yakınlık karar sağlığı (2026-11-16, 555 test):** 22:26–22:28 cihaz
  kanıtı: RSSI −65…−80 zıplarken tek örnek "uzaklaşma" üretti, 5 kilitleme
  akışı başladı; komutlar araca ulaştı (ack) ama kapı açıkken araç
  kilitlemedi, doğrulama 6 sn'lik pencerede hiç imzalı durum görmedi.
  Düzeltmeler: uzaklaşma kararı 2 ardışık örnek ister (yaklaşma hızlı
  kalır); otomatik kilitlemeler arası 60 sn pencere (geofence dahil);
  doğrulama penceresi 35 sn (bir tam imzalı durum dönemi); bildirim
  metni kapı/bagaj açık bağlamını söyler.
- **Bildirim penceresi (2026-11-16, 554 test):** zayıf sinyal döngüsünde
  otomatik komut başarısızlığı dakikalar içinde 5 bildirim üretmişti
  (cihaz kanıtı: 22:26–22:28). `NoticeThrottle`: aynı araç × eylem ×
  başarısızlık türü 10 dakikada en fazla bir bildirim; tekrar sessizce
  kayda geçer, ilk uyarı gecikmez. Onarım kaydı aynı akşam temizlenmiş
  (`repair_cleared` dolaylı: kayıt yok) ve araç doğrulama anahtarını
  sunmaya başlamış.
- **Canlı şarj gözlemi (2026-11-16, 550 test):** Şarj sekmesinde "Canlı şarj
  gözlemi" kartı: doluluk, menzil, geçen süre (uygulama açıkken ölçülür),
  gözlemlenen yüzde hızı (son 15 dk eğim) ve tahmini bitiş. Dürüstlük
  kuralları: kWh/kW telemetrisi olmadığı için enerji gösterilmez; "kalan
  süre" ile "tahmini bitiş" tek hız tabanından üretilir (resmi uygulamadaki
  çelişki kopyalanmaz); eksik veri "—". Oturum `toqdas.charging.session.<vin>`
  ile kalıcıdır; VIN yalnız depolama anahtarında.
- **Sahte onarım düzeltmesi (2026-11-15, 541 test):** zayıf sinyaldeki
  `encryptionTimedOut` hatası eşleşme kaybı sayılmıyordu; kullanıcı anahtar
  sağlamken onarım akışına itiliyordu. Artık sinyal hatasıdır ve otomatik
  yeniden bağlanma dener; yalnız `peerRemovedPairingInformation` ve ATT
  `insufficientAuthentication` onarım gerektirir.
- **Tanı özeti betiği (2026-11-15):** `Scripts/tani-ozet.py` cihazdan plist
  çekip anahtar/onarım, BLE oturum kalitesi, sinyal/kopma ve saat eşitleme
  durumunu tek tabloda özetler; fiziksel doğrulama turlarında kullanılır.
- **Zayıf sinyal dayanıklılığı (2026-11-15, 540 test):**
  - `BleTimeoutPolicy`: RSSI < −85 dBm'de el sıkışma/komut bekleme süresi
    ×1,5 (üst sınır 20 sn); güçlü sinyalde davranış değişmez.
  - `BleSessionQuality` (`toqdas.ble.session.v1`): oturum süresi ve
    min/ort/maks RSSI + kopma nedeni; konum karşılaştırması için.
- **Saat eşitleme tanısı (2026-11-15, 533 test):**
  - Telefon `WCSession` “Watch app is not installed.” hatası verdiğinde bunu
    yalnız konsola yazıyordu; saat verisi sessizce donuyordu. Artık son
    gönderim sonucu `toqdas.watch.sync.v1`e yazılır (`installed/paired/
    reachable` dahil).
  - Saat uygulaması öne geldiğinde bayat veriyi otomatik tazeler; saat
    complication'ı 1 saatten eski veriyi “Eski veri” olarak işaretler
    (`WatchSnapshot.isStale`).
- **Bayat onarım kaydı (2026-11-15, 529 test):**
  - Başarılı kimlik doğrulamada (`ready`) `PairingRepairStore` temizlenir;
    önceden kayıt silinmediği için her açılışta `repair_restored` oluyordu.
- **Onarımın kendisi kilitleniyordu (2026-11-14, 529 test):**
  - `checkKeyIdentity` açık onarımda da eski parmak izini görüp duruyordu;
    “Yeniden eşleştir” hiçbir zaman sunucuya ulaşmıyordu. Artık
    `blocksAuthentication(isExplicitRepair:)` ile açık onarım geçer, yeni
    parmak izi sertifika alındıktan sonra yazılır.
  - `Core/KeyAudit` son 20 anahtar olayını sebep/status ile saklar.
- **Anahtar sürekliliği kök nedeni (2026-11-14, 526 test):**
  - `Keychain` anahtarı `WhenUnlocked` ile saklanıyordu; arka planda kilitli
    cihazda okunamayınca sessizce yeniden üretiliyor ve araç eşleşmesi
    bozuluyordu. Artık `AfterFirstUnlock` + yalnız `errSecItemNotFound`da
    üretim (`PhoneKeyStore.canGenerate`); kilitli durum onarım açmaz.
- **Dijital anahtar kalıcılığı (2026-11-13, 520 test):**
  - `Core/CertificateProvenance` (saf, testli): sertifikanın kaynağı
    (`reused` / `refreshed` / `issued`) VIN başına kaydedilir; pano bunu
    “yeniden kullanılıyor · N gün geçerli” diye gösterir.
  - `CertificateCache` doğrulama hatasında kaydı silmiyor; yalnız kesin
    süresi dolmuşsa siliyor. Anahtar kaybı `KeyIdentity.missing` ile onarım
    akışına gider — sessiz yeni anahtar/yeniden eşleştirme yok.
- **Sahiplik çakışması tanısı (2026-11-13, 516 test, `c1f27d8`):**
  - `Core/ClaimResponseShape` (saf, testli): `ClaimCarToUser` yanıtının
    yalnız alan adları/tip/uzunlukları kaydedilir (`toqdas.claim.shape.v1`);
    değer yazılmaz. Sunucu başka telefonun kimliğini paylaşmadığı için uyarı
    metni de bunu açıkça söyler (taşı / davet iste).
- **İyileştirme turu (2026-11-12, 435 test):**
  - Eşleştirme bekleme UI'da açık: `BleConnection.State.isPairingWait`
    (yalnız `vehicleKeyMissing`), Dashboard başlığı
    "Araç eşleştirmesi bekleniyor · araç ekranından eşleştirmeyi başlat",
    durum rengi turuncu (`ea81893`).
  - Zayıf sinyalde BLE geri çekilme: son RSSI < −85 dBm → temel gecikme
    ×2, üst sınır 30 sn; güçlü/bilinmeyen sinyalde davranış birebir.
    Android .57'nin "taze uygun reklam + backoff" kapısı felsefesinin
    iOS karşılığı; doğrudan yeniden bağlanma kısayolu değişmedi (`68994b0`).
  - Saat snapshot darboğazı: `Core/WatchSnapshotThrottle` — gösterim
    değişimi 30 sn minimum aralığa sıkıştırılır; önemli alan (ready/
    bleState/komut sonucu/yeniden bağlanma) anında geçer; zaman damgaları
    parmak izine girmez (`e1d344a`).
  - Tanı günlüğü paylaşımı: `BLEDiagnosticLogExporter.text` (zaman
    damgalı olaylar; boş günlükte "kayıt yok") + CommandView ShareLink (`85e69e4`).
  - Widget 12 V son 7 gün mini-grafik: `AuxiliaryBatteryHistory.numericValues`
    + `VehicleWidgetSnapshot.auxiliaryHistoryPercents` (VIN'siz, eski
    önbellek uyumlu) + medium boyutta 7 çubuk; eksik gün çukur/"bilgi yok",
    gerçek 0 korunur (`cbacb1b`).
- `BLEDiagnosticStore` … `BLECommandRejection` ve `BLECommandReceipt` aşamaları eklendi.
- `VehicleTelemetry` için tip veri kümesi eklendi; görev hatası/TODO kalıntısı
  temizlendi.
- Saat komut sonucuna kısa dokunsal geri bildirim veriyor; "forwarded" bildirim
  tipindedir ve başarılı komut demek değildir.
- `ProximityCycleGuard` (Android 1.0.24.57 paritesi): uzak↔geri-yaklaşma
  döngüsünde açma tek biletle sınırlı; eski/geçersiz ölçüm veya başarısız
  gönderim bileti iptal eder ve 30 sn guard devreye girer. Karar çekirdeği
  birim testli; komutun sonucu imzalı telemetriyle doğrulanmaya devam eder.
- `ProximityLatencyMeter` (Android .57 latency paritesi): yaklaşma karar
  gecikmesi yalnızca yerel ölçülebilir kanıtlarla raporlanır — döngü tabanı
  (etkinleştirme/uzaklaşma teyidi/fresh cycle) → karar süresi (ms), pencere
  örnek sayısı ve profilin beklenen karar penceresi (gerekli örnek × RSSI
  aralığı). Ölçüm tanı ekranında "Yaklaşma kararı" satırında görünür; araç
  tarafı ACK süresi ölçülmez, arka plan gecikmesi raporlanmaz. Eksik ölçüm
  "—" kalır, asla 0 yazılmaz.
- Oto kilit sesli komutu (Android `set_automatic_lock` paritesi):
  `VoiceCommand.automaticLock(on:)` + deterministik algılama
  ("oto/otomatik/otomotik" × "kil-" önekli kelime, ekli biçimler dahil) +
  politika onay kapısı. Araç komutu göndermez; yakınlık otomasyonu anahtarını
  onaylı olarak yönetir. Bağlantı/tazelik kapısına takılmaz, çünkü hedefi
  cihaz tarafı bir ayardır.
- Boot-parite arka plan (Android .57 parite, iOS kısıtlarıyla kısmi):
  iOS'ta boot alıcısı yoktur; karşılık CBCentralManager state restoration
  (restore identifier `com.toqdas.ios.central`). `BleRestorePlan` restore
  olayında üç yol verir — sistem bağlı oturum verdimiyse `resumeSession`
  (CoreBluetooth garantisiyle `connect(connected)` → `didConnect` akışı,
  el sıkışma sıfırdan değil), kopuksa mevcut `reconnect` politikası, yoksa
  normal başlangıç. Plan asla komut göndermez (`sendsCommand` invariant
  testli). Sınır: kullanıcı uygulamayı sweep-kill ile kapatırsa iOS
  restoration teslim etmez; Android otomatik servis başlangıcı bu senaryoda
  daha güçlüdür. Fiziksel araçla doğrulama bekliyor.
- Widget'a son komut sonucu: `VehicleCommandStatus` (etiket + zaman +
  doğrulama durumu) app group'ta VIN'siz tutulur; orta boyut widget'ta
  "Son komut: … · doğrulama yok/doğrulandı" satırı. "Başarılı" nitelemesi
  yazılmaz; kesinlik yalnız imzalı telemetri doğrulamasıdır. 24 saatten eski
  kayıt ekranda çıkarılmaz.
- Uygun aralık otomatik önerisi: `ProximityAutoCalibrationSuggester`
  dijital anahtar bağlı GATT RSSI akışında kararlı yakın/uzak kümeleri
  (5 örnek, ±2 dBm, fark ≥14 dBm) gözleyip **öneri** bildirimini kaldırır
  ("Uygun yakınlık aralığı algılandı", VIN'siz). Öneri kalibrasyonu yazmaz,
  otomasyonu açmaz; onay hâlâ yakınlık kartındaki ölçüm düğmelerinden
  geçer.
- 12 V akü günlük geçmişi (Android `aux_history` paritesi):
  `AuxiliaryBatteryHistory` — gün başına en güncel ölçüm, 30 gün üst sınırı,
  eksik gün `—` (asla 0 değil; gerçek 0 `%0`), geriye yazım engellenir.
  Sağlık kartında "Son 3 gün (12 V)" satırı; kayıt yalnız taze telemetriyle.
- Saatte son komut sonucu: `WatchSnapshot.lastCommandText` — metin iPhone
  tarafında kurulur (etiket · doğrulama · saat), 24 saatten eski kayıt
  widget kuralıyla süzülür; saat yalnız gösterir, VIN/içerik ayrıntısı geçmez.
- Sesli oto kilit süre tercihi (Android `set_automatic_lock.autoOff*`
  paritesi): `VoiceCommand.autoOff(enabled:minutes:)` — "oto kilit 20
  dakika" süre (1–1440, dışı reddedilir), "oto kilit süresiz / sayacı
  kapat" sayaç kapama, "sayaç aç" açma. Yalnız belirtilen alan değişir;
  ana "oto kilit aç/kapat" davranışı korunur. Sayaç yerel tercihtir,
  araç komutu gönderilmez; sayaç kapalıysa durum dürüstçe söylenir.
- EPDK sesli `nearby_stations` veri hattı tamamlandı: kayıtlı katalog
  özeti (istasyon sayısı + saat) sesli yanıtta gerçek veriyle söylenir,
  tazeleme arka planda rate-limit'e saygılı `load()` ile tetiklenir.
  Telefon konumu paylaşılmadığı için mesafe sıralaması yapılmaz ve bu
  dürüstçe söylenir (Android 5 km açma davranışı taşınmaz).
- 12 V akü düşük uyarısı: `AuxiliaryBatteryPolicy` (kritik ≤%25, uyarı
  ≤%40) eksik/geçersiz telemetride uyarı üretmez ("bilgi yok" ≠ uyarı;
  gerçek 0 kritiktir). `VehicleHealthCard` kartın en üstünde renkli,
  kenarlıklı ve erişilebilir bandı gösterir; sesli `auxiliaryBattery`
  yanıtı düşük değerlerde "Dikkat/Not" tonu verir. iPhone yerel bildirimi:
  yalnız taze telemetri güncellemesinde, ciddiyet başına günde bir kez,
  VIN'siz anahtar/metin (lastik uyarısı deseni).
- EPDK istasyonu sesli sorgusu (Android `nearby_stations` paritesi):
  `VoiceCommand.nearbyStations` salt okunur niyeti; "istasyon bul / ara /
  yakındaki istasyonlar" ayrıştırılır, politika EPDK sekmesine yönlendirir.
  Ses verisi okumalı istasyon listesi veri hattına bağlı değildir; sonraki
  adım öneri.)
- UI testleri: `-uiTestFixture` ile ağa çıkmadan pano açılabilir; komutun kapalı
  olma nedeni test edilir.
- Üst araç kartı semantik fonlara geçirildi; Dynamic Type ile birlikte ölçeklenir.
- `CloudSnapshotStore`: bulut telemetrisi VIN bazlı önbelleğe alındı; soğuk
  başlangıçta pano son bilinen değerle açılır, araç seçimi ve çıkışta
  karışma/sızıntı önlenir. `KeyValueStore` protokolü `GaragePreferences`
  içinden `Core/KeyValueStore.swift`'e taşındı.
- Önbellekten açılan pano, üst kartta veri yaşını dolaysız yazar
  (`Güncellendi HH:mm · N dk/sa önce`); 5 dakikanın altındaysa yalnız saat
  görünür ve yan etkiler (lastik uyarısı, sürüş kaydı) eski değerle
  tetiklenmez.
- Widget tazelik rozeti test edilebilir `VehicleWidgetSnapshot.freshnessText`
  hesaplamasına taşındı: BLE yoksa bulut telemetri zamanı (`Bulut · HH:mm`)
  gösterilir; canlılık iddiası yalnız canlı BLE için korunur.
- `BLETransport` merkezi (central) yaşam döngüsü ayrıldı; `BleConnection`
  hâlâ servis/karakteristik keşfi, yazma kuyruğu ve el sıkışmayı taşıyor.
- `BLETransporting` protokolü ve `FakeBLETransport` ile radyo/tarama testleri
  eklendi.
- `BLEIssue` eklendi; `BleConnection.State.failed` artık serbest metin yerine
  tipli hata nedeni taşıyor.
- `BLECommandReceipt` eklendi; komutlar `sıraya alındı → gönderildi → araç
  aldı → doğrulandı/başarısız` aşamalarıyla izleniyor ve `CommandView` içinde
  gösteriliyor.
- Son 20 komut `BLECommandHistoryStore` ile kalıcı saklanıyor; geçmiş
  `CommandView` içinden görüntülenip temizlenebiliyor.
- `CertificateLifecycle` eklendi; sertifika son 24 saatte yenilenmeye çalışılıyor,
  yenileme başarısız olursa süresi dolana kadar önbellekteki sertifika kullanılıyor.
  `CommandView` kalan süreyi ve yenileme gereksinimini gösteriyor.
- `NetworkRetryPolicy` eklendi; GET/HEAD isteklerinde geçici ağ hataları ve
  5xx/429 için sınırlı geri çekilme uygulanıyor. 401 alınan yetkili istek bir kez
  oturum yenilemesiyle tekrarlanıyor; POST komutları ağ hatasında otomatik
  tekrarlanmıyor.
- Saat, son gösterim anlık görüntüsünü kendi `UserDefaults` alanında saklıyor;
  iPhone erişilemezken son bilinen değerleri yaşıyla gösteriyor. Komutlar hâlâ
  iPhone bağlantısı ve taze telemetri gerektiriyor.
- Erişilebilirlik: alt sekmeler seçili durumu VoiceOver'a bildiriyor, sertifika
  durumu etiket/değer olarak okunuyor ve sesli asistan nabzı Hareketi Azalt
  açıkken duruyor. Ayrıntılar `Docs/Erisilebilirlik.md` içinde.
- Lokalizasyon: kullanıcıya gösterilen ondalıklar `TurkishFormat.decimal` ile
  virgüllü, binlikler noktalı; `ExperienceFormat` ve kritik kartlar aynı kaynağı
  kullanıyor. Teknik/protokol biçimleri `en_US_POSIX` olarak ayrıldı. Ayrıntılar
  `Docs/Lokalizasyon.md` içinde.
- Gizlilik: uygulama, watch ve widget hedeflerine `PrivacyInfo.xcprivacy`
  eklendi; UserDefaults ve dosya zaman damgası erişim gerekçeleri bildirildi.
  Veri akışı ve App Store öncesi eksikler `Docs/Gizlilik.md` içinde.
- Faz 1 (Android .57.18 parite): `BleStatusWatchdog` (Android `j4` paritesi —
  15 sn eşikler, `stale_telemetry_reconnect`/`first_status_timeout`, 3 deneme
  eşiği; etiketler gösterim/günlük amaçlı, davranış `BleReconnectPolicy`'de)
  + 6 test. Watch P1.1: 12 V metnine `AuxiliaryBatteryPolicy` renk bandı
  (≤%25 kırmızı, ≤%40 turuncu; widget ile aynı kural). P1.3: kritik 12 V
  bildirimine `interruptionLevel = .timeSensitive` (saatte haptikle düşer;
  Critical Alerts yetkisi yok). Karşılaştırma raporu `Docs/Parite-Android57.18-iOS.md`.
  Test sayısı 369 → 375. Gözcü `BleLinkCoordinator`'a bağlandı (`ble_watchdog ·`
  önekiyle tanı günlüğü; etiket değiştiğinde yazar, bağlantı eylemi tetiklemez).
- 12 V metin formatı tek kaynağa alındı (`AuxiliaryBatteryPolicy.percentText`
  — geçersiz değer `nil`, çağıran "—"/"—%" gösterir); saat, widget, pano ve
  uygulama menü çubuğu aynı yardımcıyı kullanır (+2 test). UserDefaults
  anahtar biçimleri `App/StorageKeys.swift`'te tek kaynağa alındı.
- Test edilebilirlik temeli: `SessionStoring` protokolü (SessionStore
  Keychain'den arayüze ayrıldı) ve `ToggAPIClient` protokolü eklendi;
  `ToggAPI`'nin init'ine URLSession/SessionStore enjeksiyonu açıldı
  (varsayılanlar üretim davranışını korur); `BleLinkCoordinator` api
  bağımlılığı protokole genişletildi. Not: App katmanı birim testleri için
  Xcode birim test hedefi gerekli (Tests/ yalnız Core SPM) — ayrı iş.
- DashboardView bölünmesi Faz A: 8 alt tip saf taşıma ile kendi dosyasına
  alındı (`App/Dashboard/`: Header, VehicleVisualCard, QuickActionButton,
  PremiumControlsSection, ClimateCard, VehicleHealthCard, BLESetupGuideSheet;
  `App/LoginView.swift`). Yalnız erişim düzeyi açıldı (`private struct` →
  `struct`, `DashboardCommand` dahil); davranış/yeniden adlandırma yok.
  `DashboardView.swift` 3592 → 2567 satır. Faz B (ViewModel'e iş mantığı)
  ayrı oturumda.
- Faz B1 (iş mantığı Core'a): `NotificationDedupe` (anahtar başına günde
  bir kez bildirim; aux/tire/bakım tek kaynağı) ve
  `AuxiliaryBatteryHistoryStore` (12 V geçmiş kalıcılığı, `KeyValueStore`
  enjeksiyonu) eklendi (+10 test, bozuk veri boş geçmiş döner);
  `KeyValueStore` protokolüne `object/integer/data` üyeleri eklendi.
  DashboardView ve MaintenanceNotifier yeni tiplere bağlandı; davranış
  birebir korundu (bakımda kayıt yalnız başarılı gönderimde). Test 377 → 387.
- Faz B2 (kalıcılık store'ları): `ProximitySettings` (profil, yakın/uzak
  kalibrasyon, oto-kapanma tercihi/deadline kalıcılığı; anahtar biçimleri
  tek kaynak, byte-identical) ve `ClimateSettings` (klima hedef sıcaklık
  kalıcılığı, `hasTarget` ile "ilk hedef alma" kararı korunur) Core'a
  alındı (+9 test); `StorageKeys` ince delegasyona çevrildi;
  DashboardView'daki tüm yakınlık/klima `UserDefaults` çağrıları yeni
  store'lara bağlandı. Açma/kapama (`enabled`) durumu `GaragePreferences`
  kaynağında kaldı. Test 387 → 396.
- Faz B3 (gönderim birleşimi): `NotificationPoster` — yerel bildirim
  gönderiminin tek noktası. `NotificationPosting` protokolü (testte sahte
  merkez) + `SystemNotificationPoster` (UNUserNotificationCenter
  sarmalayıcı) + `post(draft:using:onSuccess:)` (içerik kurulumu,
  gönderim, yalnız başarıda geri çağrı). 4 gönderim noktası bağlandı:
  DashboardView (tire/12 V/kalibrasyon önerisi), `MaintenanceNotifier`
  (kayıt yalnız başarıda korunur), `ChargingBudgetNotifier` (izin akışı
  korunur). Bildirim kararı çağırandadır; +5 test. Test 396 → 401.
- Tanı: ham sürüş modu değeri (`vehicleInfo · driveMode=...`) tanıya
  yazıldı; sürüş modu uyuşmazlığı tanı ekranından doğrulanabilir.
- keyDiscovery Faz D1 (Core politikası): `KeyDiscoveryPolicy` +
  `KeyDiscoveryCandidate` — Android `.57.18` `Q4.java` kuralları saf
  mantık olarak taşındı: VIN-ad eşleşmesi ("MY T-SAS <son 8/son 6/tam
  VIN>", [A-HJ-NPR-Z0-9]{17}), aday geçerliliği ve öncelik metinleri
  (VIN-ad > kayıtlı adres > servis > genel ad), seçim tazeliği (tarama
  ≤12 sn, seçim penceresi 120 sn, 128 ham/32 geçerli aday limiti) ve
  K00–K07 durum kodları. Aday seçimi **araç komutu göndermez**
  (Android invariant'ı). +10 test. Test 401 → 411.
- keyDiscovery Faz D2 (aday seçim akışı): `KeyDiscoverySession` (saf
  oturum durumu: katalog, 12 sn tarama penceresi, 120 sn seçim
  tazeliği, 128 ham/32 geçerli limit, K-kodları; tazelik tarama
  bitişini izler) + `KeyDiscoveryView` (SwiftUI sheet: Tara → geçerli
  aday listesi → Seç → Bağlan). `KeyDiscoveryScanner` ayrı
  `CBCentralManager` örneğiyle gözlem toplar, `BleConnection`'ın
  otomatik bağlantı akışına dokunmaz; "Bağlan" mevcut el sıkışma/
  anahtar öğrenme akışını başlatır (`connect(to:)`). DashboardView'a
  "Cihaz ortamında aday seç" girişi eklendi (bağlantı yokken görünür);
  `BleConnection.lastConnectedPeripheralIdentifier` salt-okunur açıldı
  (kayıtlı adres kanıtı). +9 test. Test 411 → 420.
- Proje değerlendirme raporu: `Docs/Proje-Degerlendirme-2026-11.md`
  (mimari/kalite/test/arayüz; App katmanı test ve DashboardView bölünmesi
  sonraki işler).

- **UI test kapsamı genişletildi (2026-11-13, 19 UI testi):**
  `UITests/ToqdasUITestSupport.swift` ortak altyapı (fixture başlatma,
  etiket/türden bağımsız sorgu, koşula bağlı kaydırma; sabit `sleep` yok)
  + dört yeni dosya: `ToqdasFlowTests` (sekmeler, telemetri, sağlık kartı,
  Trugo), `ToqdasCommandTests` (komut kapısı, devre dışı komut, menü),
  `ToqdasGuideTests` (senaryolar rehberi + kalibrasyon sheet'i),
  `ToqdasAccessibilityTests` (44 pt, VoiceOver, XXXL Dynamic Type).
  App tarafında yalnız erişilebilirlik kimlikleri eklendi
  (`tab.*`, `header.menu`, `guide.close`, `proximity.*`). UI testinin
  bulduğu gerçek eksik: sekme düğmelerinin erişilebilirlik çerçevesi
  34,7 pt'ti — 44 pt `minHeight` içerik VStack'inde kalıyordu, düğmeye
  taşındı. Koşu: 19/19 yeşil, 190 sn. Birim test sayısı değişmedi.

- **Navigasyon dumanı (2026-11-13, 27 UI testi):** `ToqdasNavigationTests`
  (8 test) — Sesli Asistan, BLE kurulum rehberi, Aday Seç, Bluetooth
  taraması sheet'leri; Araç detayı, Servis kartı, Seyahatname ve
  Bildirimler & Destek ekranları açılıp panoya dönülüyor. Ağ/oturum yok;
  ekranlar dürüst boş/hata durumunda açılıyor. Yüzey kapsamı 8/17 → 16/17
  (%94); tek eksik `ChargingStationsView`. Koşu: 27/27 yeşil.

- **Erişilebilirlik denetimi (2026-11-13, 31 UI testi):** `ToqdasAccessibilityAuditTests`
  (4 test) — Genel Bakış, üç sekme, rehber ve komut sheet'inde
  `performAccessibilityAudit` (dokunma hedefi, etiket, kırpılma, trait).
  Keşif koşusu 165 bulgu verdi; 17'si düzeltildi (4 düğme 44 pt, 5
  dekoratif ikon gizlendi, menüye "Menü" etiketi, araç başlığı 2 satır,
  komut sheet'i satır içi başlık). Dynamic Type (xxxLarge sınırı) ve
  kontrast (tokenlar elle AA üstü) bilinçli kapsam dışı. Koşu: 31/31.

- **Görünüm tercihleri ve oturum (2026-11-13, 35 UI testi):**
  `ToqdasSettingsTests` (4) — tema (Okyanus) ve düzen (Minimal) seçimi
  yeniden başlatmada korunuyor; Minimal düzende yakınlık kartı gizli;
  menüde VoiceOver tek tema/tek düzen seçili; "Çıkış yap" giriş ekranına
  dönüyor. Test izolasyonu için `-uiTestResetLook` (yalnız DEBUG) tema ve
  düzen anahtarlarını temizler. Koşu: 35/35.

- **CI (2026-11-13):** `.github/workflows/ci.yml` — macOS runner'da
  `swift test` ve duman UI testleri (Smoke + Flow) her push/PR'da;
  gecelik `03:00 UTC` tam 35 testlik paket. Simülatör dinamik seçilir
  (en yeni iOS + iPhone, yoksa oluşturulur), imzalama kapalı, hata
  durumunda `.xcresult` artifact.

- **CI ilk koşu düzeltmesi (2026-11-13, 521 birim testi):** CI UTC saat
  diliminde `TurkishFormatTests.testDateFormatUsesTurkishMonthNames`
  kırılıyordu (beklenen "29 Eki 23:45", alınan "29 Eki 20:45").
  `TurkishFormat.date`'a isteğe bağlı `timeZone` parametresi eklendi
  (varsayılan `.current`, üretim davranışı aynı); test açık saat dilimi
  veriyor ve saat diliminden bağımsız yeni bir test eklendi.
  `TZ=UTC swift test`: 521/521.

- **Ekran nesneleri / POM (2026-11-14, 35 UI testi):**
  `UITests/Screens/ToqdasScreens.swift` — `DashboardScreen`, `MenuSheet`,
  `CommandSheet`, `ScenarioGuideSheet`, `CalibrationSheet`, `LoginScreen`.
  Erişilebilirlik seçicileri tek yerde; testler davranış ve iddia taşır,
  ekran nesneleri iddia içermez. Test iddiaları değişmedi. Koşu: 35/35,
  374 sn.

- **Bütçe ve bakım kartı testleri (2026-11-14, 43 UI testi):**
  `UITests/ToqdasStoreSeedTests.swift` — `-uiTestResetStores` (boş bütçe)
  ve `-uiTestSeedStores` (limit 5.000 ₺, harcama 4.250 ₺; bakım 1.500 km
  ve 900 km) DEBUG hook'ları; her açılışta store'lar temizlenip sabit
  değerler yazıldığı için test sırası sonucu değiştirmez. Boş/dolu bütçe,
  yaklaşan ve gecikmiş bakım olmak üzere 4 test. Tam paket: 43/43 UI,
  529 birim.

- **Düzen varyantları + şarj hesaplayıcı testleri (2026-11-14, 39 UI testi):**
  `UITests/ToqdasLayoutTests.swift` — Sportif düzende kart sırası
  (hızlı kontroller < BLE kartı) ve cam/güvenlik bölümü; Teknik düzende
  "Canlı BLE Tanısı" bloğunun yakınlık kartından önce gelmesi; şarj
  hesaplayıcıda hedef doluluk değişiminin enerji/ücreti yenilemesi;
  varsayım ve "araçta şarj başlatmaz" notu. Hesaplayıcıya erişilebilirlik
  kimlikleri (`calculator.startPercent`, `calculator.targetPercent`,
  `calculator.energy`, `calculator.cost`) ve kaydırıcı etiketleri eklendi;
  üretim davranışı değişmedi. Tam paket: 39/39 UI, 521 birim.

- **Fonksiyon envanteri (2026-11-14):** `Docs/FonksiyonEnvanteri.md` —
  F01–F45 işlev, 8 sistem yüzeyi (widget/watch/Siri/kısayol/deep link),
  A/B/C sınıflandırması ve ilk 10 öncelikli boşluk. Yöntem: statik tarama
  + 35 UI testinin simülatör koşuları. Uygulama ve testler değişmedi.

- **Uzaklaşınca kilitleme bileti (2026-11-17, 588 test):** Kök neden
  kanıtlandı: araç, dijital anahtar (telefon) **güçlü sinyaldeyken**
  kilit komutunu onaylıyor (ack) ama uygulamıyor. Ölçüm (aynı gün,
  araç başı): yakın RSSI −57…−84 aralığında **7/7 kilit reddi**
  (`automatic_command_failed · kilit durumu komut sonrasında
  doğrulanamadı`), uzak −88…−97 aralığında **6/6 uygulama** (imzalı
  telemetriyle doğrulandı). Protokol tarafı temiz: kilit(1)/aç(2)
  paketleri birebir aynı yapı, tek fark kod byte'ı; açma yakında da
  uygulanıyor → ayrım aracın kendi güvenlik kararı. Alternatif çözüm
  `Core/DeferredLockTicket`: kullanıcı panodaki "Uzaklaşınca kilitle"
  düğmesiyle bilet kurar; RSSI ≤ `BleReconnectPolicy.weakSignalThreshold`
  (−85), telemetri ≤15 sn taze ve `isLocked == false` olduğunda **tek**
  `ble.lock()` gönderilir; 10 dk üst sınır, `isLocked == true`/süre
  dolumu/60 sn içinde başka kaynak kilidi → iptal. `AutomaticCommandLedger`
  kaynağına `deferredLock` eklendi (çift komut koruması). Karar saf ve
  testli (9 yeni test).


- Sıfırdan rewrite yok; strangler pattern benzeri kademeli geçiş.
- Bir seferde tek sınır: önce BLE, sonra DI, sonra UI.
- Davranış değişikliği ile refactor aynı PR'da karıştırılmaz.
- Güvenlik kapıları UI'da değil, domain/servis katmanında kalır.
- Anahtar, token ve VIN gibi hassas veriler loglanmaz.
