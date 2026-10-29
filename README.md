# Toqdas iOS + watchOS — development baseline

Native SwiftUI project based on the API contract in `../Garajm`.
This is an independent implementation, not a completed port of the Android app.

## Open and build

Open `Toqdas.xcodeproj` in Xcode. Schemes: `Toqdas`, `ToqdasWatch`, `ToqdasWidget`.
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
- Dashboard layouts: Klasik, Minimal, Sportif and Teknik. The selected layout only changes
  hierarchy and card visibility; it never changes vehicle command behavior.
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
- Android 1.0.24.42/.47 tanı uyarlaması: son 60 dk BLE raporu (tarama/devir,
  bağlanma/kopma, READY, radyo, hata grupları, RSSI ve GATT yakınlık tazeliği);
  yakınlıkta eski oturum kanıtı yeni açma tetiklemez. Yalnız toplu özet paylaşılır.
- Android 1.0.24.49.3 uyarlaması: Bluetooth durum değişimi iOS'ta zaten
  centralManagerDidUpdateState ile yönetiliyor. Key discovery akışı iOS'ta
  DiscoveryView ile var; VIN-ad eşleşmesi ve servis UUID kontrolü tanı amaçlı
  gösteriliyor. GATT toparlama teşhisi BLE tanı raporuna eklendi. B alternatif
  açma yolu, PendingIntent/PI sahiplik takibi ve notification channel kontrolü
  iOS'a taşınmadı.
- Ortak BLE komut kapısı: READY ve 15 saniyeden yeni imzalı telemetri gerekir;
  kilit/açma için kilit durumu bilinmelidir. Watch bagaj/cam komutları fiziksel
  doğrulama tamamlanana kadar kapalı; kilit/açma öncesi saat onayı alınır.
- Araç sağlığı: batarya, menzil, 12 V akü, şarj durumu, kilometre, dış sıcaklık,
  lastik basıncı (kPa'dan PSI'ye) ve lastik sıcaklığı `VehicleInfo` API'sinden
  30 saniyede bir yenilenir; son güncelleme zamanı gösterilir. Tüketim alanı
  doğrulanmış servis yanıtında bulunmadığı için önizlemedir.
- Bildirimler & Destek Merkezi: superapp `Notifications/all`, `Tickets/Tur` ve
  `Package/Tur/subscriptions` uçları; okunmamış işareti, durum/tarih ve destek
  talebi notlarına geçiş. Yanıt alanları esnek eşlenir.
- Yakındaki şarj istasyonları: EPDK kamu kataloğu (istasyon, adres, koordinat ve soket),
  yerel arama/mesafe filtresi, harita ve Apple Maps yol tarifi. Cihaz konumu EPDK'ya
  gönderilmez, istemci geocoding yapılmaz; katalog saatlik sınırla önbelleğe alınır.
  EPDK kataloğu canlı soket uygunluğu/fiyat bilgisi sağlamaz.
- Read-only WidgetKit araç özeti (small/medium): kilit, bulut batarya/menzil ve veri yaşı.
  App Group `group.com.toqdas.ios` üzerinden hassas olmayan snapshot alır; WidgetKit
  yenileme sıklığı sistem politikasına bağlıdır. İmzalı iPhone kurulumu başarılı.
- İklimlendirme: Togg uzaktan kontrol gRPC servisinden `GetClimateControlStatus` ile
  açık/kapalı ve hedef sıcaklık okunur; `SendClimateControlCommand` ile 16–30 °C arası
  hedefle açma/kapatma ve sıcaklık uygulama yapılır. Her komuttan sonra araç durumu
  yeniden okunur; durum alınamazsa komut gönderilmez. Hedef sıcaklık VIN bazında saklanır.
- Browser-based OAuth authorization-code/PKCE flow with callback validation.
- Device-only Keychain session storage; refresh-token handling.
- Vehicle-list and vehicle-detail requests; details currently display formatted
  service JSON rather than a normalized dashboard.
- Foreground, service-filtered BLE discovery on iPhone and Watch, bounded to 20 seconds.
- WatchConnectivity application-context synchronization of vehicle names, timestamp and a
  display-only vehicle snapshot (lock state, doors, trunk, power state, BLE state, age, plus
  cloud battery %, range, outside temperature, 12 V battery, odometer and charging state when
  the server returns them; missing values render as "—", never as 0).
  The snapshot is not live vehicle telemetry. No credentials or key material are transferred.
