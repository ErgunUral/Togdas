# Toqdas iOS + watchOS — development baseline

Native SwiftUI project based on the API contract in `../Garajm`.
This is an independent implementation, not a completed port of the Android app.

## Open and build

Open `Toqdas.xcodeproj` in Xcode. Schemes: `Toqdas`, `ToqdasWatch`.
Minimum targets: iOS 16, watchOS 9. Select your signing team for device builds;
use identifiers registered to your team for distribution and update the Watch
companion identifier to match if you change the iOS bundle identifier.

```sh
swift test
xcodebuild -project Toqdas.xcodeproj -scheme Toqdas -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Toqdas.xcodeproj -scheme ToqdasWatch -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

`generate_project.rb` regenerates the Xcode project using the `xcodeproj` Ruby gem.
It overwrites project settings; preserve manual project changes before running it.

## Implemented

- Togg Trumore tarzı koyu tema dashboard: başlık, canlı telemetri şeridi, batarya/menzil
  kartı, alt sekmeler (Genel Bakış, İklimlendirme, Trugo Şarj, Araç Durumu), hızlı işlemler,
  konfor/güvenlik kartları, şarj limiti ve sağlık kartı.
- iPhone dashboard color themes: Togg Gece, Okyanus and Grafit/Amber; the choice is stored
  locally. All palettes remain dark to preserve contrast across existing white card text.
- Çoklu araç desteği: garajdaki araçlar arasında geçiş; seçim `UserDefaults` ile kalıcıdır.
- Sürüş & şarj analizi: `DriveExperience` uçlarından son 30 gün, önceki dönem,
  önceki takvim ayı ve tüm zamanlar özeti; topluluk karşılaştırması; son yolculuk ve
  son şarj kartları; haftalık/aylık/yıllık yolculuk ve şarj listeleri; dönem grafiği,
  sayfalama, kayıt ayrıntıları ve ham yanıt görünümü. Şarj ayrıntısında ortalama güç
  hesaplanır; sunucunun döndürdüğü ücret "ödeme/fatura olarak doğrulanmadı" notuyla
  gösterilir. Yolculuk verim yüzdesi ile ekonomi puanı ayrı alanlardır.
  Konum/adres metinleri yalnız sunucu yanıtından okunur; cihazda adres üretilmez.
- Şarj hesaplama: başlangıç/hedef doluluk, varsayılan kapasite (88,5 kWh) ve birim
  fiyat (10 ₺/kWh) ile tahmini enerji ve ücret. Kapasite/fiyat varsayımdır; şarj
  kayıpları hesaba katılmaz ve araçta şarj başlatmaz.
- BLE el sıkışma zaman aşımı ve bağlantı sinyali (RSSI) göstergesi.
- Araç sağlığı: batarya, menzil, 12 V akü, şarj durumu, kilometre, dış sıcaklık,
  lastik basıncı (kPa'dan PSI'ye) ve lastik sıcaklığı `VehicleInfo` API'sinden
  30 saniyede bir yenilenir; son güncelleme zamanı gösterilir. Tüketim alanı
  doğrulanmış servis yanıtında bulunmadığı için önizlemedir.
- Bildirimler & Destek Merkezi: superapp `Notifications/all`, `Tickets/Tur` ve
  `Package/Tur/subscriptions` uçları; okunmamış işareti, durum/tarih ve destek
  talebi notlarına geçiş. Yanıt alanları esnek eşlenir.
- Yakındaki şarj istasyonları: MapKit/Apple Maps aramasıyla Trugo ve EV şarj noktaları,
  harita, mesafe, yol tarifi ve konum izni yönetimi. Veri kaynağı Togg servisi değildir.
- İklimlendirme: Togg uzaktan kontrol gRPC servisinden `GetClimateControlStatus` ile
  açık/kapalı ve hedef sıcaklık okunur; `SendClimateControlCommand` ile 16–30 °C arası
  hedefle açma/kapatma ve sıcaklık uygulama yapılır. Her komuttan sonra araç durumu
  yeniden okunur; durum alınamazsa komut gönderilmez. Hedef sıcaklık VIN bazında saklanır.
- Browser-based OAuth authorization-code/PKCE flow with callback validation.
- Device-only Keychain session storage; refresh-token handling.
- Vehicle-list and vehicle-detail requests; details currently display formatted
  service JSON rather than a normalized dashboard.
- Foreground, service-filtered BLE discovery on iPhone and Watch, bounded to 20 seconds.
- WatchConnectivity application-context synchronization of vehicle names and timestamp.
  The snapshot is not live vehicle telemetry. No credentials or key material are transferred.
- Unit tests: RFC 7636 vector, callback rejection cases, vehicle parsing and form encoding.
- Shared BLE protocol framing on both targets: certificate VIN/device-key binding,
  P-256 key frames, challenge parsing, raw/DER signature conversion, outgoing
  certificate/phone-proof/command frames, signed vehicle proof and telemetry verification.
  RFC 6979 known-answer, framing and tampering tests pass. Certificate binding is not
  issuer/expiry verification.
- Per-VIN P-256 phone key generated in the Keychain (private key never exported).
- Smart-access certificate fetch/create with owner body and phone-key binding.
- BLE session state machine: certificate presentation, challenge signing, car-proof
  verification, READY gate and authenticated lock/unlock/trunk/window/drive frames.
  Window commands use the official windowsOpen=6/windowsClose=7 command codes and
  signed nonce flow; the vehicle's window position is not exposed by verified telemetry.
  Every lock action sends windowsClose first, then sends lock only after the vehicle
  acknowledges the window command; this does not prove the glass physically closed.
  After fresh signed telemetry confirms the locked state, the iPhone plays two short
  confirmation tones (ambient audio; respects the silent switch).
- The exact outgoing handshake order and the bytes the vehicle expects in PHONE_PROOF
  are inferred from `Garajm` protocol constants; they have not been confirmed against
  a live vehicle. Command timestamps use the vehicle's time characteristic when available.

## Integration boundaries

The existing Android `super-app` client ID, callback and production endpoints are
used as integration inputs. Acceptance of this OAuth flow on iOS has not been tested
or approved by the service operator. No production requests were made during setup.
Application signatures and successful builds do not demonstrate vehicle compatibility.

The Watch receives the latest available display snapshot when the system delivers
it. It does not issue commands. Scanning does not identify an authorized vehicle:
advertisement names, service UUIDs and RSSI are not authentication evidence.

## Next implementation milestones

1. Verify iOS OAuth client/redirect acceptance and real response formats.
2. Complete BLE framing (outgoing handshake/commands) and establish trusted vehicle
   key provenance. Incoming P-256 proof verification and known-answer tests are implemented.
3. Implement GATT discovery, characteristic subscription, write-size negotiation,
   authentication state machine, cancellation and timeout recovery on iPhone.
4. Verify separate Watch public-key/certificate registration without replacing the
   existing phone relationship; private keys remain on their generating device.
5. Implement foreground Watch lock/unlock with explicit desired state, command ID,
   expiry, acknowledgement and fresh lock-state readback. Never queue stale commands
   using deferred WatchConnectivity delivery.
6. Add proximity evaluation in observation-only mode: filtered RSSI, hysteresis,
   dwell time, stale sample rejection and suppression of repeated decisions.
7. Evaluate background discovery/reconnection on physical supported watches;
   enable appropriate capabilities only with this implementation. Handle BLE runtime
   limit errors and fall back to an explicit foreground action.
8. Gate any automation on authenticated identity, fresh vehicle state and supported
   vehicle-state signals. Connection loss alone must never imply a lock command.

Watch and phone must coordinate command ownership so both do not issue conflicting
operations. WatchConnectivity reachability is not proof of proximity to the vehicle.
RSSI cannot prove distance or prevent relay attacks; do not present this prototype as
equivalent to Apple Wallet/Car Key or UWB-based passive entry.

Apple background BLE reference:
https://developer.apple.com/videos/play/wwdc2022/10135/
The historical numeric quotas in that session are not assumed to be constants on
new watchOS versions; observe documented runtime errors and test target versions.

## Verification so far

- iOS Simulator build: passed (Xcode 27.1).
- watchOS Simulator build: passed (Xcode 27.1).
- Thirty-three Swift package tests: passed (Drive Experience şema, biçimlendirme,
  sayfalama ve ayrıntı testleri; şarj hesaplama sınırları).
- Dashboard UI: built and launched on the physical iPhone. Veri gelmeyen alanlar
  (ortalama tüketim, şarj kontrolleri) açıkça "önizleme" olarak işaretlidir.
  Şarj istasyonları Apple Maps aramasıyla listelenir; Trugo'nun özel servisi değildir.
- Telemetri zaman damgası 5 dakikadan eskiyse başlıkta "Canlı Telemetri" yerine
  "Son Telemetri" ve tarih gösterilir; eski veri canlı gibi sunulmaz.
- Dashboard'a gömülü Bluetooth dijital anahtar kartı: tek paylaşılan BLE oturumu, bağlan/kes,
  sertifika sunma, telefon/araç anahtarı durumu, kilit, dört kapı, bagaj ve güç durumu.
  Kilit eşlemesi resmî web uygulamasına göre 1 = kilitli, 2 = kilit açık; diğer değerlerde
  "Kilit durumu doğrulanıyor" gösterilir. `powerState` eşlemesi 2 = bekleme, 3 = aksesuar,
  4 = hazır; diğer değerlerde "Durum doğrulanıyor" gösterilir. Kapılar `door1–door4`
  sırasıyla "Kapı 1–4" etiketiyle gösterilir; fiziksel kapı konumları henüz doğrulanmadı.
   Kilit ve bagaj hızlı işlemleri READY durumunda onaylı gerçek BLE komutları gönderir;
   aksi hâlde ayrıntılı komut ekranına yönlendirir. Kapı komutlarında taze araç nonce'u
   ve telefon P-256 imzası kullanılır; kilit sonucu imzalı telemetriyle doğrulanmaya çalışılır.
    Yakınlık otomasyonu isteğe bağlıdır, araç başı/uzak RSSI kalibrasyonu ister ve yalnızca
    uygulama ekrandayken çalışır. Dengeli/Hızlı/Agresif/Öngörülü/Kalman profilleri iOS'un
     daha yavaş RSSI örneklemesine uyarlanmıştır; Android filtre algoritmasının birebir portu
     değildir. Otomatik kilitleme fiziksel araçta ayrıca doğrulanmalıdır.
     İsteğe bağlı süre sonu kapatma, ilk imzalı telemetriyle doğrulanmış yakınlık kilidinden
     sonra başlar (5–60 dk veya özel 1–1440 dk); süre dolunca otomasyon kapanır ve araç
     komutu gönderilmez. iOS uygulamayı arka planda askıya alırsa kapatma gecikebilir.
- Araç Durumu: iç sıcaklık, sürüş modu (`DRIVEMODE_COMFORT` → Konfor) ve API'de
  dolu geldiğinde fren/motor uyarıları gösterilir. Uyarı alanları boolean değilse
  veya boşsa değer uydurulmaz. `location` alanı doluysa başlıkta enlem/boylam
  koordinatları gösterilir; alan yoksa "Konum yok" yazar.
- Physical-device login, vehicle list and detail: passed.
- Sürüş & şarj analizi: fiziksel iPhone'da gerçek hesap/araç yanıtıyla doğrulandı.
  Özet (`this_month`, `last_month`, `last_month_calendar`, `all_time`,
  `community_comparison`, `last_journey`, `last_charge`), yolculuk/şarj listeleri
  (`journeys`, `charges`), dönem grafikleri (`period_km`, `period_energy`) ve
  sayfalama (`journeys_pagination`, `charges_pagination`) alanları eşlendi.
  22 Ekim 2026 verisiyle özet 1.317,6 km / 46 yolculuk / 39 sa 11 dk /
  20,01 kWh/100 km; 20 yolculuk kaydı ve 3 şarj kaydı görüntülendi. Kayıt
  ayrıntıları ve şarj maliyeti uyarısı cihazda kontrol edildi. Farklı dönemler ve
  hesap türleri için canlı doğrulama sürüyor.
- Klima gRPC istemcisi: protobuf kodlama/çözme ve gRPC çerçeve testleri geçti; uygulama
  cihaz için derlendi. `GetClimateControlStatus` cihazda `gRPC 14` ve
  `upstream connect error … 111` döndürdü; aynı yanıt kimlik doğrulaması olmadan da
  alındığından sorun istemci tarafında değil, Togg'un araç servisi tarafında.
  Kullanıcıya ham hata yerine "Araç servisine şu anda ulaşılamıyor" mesajı gösterilir.
  `SendClimateControlCommand` bu nedenle gerçek araçla uçtan uca doğrulanamadı.
- Physical-device BLE handshake, car-proof verification and vehicle commands:
  not yet tested end-to-end (requires the vehicle present).
