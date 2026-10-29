# BLE dayanıklılığı (Android 1.0.24.42 / 1.0.24.47 uyarlaması)

Android 1.0.24.42 yeni özellik getirmedi; bağlantı kopmasını azaltmaya yönelik
üç mekanizma ekledi. Bunların iOS karşılıkları:

## 1. Evreli tarama (`PI → normal devir` karşılığı)

Android: PendingIntent taraması 15 sn sonuç vermezse normal taramaya döner.

iOS: `BleScanPolicy` iki evre tanımlar (`Core/BleFailure.swift`):

| Evre | Süre | `allowDuplicates` |
|---|---|---|
| hızlı | 12 sn | kapalı |
| ısrarlı | 12 sn | açık |

İlk evre sonuçsuz kalırsa tarama durdurulup yeniden başlatılır; teşhis kaydına
`scan_rotate · hızlı tarama sonuçsuz; ısrarlı taramaya geçildi` düşer. İki evre
de boşsa `scan_exhausted` yazılır ve pano "Araç bulunamadı" gösterir.

Neden: iPhone tek seferlik taramada reklamı kaçırabiliyor; iOS'ta PendingIntent
olmadığı için en yakın karşılık temiz bir yeniden taramadır.

## 2. Radyo geri gelince kendiliğinden bağlanma (`Bluetooth STATE_ON`)

`BleConnection` "bağlı kal" niyetini (`shouldStayConnected`) tutar:

- Kullanıcı bağlanınca veya otomatik bağlanma açıksa `true`.
- Kullanıcı bağlantıyı kapatınca `false` (beklenmeyen kopmada korunur).

Bluetooth kapanırsa: durum `failed("Bluetooth kapalı")`, telemetri korunur,
yeniden bağlanma denemeleri **deneme sayacını tüketmez** (koordinatör
`isRadioAvailable` ile bekler).

Bluetooth açılınca: eski `CBPeripheral` tanıtıcıları geçersiz sayılır
(`lastPeripheral = nil`), tarama sıfırdan kurulur ve bağlantı hemen yeniden
denenir. Teşhis: `radio_on · Bluetooth yeniden açıldı; tarama sıfırlandı`.

Ayrıca uygulama öne geldiğinde (`willEnterForeground`) bekleyen geri çekilme
süresi atlanır: `foreground_retry · uygulama öne geldi; bekleme atlandı`.
Son 3 saniye içinde deneme yapıldıysa tekrar denenmez.

## 3. GATT hatasının tek satır özeti

`BleFailureClassifier` CBError/CBATTError kodlarını gruplara indirger:

| Grup | Örnek kod | Panoda |
|---|---|---|
| `signal` | `connectionTimeout`, `connectionFailed` | Sinyal zayıf · bağlantı koptu |
| `peerClosed` | `peripheralDisconnected`, hata yok | Araç bağlantıyı kapattı |
| `pairingLost` | `peerRemovedPairingInformation`, `encryptionTimedOut`, `insufficientAuthentication` | Eşleşme geçersiz · yeniden eşleştirme gerekli |
| `radioOff` | Bluetooth kapalı / izin yok | Bluetooth kapalı |
| `serviceDiscovery` | servis keşfi hatası | Araç servisleri bulunamadı |
| `gatt` | diğer CBATT hataları | Araçla veri kanalı kurulamadı |
| `busy` | `connectionLimitReached` | Araç başka bağlantıyla meşgul |

`BleFailureCounter` aynı grubu 60 saniyelik pencerede sayar; üçüncü tekrarda
özet "Sinyal zayıf · bağlantı koptu · son 1 dk'da 3 kopma" olur. READY'ye
geçince sayaç sıfırlanır.

Ayrıntı (ham kod, süre, RSSI) `diagnosticEvents` içinde kalır; pano yalnızca tek
satır gösterir.

## Sınırlar

- Bu değişiklikler fiziksel iPhone + gerçek araçla **ölçülmedi**. READY ve
  telemetri için araç anahtarı (`carKey`) gerekiyor; anahtar yokken yalnızca
  tarama/radyo/hata yolları doğrulanabilir.
- Tarama evreleri pil tüketimini artırabilir; ölçüm sonrası süreler kısaltılabilir.
- Android'in PendingIntent, sticky servis ve ekran açık/kapalı ayrımı iOS'ta
  yoktur; karşılıkları yukarıdaki üç mekanizmadır.

## 4. Yakınlık oturumu ve GATT RSSI güvenliği (.47)

Android 1.0.24.47, açma kararını bağlı GATT RSSI'sinin tazeliği, birden çok
ölçümün yönü ve aynı bağlantı oturumuna ait olmasıyla sınırlar. Ayrıca 2 saniyelik
güçlü sinyal alternatif açma yolu ve ayrıntılı zamanlama tanısı ekler.

iOS'a taşınan güvenli kısım:

- `BleConnection.rssiUpdatedAt` son bağlı GATT RSSI okumasının zamanını tutar.
- Yakınlık geçişi, seçili profilin RSSI aralığına göre taze olmayan/gelecek zamanlı
  örnekleri reddeder (`ProximityRSSIPolicy`).
- BLE yeniden bağlanınca/oturum kesilince önceki `near` durumu silinir. Otomasyon
  önce yeni bir **uzak baz çizgisi**, sonra yeni yaklaşma örneği görmeden kilit
  açma eylemi üretemez (`requireFreshCycle`).
- Tanı raporuna eski GATT örneği ve yakınlık oturumu sıfırlaması sayaçları eklendi.

Taşınmayanlar:

- Android'deki 2 saniyelik alternatif otomatik açma yolu; bu, mevcut iOS kalibrasyon
  ve teyit kapılarını gevşetip yanlış açma olasılığını artırabilir.
- Ekran kapalı/arka planda otomatik araç komutu. iOS arka planda yalnız algılama ve
  bildirim yapar; kilit/aç komutu göndermez.

Bu korumalar kod/test düzeyinde doğrulandı. Android .47'nin yeni alternatif açma
yolu gerçek araçta gözlemlenmedi ve iOS'ta uygulanmadı.
