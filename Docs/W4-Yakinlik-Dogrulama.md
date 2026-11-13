# W4 — Araç Başı Yakınlık Otomasyonu Doğrulama Listesi

Tarih: 2026-11-13 · Durum: kısmi — 1. adım + 2. adım akşam testiyle tamam
Sıralama onaylandı (kullanıcı, 2026-11-13). Her adımda kanıt: tanı log satırı
veya ekran görüntüsü (`~/Desktop/toqdas-analiz/w4-hazirlik/` altına).

## 1. Kalibrasyon (ilk iş — otomasyon bununla çalışır) — **TAMAM ✓**
- [x] Kalibrasyon yapıldı (13.11 akşam): **near=-61 / far=-86 → fark 25 dB ≥ 14 ✓**
  - Oto-öneri de çalıştı: `proximity_autocal · öneri yakın=-45 uzak=-91 fark=46`
  - Kanıt: `w4-hazirlik/17-Simdi.plist` (yeni anahtarlar `toqdas.proximity.near/far`)
- [x] Otomasyon açıldı, saha testinde aktif

## 2. 17 → READY (sahiplik/anahtar) — **TAMAM ✓**
- [x] Araç ekranı onayı verildi; `cert_present · sunucu araç anahtarı **var**`
- [x] `Komut hazır` + imzalı telemetri (`İmzalı araç durumu: lock=… power=…`)
- [ ] Kalan: akşamki **aralıklı `pairing_lost`** gözlemi kayıt altına (aşağıda)

## 3. Yaklaşma → otomatik açma döngüsü — **bekliyor**
Akşam testinde açma denemeleri "araç bekleme durumunda değil" ile atlandı
(araç Aksesuar/doğrulanıyor modundaydı — doğru davranış). Bu yüzden açma
komutunun kapıları gerçekten açtığı henüz doğrulanmadı.
- [ ] Araç **Bekleme** modundayken yaklaş → tek `kilit açma`; kapılar açılsın
- [ ] Aynı döngüde 2. yaklaşma → **yeni komut yok** (tek bilet)
- [ ] Yeni döngü: tekrar uzaklaş (teyitli) → yaklaş → yine açar
- [x] Guard gözlemleri akşamdan işliyor: arka planda komut yok ✓,
  fresh cycle mesajları ✓, `proximity_latency · 1046/2100 ms` ölçüldü ✓
- [ ] Kanıt: `Yakınlık otomasyonu kilit açma biletiyle…` satırı

## 4. Uzaklaşma → otomatik kilit döngüsü — **kısmi**
- [x] Uzaklaş → cam kapatma + kilit akışı 3 kez başladı; nonce + imzalı
  komut + `command_ack` zinciri uçtan uca çalıştı ✓
- [ ] **Kalan:** kapılar **kapalıyken** uzaklaş → imzalı telemetri teyidi +
  **çift bip**; akşam 4 kez `automatic_command_failed · kilit durumu
  doğrulanamadı` — test sırasında kapı açıktı (`doors=[1,0,0,0]`);
  19:37:30'da `Kilitli doors=[0,0,0,0]` doğrulandı (kapılar kapanınca)
- [ ] Teyitsiz 30 sn → sayaç başlamaz ("Kilit telemetrisi doğrulanmadı…")
- [x] Kapı açıkken kilitlenmez ✓ (akşam gözlemiyle uyumlu)
- [ ] Süre dolunca otomasyon kapanır
- [ ] Kanıt: çift bip + `lockConfirmationCount` satırları
- Not: 19:37:22-57 arası 1-2 sn'lik yaklaş/uzaklaş salınımı (eşik merkezine
  yakın durma) — normal, gerçek kullanımda tolerans izlenecek.

## 5. Saat + widget veri kanalı — **bekliyor**
- [x] Saat uygulaması Watch Ultra 2'ye yeniden kuruldu ve launch OK (13.11)
- [ ] Complication/widget verileri doluyor mu? (app group kayıtlı ✓)
- [ ] `WatchSnapshotThrottle` 30 sn davranışı
- [ ] Tazelik rozeti: bilgi yok → gri, eski → turuncu (doğru ton)
- [ ] Kanıt: saat + widget ekran görüntüleri

## 6. Eşleşme bilgisi geçersiz (`pairing_lost`) — **17'de de görünüyor, ikisini kapsar**
- [x] 14: sürekli `pairing_lost` — yeniden eşleştirme adayı
- [ ] **17: aralıklı `pairing_lost`** (19:42:29 + 19:49:13; 19:44'te kendiliğinden
  `Komut hazır`'a döndü). Uzun oturum + sık reconnect sonrası oluşuyor.
  Akşamki plist: `w4-hazirlik/17-Simdi.plist`.
- [ ] 17'de tekrar oluşursa: tam olay dizisini kaydet → kök neden (session/nonce
  ömrü?) 14 için de aynı kurtarma mı?
- [ ] Karar: 14 yeniden eşleştirilir mi, yoksa gözlemci mi kalır?
- [ ] Flush notu: plist yalnız uygulama arka plana alınınca yazılır.

## Başlangıç durumu (13.11 öğlen çekildi)
- 17: `pairing_wait`/`vehicleKeyMissing` döngüsü, proximity kapalı, profil
  balanced, oto-kapatma açık. Plist: `w4-hazirlik/17-Once.plist`.
- 14: `pairing_lost · eşleşme bilgisi geçersiz`. Plist: `w4-hazirlik/14-Once.plist`.
- Saat: app group'lu build kurulu, uygulama başlatıldı.

## Akşam saha testi kaydı (13.11 19:32-19:49, kullanıcı testi)
- İmzalı komut zinciri ilk kez gerçek araçta uçtan uca çalıştı: nonce →
  imzalı "Kapı kilidinden önce camları kapat" → ack → "Kilitle" → ack (3 kez).
- Arka plan sınırı ve fresh-cycle guard'ları beklenen davrandı.
- Açık konular: kilit teyidi (kapalı kapıyla), aralıklı pairing_lost (17+14).
