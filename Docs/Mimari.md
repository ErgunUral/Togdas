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

## 9. İlkeler

- Sıfırdan rewrite yok; strangler pattern benzeri kademeli geçiş.
- Bir seferde tek sınır: önce BLE, sonra DI, sonra UI.
- Davranış değişikliği ile refactor aynı PR'da karıştırılmaz.
- Güvenlik kapıları UI'da değil, domain/servis katmanında kalır.
- Anahtar, token ve VIN gibi hassas veriler loglanmaz.
