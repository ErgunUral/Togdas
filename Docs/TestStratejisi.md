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
  -derivedDataPath build-uitest \
  CODE_SIGNING_ALLOWED=NO
```

`UITests/ToqdasSmokeTests.swift` şunları doğrular:

- Giriş ekranı ve Togg ID düğmesi erişilebilir.
- Cihaz dili İngilizce olsa da Türkçe arayüz metni korunur.
- `-uiTestFixture` (yalnız DEBUG) ile ağa çıkmadan pano açılır ve sekmeler görünür.
- Araç READY değilken komut düğmeleri kapalıdır ve neden ekranda görünür.

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

- UI testleri oturum açmış pano için `-uiTestFixture` ile yalnız giriş ekranı,
  sekmeler ve komut kapısını kapsıyor; gerçek API/telemetri verisi kullanılmaz.
- BLE ve WatchConnectivity simulator'da gerçek donanımı temsil etmez.
- Watch UI testi fiziksel watch gerektirir.
