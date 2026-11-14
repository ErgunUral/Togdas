# Fonksiyon envanteri ve kapsam keşfi

Tarih: 2026-11-14 · Kapsam: `App/` (33 dosya), `Core/`, `Widget/`, `Watch/`.
Yöntem: statik kod taraması + mevcut 35 UI testinin simülatör koşuları
(her menü öğesi ve sheet açılıyor) + 521 birim testinin eşlemesi.

Amaç: her kullanıcı işlevini tek tabloda toplamak ve şu üç sınıfa ayırmak:

- **A** — simülatörde otomatik test edilebilir
- **B** — fixture/hook eklemek gerekir
- **C** — fiziksel donanım/gerçek servis gerekir (manuel)

## 1. Ana yüzeyler

| ID | İşlev | Giriş noktası | Veri / durum | Sınıf | Mevcut kapsam |
|---|---|---|---|---|---|
| F01 | Giriş ekranı, Togg ID düğmesi | açılış (oturum yok) | yerel | A | Smoke 4/4 |
| F02 | Türkçe metinler (en_US sistemde) | `-AppleLanguages (en)` | yerel | A | Smoke |
| F03 | Pano başlığı, araç adı, bağlantı rozeti | `-uiTestFixture` | fixture | A | Smoke, Flow |
| F04 | Telemetri şeridi (akü %79, menzil 365) | Pano | fixture | A | Flow |
| F05 | 4 sekme (Genel Bakış, İklimlendirme, Trugo Şarj, Araç Durumu) | sekme çubuğu | fixture | A | Flow, Accessibility |
| F06 | Sekme seçili durumu + VoiceOver etiketleri | sekme çubuğu | yerel | A | Accessibility |
| F07 | 44 pt dokunma hedefleri | tüm sekmeler | — | A | Accessibility |
| F08 | XXXL Dynamic Type açılışı | launch arg | — | A | Accessibility |
| F09 | Bluetooth dijital anahtar kartı (boş/hata durumu) | Pano | BLE yok | A | Audit (genel), doğrudan değil |
| F10 | Yakınlık kartı: senaryolar düğmesi | Pano kartı | fixture | A | Guide |
| F11 | Yakınlık otomasyonu aç/kapat | Pano kartı | yerel ayar | A | Kısmi — kart Sportif/Teknik düzen testinde; toggle yok |
| F12 | Yakınlık kalibrasyon sheet'i | kart düğmesi | BLE sinyali | A (açılış) | Guide |
| F13 | Geofence: ev konumu ayarla/güncelle/sil | Pano kartı | konum izni | B | **yok** |
| F14 | Sürüş istatistikleri kartı | Pano | fixture | A | **yok** (yalnız görünür) |
| F15 | Şarj bütçesi kartı (boş veri) | Pano | UserDefaults | A | **yok** |
| F16 | Bakım kartı (boş veri) | Pano | UserDefaults | A | **yok** |
| F17 | Hızlı araç kontrolleri (kapı, klima, …) | Pano | BLE hazır değil → komut sheet'i | A (kapı) | Command (dolaylı) |
| F18 | Cam ve güvenlik bölümü | Pano | BLE | C | **yok** |
| F19 | İklimlendirme: aç/kapat, hedef sıcaklık | sekme | BLE/API | C (komut), A (görünüm) | Flow (görünüm) |
| F20 | Şarj sekmesi: şarj kartı + hesaplayıcı | sekme | fixture | A (kart), B (hesaplama) | Layout (hesaplayıcı), Flow (kart) |
| F21 | Trugo istasyon kartı | `-openChargingTab` | fixture | A | Flow |
| F22 | EPDK haritası/listesi | Şarj sekmesi | ağ + konum | B/C | **yok** (bilinçli) |
| F23 | Araç sağlığı: 12 V akü, lastikler, sürüş modu | sekme | fixture | A | Flow |
| F24 | Seyahatname (Sürüş & Şarj) | menü / şarj sekmesi | API | B | Navigation (yalnız açılış) |
| F25 | Seyahatname dönem seçici, grafik, dışa aktarma | iç ekranlar | API | B | **yok** |
| F26 | Araç detayı | menü | API | B | Navigation (açılış) |
| F27 | Servis kartı | menü | API | B | Navigation (açılış) |
| F28 | Hesap merkezi | menü | API | B | Navigation (açılış) |
| F29 | Bildirimler/destek/paketler alt ekranları | Hesap merkezi | API | B | **yok** |
| F30 | Senaryolar rehberi (canlı durum rozetleri) | menü / yakınlık kartı | yerel | A | Guide |
| F31 | Sesli asistan sheet'i | Pano | cihaz üstü | A (açılış) | Navigation |
| F32 | Sesli komut yürütme | sheet | mikrofon izni | C | **yok** |
| F33 | BLE kurulum rehberi (5 adım) | Pano kartı | yerel | A | Navigation |
| F34 | Aday anahtar seçimi | Pano kartı | BLE | A (açılış) | Navigation |
| F35 | Bluetooth taraması | menü | BLE | A (açılış) | Navigation |
| F36 | Komut kapısı ve 5 komut (kilit/aç/bagaj/sürüş) | menü / Pano | BLE | A (devre dışı) | Command |
| F37 | Onay istemi (hazır bağlantıda) | komut | BLE + araç | C | **yok** |
| F38 | Eşleştirme/sertifika/paylaşım bölümleri | komut sheet'i | BLE + API | C | **yok** |
| F39 | Tanı özeti/günlüğü paylaşımı | komut sheet'i | BLE | C | **yok** |
| F40 | Kilit teyit sesini dene | komut sheet'i | yerel | A | **yok** |
| F41 | Tema seçimi (3) ve kalıcılığı | menü | UserDefaults | A | Settings |
| F42 | Pano düzeni (4) ve kalıcılığı | menü | UserDefaults | A | Settings + Layout (Sportif/Teknik) |
| F43 | Araç seçimi (çoklu) | menü | fixture'da 1 araç | B | **yok** |
| F44 | Çıkış yap → giriş ekranı | menü | yerel | A | Settings |
| F45 | Hata bandı / çevrimdışı durumlar | çeşitli | ağ hatası | B | Kısmen (kapı metni) |

