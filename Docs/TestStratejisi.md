# Test stratejisi

## Birim testleri

```sh
swift test
```

Core politikaları, BLE protokolü, ağ yeniden denemesi, biçimlendirme,
şarj hesapları, erişilebilirlik yardımcıları ve komut kapıları burada test
edilir. Fiziksel araç davranışı bu testlerin kapsamı dışıdır.

## Simulator UI smoke testleri

```sh
xcodebuild test \
  -project Toqdas.xcodeproj \
  -scheme Toqdas \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:ToqdasUITests
```

19 test, 5 dosya (2026-11-13: 190 sn, 19/19 yeşil):

- `UITests/ToqdasSmokeTests.swift` (4): Giriş ekranı ve Togg ID düğmesi
  erişilebilir; cihaz dili İngilizce olsa da Türkçe arayüz metni korunur;
  `-uiTestFixture` (yalnız DEBUG) ile ağa çıkmadan pano açılır ve sekmeler
  görünür; araç READY değilken komut düğmeleri kapalıdır ve neden ekranda
  görünür.
- `UITests/ToqdasFlowTests.swift` (5): Dört sekme görünür/seçilebilir;
  fixture telemetrisi (%79, 365 km); klima hedef sıcaklık kontrolleri;
  12 V %65 ve eksik veri `—` kuralı; Trugo istasyon kartı.
- `UITests/ToqdasCommandTests.swift` (3): Komut kapısı açıklaması; beş
  komutun devre dışı olması; devre dışı komuta dokununca onay
  istenmemesi; başlık menüsünden komut sheet'i açılıp kapanması.
- `UITests/ToqdasGuideTests.swift` (4): Senaryolar rehberi aç/kapat;
  canlı durum rozetleri; yakınlık kartından rehberin yakınlık bölümüne
  odaklanması; yakınlık kalibrasyon sheet'i.
- `UITests/ToqdasAccessibilityTests.swift` (3): Sekme dokunma hedefleri
  ≥44 pt; VoiceOver etiketleri ve seçili durum; XXXL Dynamic Type ile
  pano kullanılabilirliği.

`UITests/ToqdasUITestSupport.swift` ortak altyapıdır: `-uiTestSignedOut`
ile oturum kapatılır, `-uiTestFixture` panoyu açar; sabit `sleep` yok,
yalnız koşula bağlı bekleme ve kaydırma kullanılır.

UI testleri ağa çıkmaz. `-uiTestSignedOut` yalnız DEBUG derlemesinde oturumu
temizler; giriş düğmesine basmaz.

## Fiziksel testler

Aşağıdakiler otomatik test değildir ve gerçek iPhone + araç gerektirir:

1. Araç ekranından dijital anahtar eşleştirmesi; `carKeyPresent=true`, READY.
2. Kilit/açma, bagaj, cam ve klima komutları; imzalı telemetri doğrulaması.
3. Yakınlık/geofence, arka plan BLE ve sesli kilit açma akışı.
4. Watch kurulumu, çevrimdışı son veri ve komut reddi.
5. Lastik basıncı, şarj, EPDK ve widget fiziksel kontrolleri.

Her fiziksel çalıştırmada konsol kanıtı ve tarih `Docs/BLE-Eslesme.md` içine
eklenir. READY veya komut başarısı fiziksel kanıt olmadan iddia edilmez.

## Bilinen sınırlar

- UI testleri oturum açmış pano için `-uiTestFixture` ile giriş ekranı,
  sekmeler, komut kapısı, senaryolar rehberi ve erişilebilirlik
  davranışlarını kapsıyor; gerçek API/telemetri verisi kullanılmaz.
- Fixture'ın bulut anlık görüntüsü lastik basıncını taşımaz: sağlık
  kartında lastikler "basınç bilgisi yok" olarak doğrulanır (0 PSI'ye
  sıkıştırılmadığının kanıtı).
- BLE ve WatchConnectivity simulator'da gerçek donanımı temsil etmez.
- Watch UI testi fiziksel watch gerektirir.