- Watch lock/unlock requests: the watch sends a command ID, target VIN, creation time and a
  15-second expiry with `sendMessage`; the watch confirms each request and checks current
  telemetry freshness. The iPhone rechecks time window, VIN, READY, fresh signed telemetry
  and known lock state. Only lock/unlock are forwarded; trunk/window requests are rejected
  until physically verified. The watch never shows "locked" from the request itself.
- Unit tests: RFC 7636 vector, callback rejection cases, vehicle parsing and form encoding.
- Shared BLE protocol framing on both targets: certificate VIN/device-key binding,
  P-256 key frames, challenge parsing, raw/DER signature conversion, outgoing
  certificate/phone-proof/command frames, signed vehicle proof and telemetry verification.
  RFC 6979 known-answer, framing and tampering tests pass. Certificate binding is not
  issuer/expiry verification.
- Per-VIN P-256 phone key generated in the Keychain (private key never exported).
- Smart-access certificate fetch/create with owner body and phone-key binding.
- Incoming shared-key invitation support: validates Togg KeySharing URL, signs the
  `seId + account UUID + phone public key + nonce` payload, submits `ReplyToSession`,
  then reads only the certificate bound to the invited VIN and this phone key.
  Shared VINs never enter the owner/`ClaimCarToUser` flow; owner approval remains in Trumore.
- BLE session state machine: certificate presentation, challenge signing, car-proof
  verification, READY gate and authenticated lock/unlock/trunk/window/drive frames.
  Window commands use the official windowsOpen=6/windowsClose=7 command codes and
  signed nonce flow; the vehicle's window position is not exposed by verified telemetry.
  Every lock action sends windowsClose first, then sends lock only after the vehicle
  acknowledges the window command; this does not prove the glass physically closed.
  After fresh signed telemetry confirms the locked state, the iPhone plays two short
  confirmation tones (ambient audio; respects the silent switch).
- On 2026-10-27 this handshake reached READY and verified signed telemetry on the
  tested iPhone/vehicle pair. That does not establish compatibility with every model
  or prove command execution. Command timestamps use the vehicle time characteristic
  when available.

## Integration boundaries

The existing Android `super-app` client ID, callback and production endpoints are
used as integration inputs. Acceptance of this OAuth flow on iOS has not been tested
or approved by the service operator. EPDK's public catalog endpoint was queried to
confirm its response contract and rate limit. On 2026-10-27 the iPhone BLE session
reached READY and verified signed telemetry; physical vehicle commands still need
separate verification. Application signatures and successful builds alone do not
demonstrate vehicle compatibility.

Key-sharing request signing, invitation validation and shared-certificate selection
are implemented from the Android 1.0.24.42 client flow; no real invitation or second
Togg account has been used to verify the service-side result.

Bluetooth Dijital Anahtar kurulumu için adım adım sesli rehber eklendi. Rehber
isteğe bağlıdır; mikrofon açmaz, ses kaydı veya transkript oluşturmaz. Rehber
metni ekranda da gösterilir; VoiceOver erişilebilirliği korunur.

Kişiselleştirilebilir arayüz (DashboardCustomization): Klasik/Minimal/Sportif/Teknik
düzenler. Özel modda kartlar sıralanıp gizlenebilir; bağlantı durumu ve hızlı
kontroller her zaman görünür. Yakınlık otomasyonu aktifken yakınlık kartı
gizlenemez. Seçimler UserDefaults ile kalıcı saklanır.

Kilit durumu taze imzalı telemetriyle doğrulandığında iki tonlu korna benzeri ses
çalar. Bağlantı sesi ayrı ve farklıdır. Ses iPhone'un sessiz anahtarına saygı gösterir.

The Watch receives the latest available display snapshot when the system delivers
it. Lock/unlock commands run as validated foreground requests (see above). Trunk and
window commands are disabled on Watch until physically verified. Scanning does not
identify an authorized vehicle: advertisement names, service UUIDs and RSSI are not
authentication evidence.

## Sesli komut çalışması

