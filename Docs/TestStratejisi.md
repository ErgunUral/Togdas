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

39 test, 9 dosya (2026-11-14: 437 sn, 39/39 yeşil):

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
- `UITests/ToqdasNavigationTests.swift` (8): Sesli Asistan, BLE kurulum
  rehberi, Aday Seç, Bluetooth taraması sheet'leri açılır ve kapanır;
  Araç detayı, Servis kartı, Seyahatname ve Bildirimler & Destek
  ekranları açılır ve panoya dönülür.
- `UITests/ToqdasAccessibilityAuditTests.swift` (4, iOS 17+): Genel Bakış,
  üç sekme, Senaryolar rehberi ve komut sheet'inde
  `performAccessibilityAudit` — dokunma hedefi, okunabilir etiket, metin
  kırpılması ve trait. Dynamic Type ve kontrast bilinçli kapsam dışı
  (bkz. `Docs/Erisilebilirlik.md`).
- `UITests/ToqdasLayoutTests.swift` (4): Sportif düzende hızlı kontroller
  BLE kartından önce gelir ve cam/güvenlik bölümü korunur; Teknik düzende
  "Canlı BLE Tanısı" bloğu yakınlık kartından önce gelir; şarj
  hesaplayıcıda hedef doluluk %20'den %100'e çekilince tahmini enerji ve
  ücret yenilenir; varsayım/şarj başlatmama notu görünür. Hesaplayıcıya
  `-scrollChargingCalculator` (yalnız DEBUG) ile otomatik kaydırılır;
  düzen seçimi test sonunda Klasik'e döner.
- `UITests/ToqdasSettingsTests.swift` (4): Tema (Okyanus) ve düzen
  (Minimal) seçimi yeniden başlatmada korunuyor; Minimal düzende
  yakınlık kartı gizleniyor; VoiceOver tek tema/tek düzen seçili
  bildiriyor; "Çıkış yap" giriş ekranına dönüyor.

`-uiTestResetLook` (yalnız DEBUG) tema ve düzen `@AppStorage`
anahtarlarını temizler; ayar testleri kendi başlangıç durumlarını
garantiler ve sonunda varsayılana döner.

`UITests/ToqdasUITestSupport.swift` ortak altyapıdır: `-uiTestSignedOut`
ile oturum kapatılır, `-uiTestFixture` panoyu açar; sabit `sleep` yok,
yalnız koşula bağlı bekleme ve kaydırma kullanılır.

`UITests/Screens/ToqdasScreens.swift` ekran nesnelerini (Page Object Model)
tutar: `DashboardScreen`, `MenuSheet`, `CommandSheet`, `ScenarioGuideSheet`,
`CalibrationSheet`, `LoginScreen`. Erişilebilirlik seçicileri yalnız burada
tanımlıdır; testler davranışı ve iddiaları taşır, ekran nesneleri iddia
içermez.

UI testleri ağa çıkmaz. `-uiTestSignedOut` yalnız DEBUG derlemesinde oturumu
temizler; giriş düğmesine basmaz.

Not: yeni bir test dosyası eklendikten sonra ilk koşu "0 test" raporlarsa
dosyaya `touch` atıp yeniden çalıştırın (Xcode artımlı derleme bazen yeni
dosyayı test paketine almıyor).

## Kapsam ölçümü (2026-11-13)

| Mercek | Kapsanan | Toplam | Oran |
|---|---|---|---|
| UI yüzeyi (ekran/sheet) | 16 | 17 | %94 |
| Ürün senaryosu — tam davranış | 2 | 32 | %6 |
| Ürün senaryosu — yüzeysel | 6 | 32 | %19 |
| Simülatörde test edilebilir senaryo tavanı | 6 | ~11 | %55 |

Kapsanmayan tek yüzey `ChargingStationsView` (harita/EPDK listesi; ağ
gerektirir). Senaryo rehberindeki 32 maddenin ~21'i BLE, araç veya
donanım gerektirdiği için simülatörde uçtan uca doğrulanamaz; bu maddeler
fiziksel test listesine aittir.

İşlev bazlı envanter (45 işlev, A/B/C sınıflandırması ve öncelikli
boşluklar): [FonksiyonEnvanteri.md](FonksiyonEnvanteri.md).

## Sürekli entegrasyon (CI)

`.github/workflows/ci.yml` iki iş çalıştırır:

| İş | Tetik | Kapsam | Süre hedefi |
|---|---|---|---|
| `unit` | push, PR, gecelik | `swift test` (ToqdasCore, 521 test) | ~1 dk |
| `ui` | push, PR | Duman: `ToqdasSmokeTests` + `ToqdasFlowTests` | CI'da ~10-15 dk |
| `ui` | gecelik `03:00 UTC` | Tam paket: `-only-testing:ToqdasUITests` (39 test) | ~20-25 dk |
| `ui` | `workflow_dispatch` | `full: true` ise tam paket, değilse duman | — |

- Runner `macos-26`; Xcode imajın varsayılanıdır. Farklı bir imaj
  gerekiyorsa `runs-on` etiketi güncellenir.
- Simülatör dinamik seçilir: en yeni iOS çalışma zamanındaki en yeni
  iPhone; runner'da hazır cihaz yoksa `Toqdas CI` adıyla oluşturulur.
  Bu yüzden cihaz adı/sürümü workflow'a gömülü değildir.
- `CODE_SIGNING_ALLOWED=NO`, `-derivedDataPath $RUNNER_TEMP/DerivedData`,
  `-parallel-testing-enabled NO` (testler `UserDefaults` paylaştığı için).
- Başarısızlıkta `ui-test-results.xcresult` artifact olarak yüklenir
  (ekran görüntüleri ve test logları dahil, 7 gün saklanır).
- Yerel koşuyla aynı komut kullanılır; tek fark `-destination` UDID'si.
- Birim testleri saat diliminden bağımsızdır: CI UTC'de koşar. Yerelde
  aynı koşulu `TZ=UTC swift test` ile doğrulayın (521 test).
- Başarısız adım hata satırlarını check-run annotation olarak yayınlar;
  GitHub logları anonim erişime kapalı olduğu için tanılama buradan okunur.

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
