# App Store başvuru taslağı

Bu belge App Store Connect gönderimi için taslak metinleri ve gizlilik anketi
önerilerini toplar. URL'ler ve kesin beyanlar ürün sahibinin onayı ile
kesinleşir; henüz onaylanmamış her madde **[onay gerekli]** olarak işaretlidir.
Taslak, fiziksel araçta doğrulanmamış özellikler için başarı iddiası taşımaz.

## 1. Temel bilgiler

- Uygulama adı: **Toqdas** [onay gerekli]
- Alt metin (30 karakter sınırı): "Togg araç durumu ve dijital anahtar"
- Birincil kategori: **Navigasyon** (araç konumu/yakınlık) [onay gerekli]
- İkincil kategori: **Yaşam Tarzı** (araç kontrolü) [onay gerekli]
- Yaş sınıfı: **4+** (reklam, analitik, kullanıcı üretimi içerik yok)
- Bağlı kimlik sağlayıcı: Togg ID OAuth (`toggid.togg.cloud`); araç verisi ve
  komutlar Togg servisleri üzerinden. Geliştiricinin kendi veri toplayan
  sunucusu yok.

## 2. Meta veri metinleri

### Tanıtım metni (taslak)

> Toqdas, Togg aracının bulut telemetrisini ve dijital anahtarını tek ekrandan
> göstermek için hazırlanmış bağımsız bir iPhone uygulamasıdır.
>
> • Araç durumu: batarya, menzil, kilit, kilometre, dış sıcaklık
> • Bluetooth Dijital Anahtar eşleştirmesi ve kilit/bagaj komutları*
> • Ay içi şarj harcaması ve dönem özetleri
> • Sürü deneyimi ve karşılaştırma özetleri (Togg Drive Experience servisleri)
> • EPDK şarj istasyonu kataloğu
> • Apple Watch gösterimi (komutlar iPhone üzerinden yürütülür)
>
> Oturum açmak için Togg ID hesabı gerekir. Uygulama Togg servislerine
> bağlanır; kendi sunucularımız veri toplamaz.
>
> * Araç komutları yalnızca dijital anahtar eşleştirmesi ve araç kimlik
>   doğrulaması tamamlandıktan sonra etkinleşir (araç gerekir).

### "Yenilikler" metni (v0.1.0)

> • Pano açılışında son bilinen batarya/menzil önbellekten görünür
> • Araç seçimi değişince önceki aracın değerleri yeni seçime sızmaz
> • Widget tazelik rozetinde bulut telemetri zamanı gösterilir
> • Erişilebilirlik: üst araç kartı Dynamic Type ile ölçeklenir

### Anahtar kelimeler ( toplam ≤100 karakter )

- Önerilen set (87/100 karakter): `togg,araba bulun,dijital anahtar,arac kilidi,sarj istasyonu,EPDK,elektrikli araba,watch`

  Kalan ~13 karaktere "lastik basinci" (14) tam sığmaz; eklenmek istenirse
  "elektrikli araba" ile değiştirme, onayda değerlendirilir. [onay gerekli]

## 3. Hesap silme akışı (taslak)

- Giriş yalnız Togg ID OAuth akışıyla yapılır; hesap Togg ID tarafındadır.
  **Hesap silme, Togg ID kanalından gerçekleştirilir.** Uygulama içi silme
  ekranı yoktur.
- "Oturumu kapat" yalnız yerel oturumu siler: sunucu oturumu kapatılır,
  Keychain'deki belirteçler silinir, bulut önbelleği ve VIN bazlı kayıtlar
  temizlenir, saat bağlantısı sıfırlanır.
- App Review'a verilecek not: "Hesap silme, Togg ID hesap yönetimi üzerinden
  yapılır" + Togg ID destek/hesap yönetimi URL'si. [onay gerekli — URL]

### 3.1 Hesap silme yönlendirme sayfası metni (web'e host edilecek)

> **Toqdas hesabı nasıl silinir?**
> Toqdas, oturumunu Togg ID hesabınla açar; uygulama kendi hesap kaydını
> oluşturmaz ve kendi sunucularında veri tutmaz. Bu nedenle hesabının ve
> verilerinin silinmesi Togg ID hesap yönetiminden yapılır:
> [Togg ID hesap yönetimi bağlantısı — onay gerekli]
>
> Uygulama tarafında: "Oturumu kapat" seçenek, yerel oturumu tamamen siler;
> cihazındaki dijital anahtar kaydı, önbellek ve bildirim tercihleri
> kaldırılır. Uygulamayı yeniden açtığında tekrar oturum açman gerekir.
>
> Soruları için: [destek e-posta] [onay gerekli]

## 4. Gizlilik anketi önerileri (App Store Connect)