## 2. Menü ve sistem entegrasyonları

| Öğe | Tür | Kapsam |
|---|---|---|
| Araç detayı, Servis kartı, Seyahatname, Bildirimler & destek | navigasyon | açılış/kapanış (Navigation) |
| Senaryolar rehberi, Bluetooth komutları, Bluetooth taraması | sheet | açılış/kapanış (Guide, Command, Navigation) |
| Renk teması (3), Dashboard düzeni (4) | Picker | 2 tema + 2 düzen (Settings) |
| Çıkış yap | eylem | Settings |
| Araç seç (çoklu) | alt menü | **yok** |

Sistem yüzeyleri:

| Yüzey | İşlev | Test durumu |
|---|---|---|
| Widget (systemSmall/Medium) | Araç durumu + komut sonucu | **yok** (WidgetKit UI testi yok; snapshot store birim testli) |
| Watch uygulaması | Kilit/bağlantı/telemetri yaşı | **yok** (fiziksel watch) |
| Siri/App Intents | "Araç durumu", "Bu ay şarj harcamam" | **yok** (AppIntents test edilebilir ama kurulu değil) |
| Kısayollar (Shortcuts) | Kilit/aç, bagaj aç/kapat | **yok** (URL açma akışı) |
| Deep link / launch arg | `-openChargingTab`, `-openCommands`, `-openDriveExperience`, `-openDriveDetail`, `-openDriveCharges` | yalnız ikisi kullanılıyor |
| E2E harness | DEBUG senaryo yürütücü | **yok** |

## 3. Kapsam özeti

| Mercek | Değer |
|---|---|
| Yüzey (ekran/sheet) | 16 / 17 (%94) |
| Ana yüzey envanteri (F01–F45) | 14 tam/aktif test, 9 açılış-kapanış, 22 boşluk (ilk tarama 2026-11-14; güncel satır durumları tabloda) |
| Birim testi | 521 (Core mantığı: bütçe, bakım, sesli ayrıştırma, dışa aktarma, widget politikası) |
| UI testi | 39 |

Not: "Boşluk" her zaman hata değildir; bir kısmı B/C sınıfı olduğu için
simülatörde uçtan uca doğrulanamaz.

## 4. Öncelikli boşluklar (öneri sırası)

| # | Boşluk | Sınıf | Neden öncelikli | Önerilen yaklaşım |
|---|---|---|---|---|
| 1 | F24–F25 Seyahatname içerik durumları | B | Yüksek kullanıcı değeri, geniş mantık | fixture dönem verisi + boş/hata durumu |
| 2 | F15–F16 bütçe ve bakım kartları | B | Pano her açılışta görünür | `-uiTestSeedStores` hook'u |
| 3 | F42 Sportif/Teknik düzenler | A | 2 düzen hiç denenmiyor | ✅ 2026-11-14: kart sırası testi (`ToqdasLayoutTests`) |
| 4 | F20 şarj hesaplayıcı | A/B | Yanlış tutar riski | ✅ 2026-11-14: hedef değişimi + varsayım notu (`ToqdasLayoutTests`) |
| 5 | F11 yakınlık aç/kapat | A | Yanlış açık kalma riski | toggle + kalıcılık |
| 6 | F17 hızlı kontrol → komut yönlendirmesi | A | Kapı davranışı | BLE hazır değilken sheet'e düşme |
| 7 | F40 kilit teyit sesi | A | Yerel, izole | düğme → çalma durumu |
| 8 | F43 araç seçimi | B | Çoklu araç gerçek senaryo | ikinci fixture aracı + reset hook'u |
| 9 | F29 hesap merkezi alt ekranları | B | Destek/bildirim akışı | fixture API yanıtı |
| 10 | Deep link'ler (`-openDrive*`) | A | Açılış yolları test dışı | arg başına açılış dumanı |

3 ve 4 numaralı boşluklar 2026-11-14'te kapandı (4 yeni UI testi);
sıradaki adım 2 (bütçe/bakım seed hook'u) ve 1 (Seyahatname fixture).

## 5. Bilinçli kapsam dışı

- Gerçek Togg ID girişi (üretim servisi), EPDK ağ haritası.
- BLE eşleştirme/sertifika/paylaşım, onaylı komut gönderimi (araç gerekir).
- Widget/Watch/Siri/Kısayollar uçtan uca (fiziksel cihaz/OS entegrasyonu).
- Dynamic Type `.dynamicType` denetimi ve kontrast (gerekçeler:
  `Docs/Erisilebilirlik.md`).
