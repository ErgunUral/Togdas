# iOS BLE tanı raporu

Android 1.0.24.42'nin son 60 dakika raporuna iOS karşılığı, Araç Komutları
BLE tanı günlüğü ekranında **BLE tanı özeti · son 60 dk** bölümüdür.

Rapor şu sayaç/özetleri gösterir:

- Tarama başlatma, hızlı→ısrarlı tarama devri ve sonuçsuz tarama
- Bağlantı, kopma, READY ve doğrudan yeniden bağlanma
- Bluetooth radyo açılma/kapanma olayları
- Sınıflandırılmış kopma/hata grupları
- RSSI örnek sayısı, minimum, ortalama, maksimum ve son ölçüm
- Eksik araç anahtarı ve telemetri imza doğrulama hatası

## Veri sınırı

- Son **500** olay bu iPhone'da tutulur; rapor bu kayıtların son bir saat içindeki
  bölümünden hesaplanır.
- RSSI tanı kaydı en fazla 30 saniyede bir yazılır; RSSI 5 dBm veya daha fazla
  değişirse daha erken örnek kaydedilir. Bu, hızlı yakınlık örneklemesinin tanı
  günlüğünü gereksiz büyütmesini önler.
- Paylaşım sadece toplu sayaçları içerir; ham olaylar, VIN, sertifika, anahtar
  veya paket verisi paylaşım metnine konmaz.
- Sayaçlar uygulamanın tuttuğu olaylara dayanır; 500 kayıt sınırına ulaşılırsa
  eski olaylar silinir ve geçmiş saat özeti eksik kalabilir.

## Kod

- Gruplama/özet: `Core/BLEDiagnosticReport.swift`
- Yerel kayıt ve RSSI örnekleme sınırı: `Core/BleConnection.swift`
- Ekran ve dışa aktarma: `App/CommandView.swift`
- Testler: `Tests/BLEDiagnosticReportTests.swift`
