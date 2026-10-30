# BLE dijital anahtar eşleştirme runbook’u

Bu belge, iPhone ile araç arasındaki dijital anahtar eşleştirmesi
tamamlanmadığında izlenecek sırayı ve loglardan nasıl karar verileceğini
açıklar. Fiziksel araç ve gerçek iPhone olmadan READY doğrulanmış sayılmaz.

## 1. Ön koşullar

- iPhone Bluetooth açık.
- Araç Bluetooth açık ve menzilde.
- Araçta dijital anahtar / telefon eşleştirme özelliği açık.
- Uygulama DEBUG build ve `-openCommands` ile açılmış.
- Araç, uygulamanın daha önce bağlandığı VIN ile aynı.

## 2. Araç ekranından eşleştirme

1. Araç ekranında **Dijital Anahtar** veya **Telefon Eşleştirme** bölümünü aç.
2. Listede bu iPhone’u seç.
3. Eşleştirmeyi başlat.
4. Araçta onay kodu görünürse iPhone’daki kodla karşılaştır.
5. Uygulamada **Araç komutları** ekranını açık tut.
6. Araçtan doğrulama anahtarı gelene kadar bekle.

Beklenen sıra:

```text
sertifika hazır
sertifika frame 1/2
frame 1 ack
sertifika frame 2/2
frame 2 ack
vehicle key request
araç anahtarı
challenge
phone proof
car proof
READY
```

## 3. Log toplama

```bash
xcrun devicectl device process launch --console --terminate-existing \
  --device <IPHONE_UDID> \
  com.toqdas.ios -- -openCommands > /tmp/toqdas-ble.log 2>&1
```

Önemli satırlar:

```bash
grep -E "\[CERT\]|\[BLE\]|ToqdasBLE" /tmp/toqdas-ble.log
```

Sertifika yanıtının alan adlarını görmek için:

```bash
grep "CERT\]\[DEBUG" /tmp/toqdas-ble.log
```

Bu log yalnızca anahtar adlarını ve değer uzunluklarını içerir; sertifika,
telefon anahtarı ve araç anahtarı değerleri yazılmaz.

## 4. Karar ağacı

### A. `carKeyPresent=false` ve sunucu anahtar döndürmüyor

Logda:

```text
[CERT] server returned no vehicle key
[BLE] vehicle key request
[BLE] vehicle repeated key request
```

Anlamı: sertifika var, araç doğrulama anahtarı yok. Öncelikle araç ekranından
eşleştirmeyi tamamla. Eşleştirme tamamlanmışsa sunucu/araç kaydı yenilenmeli.

### B. Sunucu anahtar döndürüyor ama uygulama bulamıyor

`[CERT][DEBUG] certObjectKeys=[...]` çıktısında anahtar farklı adla
görünüyorsa `CertificateRecord.vehicleKeyKeys` listesine ekle. Değer
loglanmadan yalnızca alan adı doğrulanır.

### C. Araç anahtarı geliyor ama eşleşmiyor

Logda:

```text
vehicle key frame
vehicle key does not match server record
```

Anlamı: sunucudaki anahtar eski veya başka araca ait. Sertifikayı yenile;
gerekirse sahip anahtarını yeniden al.

### D. Challenge geliyor, READY gelmiyor

Araç anahtarı doğru; sorun telefon imzası, saat veya araç kanıtı aşamasında.
Logda `challenge`, `phone proof`, `car proof` sırasına bak.

### E. READY geliyor

Artık sırayla fiziksel komutlar denenebilir:

1. Kilit aç
2. Kilitle
3. Bagaj aç/kapat
4. Camlar
5. Sürüş yetkilendirme

Her komut için `CommandReceipt` aşaması ve imzalı telemetri doğrulaması ayrı
kontrol edilir.

## 5. Sık karşılaşılan durumlar

| Belirti | Olası neden | İlk işlem |
|---|---|---|
| `carKey=yok`, `vehicleKeyRequest` tekrarı | Araç eşleştirmesi yok | Araç ekranından eşleştir |
| `CBErrorDomain code=7` | Araç oturumu kapattı | Eşleştirme/telemetri akışını kontrol et |
| `pairingLost` | iPhone/araç eşleşmesi silinmiş | İki taraftan eşleşmeyi sıfırla |
| `vehicleKeyMismatch` | Sunucu anahtarı eski | Sertifikayı yenile |
| `Araç saati okunamadı` | Zaman servisi yok | Bağlantıyı yeniden kur |
| `command_gate_rejected` | READY veya telemetri yok | READY ve telemetri tazeliğini kontrol et |

## 6. Sınırlar

- Bu runbook fiziksel doğrulama yerine geçmez.
- `carKey` gelmeden READY, kapı komutu veya proximity başarısı iddia edilmez.
- Loglarda VIN, telefon anahtarı, araç anahtarı ve ham imza paylaşılmaz.