Sesli komutların kapsamı, güvenlik kapıları, doğrulanmış iOS yetenekleri (Türkçe
on-device konuşma tanıma, Siri/App Intents, Foundation Models) ve aşamalı plan:
[Docs/SesliKomutlar.md](Docs/SesliKomutlar.md). Yeniden tasarlanan v2 mimarisi:
[Docs/SesliKomutlar-v2.md](Docs/SesliKomutlar-v2.md).

v2 çekirdeği:

- `Core/VoiceCommand.swift`: tipli komut kümesi ve risk sınıflandırması.
- `Core/VoiceCommandParser.swift`: Türkçe normalizasyon, deterministik ayrıştırma,
  belirsizlik ve olumsuzlama koruması.
- `Core/VoiceCommandPolicy.swift`: saf eylem kapıları (READY, telemetri < 15 sn,
  onay, kilit açmada cihaz kilidi + Face ID, önizleme).
- `Core/VoiceSession.swift`: kayıt → tanıma → anlama → onay → kimlik → yürütme →
  yanıt durum makinesi; sahte adaptörlerle test edilebilir.
- `Core/VoiceChat.swift`: komut olmayan sorulara yerel, deterministik yanıt
  (`nasılsın`, `neler yapabilirsin`, `teşekkürler`); ağa çıkmaz, komut yürütmez.
- `Tests/VoiceCommandParserTests.swift`, `Tests/VoiceCommandPolicyTests.swift`,
  `Tests/VoiceSessionTests.swift`, `Tests/VoiceChatTests.swift`,
  `Tests/BleFailureTests.swift`, `Tests/EPDKCatalogTests.swift`,
  `Tests/BLEDiagnosticReportTests.swift`, `Tests/KeySharingTests.swift`,
  `Tests/BLECommandPolicyTests.swift`: toplam 139 test.

Sesli asistanı genişletme rehberi: `Docs/SesliKomut-Ekleme.md` (sohbet sorusu, salt
okunur komut ve eylem ekleme adımları, değişmez kurallar).

BLE dayanıklılığı (`Docs/Ble-Dayanklilik.md`): Android 1.0.24.42'nin üç
mekanizması iOS'a uyarlandı — evreli tarama (normal → ısrarlı), radyo kapanıp
açıldığında kendiliğinden yeniden bağlanma, GATT hatalarının tek satır özete
indirgenmesi (`Core/BleFailure.swift`).

Uygulama içi bas-konuş arayüzü:

- `App/VoiceAssistant.swift`: cihaz üstü Türkçe tanıma (`requiresOnDeviceRecognition`),
  15 saniyelik oturum, canlı transkript, Türkçe sesli yanıt. Ses kaydı saklanmaz.
  Ses yakalama/tanıma hâlâ bu dosyada; v2 `VoiceSession` adaptörleri sıradaki adım.
- `App/VoiceSheet.swift`: pano başlığındaki mikrofon düğmesiyle açılan sayfa; örnek komut
  düğmeleri ve tanıma izni/dil indirme durumunda açıklama.
- `DashboardView` ses işleyicisi artık `VoiceCommandParser` + `VoiceCommandPolicy`
  hattını kullanıyor; onay ekranı ve Face ID akışı korunuyor.
- Salt okunur yanıtlar: batarya/menzil, kilit, bagaj, şarj durumu, lastik (PSI), dış
  sıcaklık, odometre, 12 V akü, klima durumu. Eksik veri "—" veya "bilgi yok" olarak söylenir.
- Eylemler yalnızca READY + 15 saniyeden taze BLE telemetrisiyle ve mevcut onay ekranıyla
  gönderilir; kilitleme/bagaj/cam komutları "önizleme" notu taşır.
- Sesli kilit açma, onaydan sonra Face ID/parola doğrulaması ister (`NSFaceIDUsageDescription`).
- Klima servisi yanıt vermediği için sesli klima komutu "kullanılamıyor" der; aracı bul
  komutu doğrulanmadığı için gönderilmez.

