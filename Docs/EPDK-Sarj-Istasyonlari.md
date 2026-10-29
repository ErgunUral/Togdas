# EPDK şarj istasyonları (iOS uyarlaması)

## Kaynak ve mahremiyet

- Android 1.0.24.42 ile aynı kamu kataloğu kullanılır: `https://apigateway.epdk.gov.tr/sarjIstasyonlari`.
- API, `GET /sarjIstasyonlari` isteğinde `{}` gövdesi bekler. iOS 13+ `URLSession` GET gövdelerini reddettiğinden `App/EPDKStationService.swift` Network.framework TLS taşıması kullanır.
- EPDK'dan gelen ad, marka, işletmeci, adres, koordinat ve soket bilgileri sunucu verisidir. İstemci geocoding/Apple Maps araması yapmaz.
- iPhone konumu yalnızca cihaz içinde mesafe ve yarıçap filtresi için kullanılır; EPDK'ya gönderilmez.
- Kataloğun soket doluluğu/gerçek zamanlı uygunluk bilgisi sağlamadığı arayüzde açıkça belirtilir.

## Dayanıklılık

- Yanıt gövdesi 32 MB ile sınırlıdır ve önce geçici dosyaya akıtılır; URLSession'ın büyük yanıt sınırına takılmaz.
- `statusCode`, `numRows`, istasyon kimlikleri ve Türkiye koordinat sınırları doğrulanır.
- Normalize edilmiş katalog `Caches/EPDK/public-catalog-v1.json` konumunda saklanır.
- Başarılı katalog sorguları arasında yerel olarak en az 1 saat bulunur. EPDK 429 döndürürse `Retry-After` varsa uygulanır; yoksa 1 saat beklenir.
- Ağ hatasında son yerel katalog gösterilir; 24 saatten eski katalog uyarıyla işaretlenir.

## iOS arayüzü

- Yakın çevrede yarıçap filtresi (5–100 km) veya tüm katalogda metin araması.
- Halka açık istasyon filtresi, AC/DC soket filtresi, marka/işletmeci/adres araması.
- EPDK koordinatlarından harita iğneleri ve Apple Maps'e yol tarifi.
- Yakındaki listede en fazla 30 sonuç; konum izni yoksa tüm katalogda manuel arama yapılabilir.

## Sınırlar

- İlk katalog gövdesi yaklaşık 16 MB ve EPDK API kotası saatlik. İlk ağ alımı gerçek cihazda ayrıca doğrulanmalıdır; bu geliştirme oturumunda kamu API kotası kullanıldığı için aynı ağdan hemen tekrar indirme yapılamaz.
- Network.framework TLS doğrulaması kullanılır; taşıma sistem HTTP proxy ayarlarını URLSession kadar otomatik izlemeyebilir.
- API kataloğu istasyon kaydını gösterir; açık/kapalı olma, fiyat veya soketin o an boş/dolu olmasını doğrulamaz.
