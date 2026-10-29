# Paylaşılan dijital anahtar (iOS)

## Android APK akışından çıkarılan sözleşme

Android 1.0.24.42 gelen Trumore davetini `https://…/KeySharing?seId=…&no=…`
biçiminde alır. Kabul imzasının mesajı:

`Base64URL(seId) || UUID-bytes(accountUUID) || phonePublicKey(X9.63) || Base64URL(no)`

P-256 / SHA-256 imzası `ReplyToSession` uç noktasına gider. Android aynı daveti
yeniden göndermemek için `seId` parmak izini saklar; sonra sahibin Trumore
onayına kadar sertifikayı tekrar kullanmaz. Onaydan sonra
`Certificates/GetAllCertificates?phonePublicKey=…` yanıtında doğru VIN ve
telefon açık anahtarıyla eşleşen sertifikayı bulur.

## iOS akışı

1. Araç Komutları → Paylaşılan anahtar daveti bölümüne hedef VIN ve Trumore URL'si girilir.
2. Onay penceresi açıkça bunun sahiplik devri olmadığını belirtir.
3. URL host/path/port/fragment ve tekil `seId`/`no` alanları doğrulanır; anahtar
   bu VIN için Keychain'de üretilir veya mevcutsa kullanılır.
4. Togg ID `sub` UUID'si ve telefonun açık anahtarıyla Android ile aynı bayt
   dizisi imzalanır; iOS platform bilgisiyle `CheckUserPhoneRelation`, ardından
   `ReplyToSession` çağrılır.
5. `seId` ham hali saklanmaz/loglanmaz; SHA-256 parmak izi aynı davetin tekrar
   gönderilmesini engeller. Ağ yanıtı belirsizse otomatik tekrar yapılmaz.
6. Araç sahibi Trumore'da onay verdikten sonra **Onay sonrası sertifikayı oku**
   seçilir. Sertifika VIN + bu telefon anahtarına bağlanarak kontrol edilir,
   süresi kontrol edilir ve Keychain'e yazılır.

Paylaşılan araçlar `friendVins` olarak ayrıştırılır. Bu araçlarda otomatik
kimlik doğrulama yalnız paylaşılan sertifikayı okur; `ClaimCarToUser` veya sahip
sertifikası oluşturma akışına düşmez. Sahiplik taşıma isteği paylaşılan VIN için
reddedilir.

## Sınırlar / doğrulama

- Davet üretme ve iptal etme iOS'ta yok; davet Trumore'dan alınır.
- Davet sahibi onayı dış uygulamada gerekir.
- Sunucu yanıtı araç açık anahtarını içermezse iOS güvenilmeyen elle anahtar
  kabul etmez; araç anahtarı olmadan READY oluşmaz.
- API'ye gerçek `KeySharing` daveti ve ikinci Togg hesabıyla test henüz yapılmadı.
  Bu nedenle kod derleniyor olsa da uçtan uca paylaşım başarılı diye
  raporlanmıyor.