Doğrulama durumu: cihazda tr-TR için `supportsOnDeviceRecognition = true` okundu ve mikrofon
hattı tanı testiyle açıldı. `-voiceDemo "Şarjım ne kadar?"` cihazda yeni ayrıştırıcıyla
`status(.battery)` üretip “Batarya yüzde 63, menzil 233 kilometre” yanıtını ve TTS’i çalıştırdı.
Arayüzden tam sesli komut cümlesi, araç içi gürültü ve eylem onayı henüz denenmedi.
Siri/App Intents: `Core/CarShortcuts.swift` dört komut sunar (kilitle, kilidi aç, bagajı aç,
bagajı kapat). Kısayollar `toqdas://command?action=<lock|unlock|trunkOpen|trunkClose>` URL'ine
yönlendirir; URL ayrıştırma `Core/ShortcutLink.swift` içinde tek yerde ve birim testlidir.
Komutlar yine `BLECommandPolicy` kapısından geçer (READY + 15 sn taze telemetri); reddedilirse
uygulama gerekçeyi hata bandında gösterir, sessizce yutmaz.

Siri/Shortcuts elle test adımları (araç yanında, uygulama arka planda):
1. Kısayollar uygulaması > Toqdas > "Arabamı kilitle" kısayolunu çalıştır.
2. Uygulama açılır; BLE hazır değilse "Kilitle gönderilemedi" bandı ve gerekçe görünür.
3. Araç uyanıkken ve "Komut hazır" iken aynı kısayol kilitleme komutunu gönderir.
4. Aynı adımlar "Arabamı aç" ve "Bagajı aç/kapat" için tekrarlanır.

Geliştirme kısıtı: iPhone Mac'e **kabloyla** bağlıyken mikrofon tüm örnekleri sıfır veriyor
(rota `builtInMic`, `isInputMuted = false` olmasına rağmen). Kablo çıkarılınca ses normal
çalışıyor. Bu yüzden ses testleri kablosuz yapılmalı; kabloyla yalnızca kurulum yapılmalı.
`-voiceRecorderTest` argümanı 5 saniyelik kayıt alıp tepe/meter değerini ve ses ortamı
özetini (rota, giriş, `muted`, rota değişimi, kesinti) konsola yazar.

Sohbet katmanı: `nasılsın`, `merhaba`, `neler yapabilirsin`, `teşekkürler` gibi komut olmayan
sorular `Core/VoiceChat.swift` içindeki yerel kalıplarla yanıtlanır; ağ, LLM veya komut
yürütme yoktur. Tanınmayan cümleler mevcut “Bu komutu anlayamadım” yanıtına düşer.

Sertifika/araç anahtarı önbelleği **Keychain**'de tutulur (`CertificateCache`, servis
`com.toqdas.ios.certificate.v2`). Daha önce `UserDefaults` kullanıldığı için uygulama her
yeniden kurulduğunda araç açık anahtarı siliniyordu; el sıkışma “Araç doğrulama anahtarını
göndermedi” hatasıyla 7 sn sonra kopuyordu. Eski `UserDefaults` kaydı ilk okumada Keychain'e
taşınır. Araç anahtarı kaybolursa arayüzdeki **Dijital anahtarı yeniden eşleştir**
(`ownerPublicKey` devri, `overwriteOwner: true`) ile araç ekranından eşleştirme yenilenir.

## Next implementation milestones

1. Verify iOS OAuth client/redirect acceptance and real response formats.
2. Complete BLE framing (outgoing handshake/commands) and establish trusted vehicle
   key provenance. Incoming P-256 proof verification and known-answer tests are implemented.
3. Implement GATT discovery, characteristic subscription, write-size negotiation,
   authentication state machine, cancellation and timeout recovery on iPhone.
4. Verify separate Watch public-key/certificate registration without replacing the
   existing phone relationship; private keys remain on their generating device.
5. Watch lock/unlock now runs as a foreground request over WatchConnectivity with command
   ID, expiry, acknowledgement and fresh telemetry readback. Independent Watch
   certificate/key registration (without replacing the phone relationship) is still open;
   private keys must remain on their generating device.
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
- Physical watch install: the watch was paired to the Mac via Device Hub (Pair Nearby
  Device), which registered its UDID. The watch app installs via
  `devicectl device install app --device <watch-udid> …/Debug-watchos/ToqdasWatch.app`.
  Installing through the iPhone's Watch app fails on free-provisioning teams
  (MIInstallerErrorDomain 111); use the direct devicectl path.