Temel kaynak `Docs/Gizlilik.md`. Önerilen minimum beyanlar:

| Veri türü | Toplanıyor mu? | Amaç | Hesapla bağlantılı? | İzleme için? |
| --- | --- | --- | --- | --- |
| Kimlik > Kullanıcı kimliği (Togg ID) | Evet (oturum için Togg servisine iletilir) | Uygulama işlevi | Evet | Hayır |
| Konum > Hassas olmayan konum (araç konumu) | Evet (Togg servisi üzerinden gösterime gelir) | Uygulama işlevi | Evet | Hayır |
| Diğer veri > Araç telemetri özeti (batarya, menzil, kilit, komut sonuçları) | Evet (Togg servisi üzerinden) | Uygulama işlevi | Evet | Hayır |
| Konum (cihaz konumu, yakınlık/geofence) | Koşullu — özellik açıkken | Uygulama işlevi | Hayır | Hayır |
| Ses verisi | Hayır — kayıt saklanmaz, tanıma cihaz üstünde (`requiresOnDeviceRecognition`) | Uygulama işlevi | Hayır | Hayır |

Netleştirilecek noktalar [onay gerekli]:

- Araç konumu "toplanan veri" kapsamında mı beyan edilecek (öneri: evet,
  Togg servisi üzerinden).
- Yakınlık/geofence izin metinlerinin fiziksel cihaz testinde gözden geçirilmesi.
- Ses tanıma davranışının anketin güncel soru setinde hangi başlığa düştüğü.

## 5. Gönderim öncesi kontrol listesi

1. [ ] Gizlilik politikası URL'si yayınlanır (temel: `Docs/Gizlilik.md`). [onay gerekli — domain]
2. [ ] Destek URL'si / e-posta adresi kararlastırılır. [onay gerekli]
3. [ ] Hesap silme (Togg ID) yönlendirme metni ve URL'si. [onay gerekli]
4. [ ] App Store Connect gizlilik anketi, §4'teki beyanlarla doldurulur.
5. [ ] Fiziksel cihaz + gerçek araç smoke testi: eşleştirme, READY, kilit/bagaj, watch eşleşmesi (`Docs/BLE-Eslesme.md`, `Docs/Ble-Dayanklilik.md`).
6. [ ] App Review notları: test hesabı/davet (demo gerekiyorsa) ve BLE bağlantı video kaydı gerekebilir. [onay gerekli]

## 6. App Review'a sunulacak notlar (taslak)

> Toqdas, Togg servileriyle konuşan bağımsız bir iPhone istemcisidir.
> - Giriş: Togg ID OAuth ekranı; test için demo hesap sağlanabilir [onay gerekli]
> - BLE komutları (kilit/aç/bagaj/cam) yalnız dijital anahtar eşleştirmesi
>   + araç kimlik doğrulaması sonrası kullanılabilir; video kaydı ek veya
>   URL üzerinden gösterilebilir [onay gerekli].
> - Uygulama kendi sunucu tarafı veri toplamıyor: gizlilik beyanı yalnız
>   Togg servisi üzerinden geçen verileri kapsar.
> - Hesap silme: Togg ID hesap yönetimi kanalından yapılır (bkz. §3.1).
> - Siri/Shortcuts yalnız kapalı komut seti kullanır; serbest metin komut
>   yürütmüyor. Ses verisi cihaz üstünde tanınır (`requiresOnDeviceRecognition`),
>   kayıt saklanmaz.
> - Widget salt okunur; komut göndermez, VIN/anahtar malzemesi görüntülemez.
> - Yakınlık otomasyonu yalnız ön planda çalışır; arka planda araç komutu
>   gönderilmez.

## 7. Kullanıcının tamamlaması gerekenler [onay gerekli — hepsi]

1. Domain kararı + gizlilik politikası sayfasının yayınlanması
   (temel metin `Docs/Gizlilik.md`, HTML'e sarılıp host edilir).
2. Destek kanalı (e-posta ya da sayfa) kararı + URL.
3. Hesap silme yönlendirme URL'si (§3.1 metni host edilir).
4. Anahtar kelimeler son onayı (§2 öneri).
5. Kategori onayı: birincil **Navigasyon**, ikincil **Yaşam Tarzı** — ya
   da ikincil **Araçlar** tercihi.
6. Fiziksel araç smoke testi + BLE bağlantı video kaydı.
7. App Store Connect "Gizlilik" anketine §4 tablosuyla aynen giriş.

## 8. Sürüm notu

Bu belge yalnızca taslaktır; App Store Connect ekranlarındaki son değerler
onaylandıkça "[onay gerekli]" işaretleri kaldırılır ve belge gerçek başvuruyla
eşleştirilir.
