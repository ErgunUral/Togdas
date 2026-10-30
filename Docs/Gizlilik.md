# Gizlilik ve App Store notları

Bu belge uygulamanın veri akışını ve App Store gizlilik manifestini özetler.
Hukuki metin veya App Store Connect beyanı yerine geçmez.

## Cihazda kalan veriler

- Togg ID oturum belirteçleri **Keychain**'de, `WhenUnlockedThisDeviceOnly`
  erişimiyle tutulur; çıkışta silinir.
- Dijital anahtar ve araç sertifikası **Keychain**'de tutulur; özel anahtar
  cihazdan dışarı çıkmaz.
- Araç listesi, son gösterim anlık görüntüsü, komut geçmişi, tanı özeti ve
  kullanıcı tercihleri `UserDefaults`/uygulama grubunda tutulur. Bunlar anahtar
  veya oturum belirteci içermez.
- Sesli asistan yalnızca kullanıcı bas-konuş başlattığında dinler. Ses kaydı
  kalıcı saklanmaz; geçici dosya işlem sonunda silinir. Tanıma
  `requiresOnDeviceRecognition = true` ile cihaz üstünde yapılır.
- Watch'a yalnızca gösterim amaçlı araç anlık görüntüsü gider; token, sertifika
  veya özel anahtar aktarılmaz. Watch komutları iPhone üzerinden ve taze imzalı
  telemetriyle yürütülür.

## Ağa giden veriler

- Togg ID, araç listesi, telemetri, sertifika ve araç komutları Togg servislerine
  (`toggid.togg.cloud`, `tva-api.togg.cloud`, `superapp-api.channels.togg.cloud`)
  gönderilir. Bu istekler uygulama geliştiricisinin kendi sunucusuna gitmez.
- EPDK şarj istasyonu kataloğu EPDK servisinden alınır; konum cihazda sıralama
  için kullanılır, sunucuya gönderilmez.
- Geofence ve yakınlık otomasyonu cihazda değerlendirilir; arka plan konumu
  yalnızca kullanıcı bu özelliği açtığında kullanılır.
- Uygulamada reklam, üçüncü taraf analitik veya izleme (tracking) yoktur.

## Manifest

Her hedefte `PrivacyInfo.xcprivacy` var:

- `Toqdas`: `UserDefaults` (`CA92.1`, `1C8F.1`) ve dosya zaman damgası
  (`C617.1`).
- `ToqdasWatch`: yalnızca kendi `UserDefaults` verisi (`CA92.1`).
- `ToqdasWidget`: uygulama grubu `UserDefaults` (`1C8F.1`).

`NSPrivacyTracking` false, izleme alanı yok. Manifestte toplanan veri türü
bildirilmiyor; Togg ID/VIN/telemetrinin Togg servislerine iletilmesi App Store
Connect gizlilik anketinde ayrıca beyan edilmeli.

## App Store öncesi eksikler

- Yayınlanacak gizlilik politikası URL'si ve destek adresi.
- Togg servislerinin veri saklama/silme koşullarının ürün sahibiyle
  netleştirilmesi.
- Hesap silme akışının Togg tarafında karşılanması; uygulama çıkışı yalnızca
  yerel oturumu siler.
- App Store Connect gizlilik anketinin gerçek veri akışına göre doldurulması.
- Fiziksel cihazda izin metinlerinin ve arka plan konumu davranışının
  doğrulanması.