- Thirty-three Swift package tests: passed (Drive Experience şema, biçimlendirme,
  sayfalama ve ayrıntı testleri; şarj hesaplama sınırları).
- Dashboard UI: built and launched on the physical iPhone. Veri gelmeyen alanlar
  (ortalama tüketim, şarj kontrolleri) açıkça "önizleme" olarak işaretlidir.
  Şarj istasyonları EPDK kamu kataloğundan listelenir; canlı soket durumu içermez.
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
     uygulama ekrandayken komut gönderir: yeni yaklaşmada kilitliyse açar; uzaklaşmada tüm
     kapılar kapalı ve araç beklemedeyse önce cam kapatma, onayından sonra kilit komutu yollar.
     Pencere açıklığı telemetride olmadığından cam kapatma her kilitleme öncesi denenir.
     BLE oturumu değişince önce yeni uzak baz çizgisi, sonra yeni yaklaşma kanıtı gerekir.
     Arka planda yalnız algılama/bildirim vardır; araç komutu gönderilmez.
     Otomatik kilitleme/açma gerçek araçta ayrıca doğrulanmalıdır.
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
- Physical-device BLE handshake: the full certificate → challenge/response → READY
  sequence was completed on 24 October 2026 with a cached 332-character certificate.
  Logged sequence: `1000000001000000` request, certificate frames 247 B + 16 B acked with
  `1001ef0002000000` and `1002000000000000`, challenge `27010a000a000100` answered,
  `11024a0001000000` and `1100000001000000` received, state `Komut hazır`. The car then
  streamed signed telemetry (`2601550055000100`, lock = kilitli, doors `[0,0,0,0]`, trunk = 1).
  The link dropped after ~16 s with `CBErrorDomain code=6` at RSSI −88…−94 dBm. Lock/unlock
  and other vehicle commands are still **not** verified end-to-end (requires the vehicle present).
- Ölçülen kopma nedenleri (26 Ekim 2026, cihaz + gerçek araç):
  - **Araç oturumu sabit 60 sn.** Sinyal iyiyken (−84 dBm) bağlantı tam 60 sn sonra
    `CBErrorDomain code=7` ("araç bağlantıyı kapattı") ile kapanıyor. Telemetri akarken ve
    20 sn'de bir araç saati okunurken de değişmedi; yani "sessizlik" zaman aşımı değil,
    araç tarafında sabit oturum ömrü. Canlı tutma denemesi koddan çıkarıldı.
  - **Zayıf sinyal hat zaman aşımı.** −90…−95 dBm'de bağlantı 3–57 sn arasında
    `code=6` (connection timeout) ile düşüyor. −80 dBm üstü güvenilir kabul edilir; telefonun
    cepte/çantada olması, gövde ve 2,4 GHz girişimi bu aralıkta kopmayı kaçınılmaz kılıyor.
  - iOS bağlantı aralığını uygulamaya değiştirtmez. Uygulama tarafında yapılabilen: hızlı,
    sınırlı yeniden bağlanma.
- `BleLinkCoordinator` (pano kapalıyken ve arka planda da çalışır): 1,5/3/6/12/15 sn
  geri çekilmeli en fazla 8 deneme; yeniden bağlanınca önbellekteki sertifika + araç
  anahtarıyla otomatik kimlik doğrulama (ağ gerekmez); READY'de sayaç sıfırlanır.
  Bilinen çevrebirime taramadan doğrudan bağlanma dener (4 sn bekçi, olmazsa taramaya döner).
  Kopma anında süre ve son RSSI teşhis günlüğüne yazılır; pano BLE kartında yeniden bağlanma
  durumu görünür. Ölçüm: kopmadan READY'ye dönüş taramayla ~6–9 sn, doğrudan bağlanmayla
  ~4–5 sn. Sinyal −90 dBm altındayken bu süre uzar; kalıcı çözüm telefonun araçta daha
  yakın taşınması ve ileride UWB ile hassas mesafe (bkz. sınırlar).
- `keepBLEConnected` is now persisted in `UserDefaults` (`toqdas.ble.keepConnected`) so the
  reconnect intent survives view re-creation; reconnect skip/abort reasons are printed.
