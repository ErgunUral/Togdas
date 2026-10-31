# iOS araç durumu widget'ı

## Kapsam

WidgetKit extension `ToqdasWidget`, iOS 16+ için `.systemSmall` ve
`.systemMedium` ailelerinde salt okunur araç özeti sunar:

- Araç adı (çoklu garajda "· N araç" rozeti)
- Taze BLE telemetrisinden kilit durumu
- Sunucu telemetrisinden batarya yüzdesi ve menzil (km)
- Son bilinen toplam kilometre ve dış sıcaklık (orta boyutta; önbellekte yoksa `—`)
- BLE son ölçüm saati; BLE yoksa bulut telemetri saati ("Bulut · HH:mm")

Widget'tan araç komutu gönderilmez. Eksik alanlar `—` gösterilir; tahmini/boş
değer sıfır olarak sunulmaz. Widget zaman çizelgesi 15 dakika sonra yenileme
ister; iOS kendi pil ve widget yenileme kurallarını uygular. Widget içeriği
VoiceOver için tek özet öğe olarak birleştirilir (`.accessibilityElement
(children: .combine)`). iOS 17+ üzerinde zorunlu
`.containerBackground(for: .widget)` API'si kullanılır; iOS 16 eski
`.background` dalını korur.

## Veri paylaşımı

`Shared/VehicleWidgetSnapshot.swift` yalnızca gösterim amaçlı snapshot'ı
`group.com.toqdas.ios` App Group içindeki `UserDefaults`'a yazar. VIN, oturum
token'ı, sertifika ve özel anahtar aktarılmaz. Uygulama açıldıkça snapshot
yenilenir; widget salt okunur.

## İmzalama gereksinimi

Uygulama ve widget extension'ın aynı App Group yetkisine sahip olması gerekir.
Apple Developer hesabında `group.com.toqdas.ios` oluşturulup hem
`com.toqdas.ios` hem `com.toqdas.ios.widget` App ID'lerine bağlanmalı; ardından
provisioning profilleri yenilenmelidir. Simulator derlemesi bu yetki olmadan
başarılı olabilir; fiziksel cihaza imzalı kurulum için profilin App Group'u
içermesi şarttır.
