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
- [x] Veri kanalı kod + cihaz kanıtıyla doğrulandı: `toqdas.watch.updatedAt.v1`
  19:57:33, snapshot dolu, complication app group kaydı ✓
- [x] **Complication VIN'siz** (13.11 akşam, `0b1a446`): `complicationCopy` +
  `WatchLink` süzgeci; cihazda `vin = ""`, gösterim alanları korunuyor ✓
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

## Loglardan çıkan iş planı (13.11 akşam ayrıştırması — onaylı sıra)

### A. `pairing_lost` kök nedeni (17 + 14) — öncelik 1
- Kanıt: 17'de 19:42:29 + 19:49:13 `pairing_lost · eşleşme bilgisi geçersiz`;
  19:44'te kendiliğinden `Komut hazır`. Uzun oturum + sık reconnect sonrası.
- Adımlar:
  1. Tekrarladığı anda **tam olay dizisi** kaydı: tanı plist (flush için
     uygulamayı arka plana al) + aynı saatteki `araç oturumu kapattı` satırları.
  2. Aday kök nedenler: session/nonce ömrü; ardışık reconnect'te eşleşme
     anahtarı geçersizleşmesi; araç tarafı oturum kapatma korelasyonu.
  3. Karar: yalnız yeniden eşleştirme mi, yoksa kodda dayanıklılık düzeltmesi mi.
  4. 14 sürekli aynı hatada → 14 için yeniden eşleştirme kararı ayrıca verilir.

### B. Kilit teyidi (4. adımın kalanı) — öncelik 2 (araç başı)
- Kanıt: `automatic_command_failed · kilit durumu doğrulanamadı` ×4, hepsi kapı
  açıkken (`doors=[1,0,0,0]`); kapılar kapanınca 19:37:30 `Kilitli
  doors=[0,0,0,0]` ✓. Kod değişikliği gerekmiyor — doğrulama işi.
- Adımlar: kapılar kapalı + araç Bekleme → uzaklaş → çift bip + imzalı
  telemetri teyidi + oto-kapatma sayacı; teyitsiz 30 sn senaryosu.

### C. Yaklaşma → açma (3. adım) — öncelik 3 (araç başı)
- Kanıt: açmalar "araç bekleme durumunda değil" ile atlandı (doğru davranış);
  tek bilet/gecikme guard'ları akşamdan ✓.
- Adımlar: araç Bekleme'deyken yaklaş → aç; 2. yaklaşmada komut yok; yeni
  döngüde tekrar aç; kanıt satırı `Yakınlık otomasyonu kilit açma biletiyle…`.

### D. Saat/widget ekran kanıtı (5. adım) — öncelik 4 (kullanıcı)
- Saat + widget ekran görüntüsü; tazelik rozeti tonu; yeni metin
  "Yakınlık otomasyonu telefonda açık — saat yalnızca görüntüler".

### E. Sessiz başarısızlık kapatıldı — **TAMAM ✓** (13.11, `a53d1be`)
- `Core/ProximityCommandNotice`: otomatik komut sonucu → yerel bildirim
  (doğrulanamadı / başlatılamadı). Yalnız yakınlık kaynaklı komutlar,
  60 sn penceresi; "komut yeniden gönderilmedi" metni.
- Açma doğrulaması zaten BLE katmanındaydı (`pendingLockVerification`);
  eksik olan bildirimdi. +7 test (459/459).

### F. `pairing_lost` kurtarma rehberi — **TAMAM ✓** (13.11, `83d62bd`)
- `Core/PairingRecovery`: başlık + 3 adım + özet tek kaynak; banner ve
  bildirim aynı metni kullanır. "Bu tamamlanana kadar otomatik komut
  gönderilmez" — davranışa sadık; VIN görünür metinde yok.
- Dashboard: `needsRepair` banner'ı Core metinlerine bağlandı; kurtarma
  bildirimi araç başına **günde bir** (`StorageKeys.pairingRecoveryNotified`).
- Not: iOS'ta BLE bağı OS seviyesinde; uygulama silemez — doğru kurtarma
  cihaz ayarlarından unutup yeniden eşleştirmektir (rehber bunu söyler).
- +5 test (464/464).

### G. Retry politikası — **karar: retry yok** (13.11, onaylı varsayılan)
- `automatic_command_failed` sonrası aynı döngüde yeniden deneme yok.
- Gerekçe: bildirim + kullanıcı kontrolü; çift komut/çift bip ve yanlış
  kilitleme riski düşük tutulur.

### H. Geofence ↔ yakınlık çakışması — **TAMAM ✓** (`22dbfc4`)
- Bulgu: `ToqdasApp` geofence kapanışları yakınlık guard'larını atlayıp
  doğrudan `ble.unlock()/lock()` çağırıyordu.
- `Core/AutomaticCommandLedger` (saf, testli): kaynak (proximity/geofence)
  + eylem başına son komut zamanı; ikinci kaynak 30 sn içinde komut
  göndermez (`geofence_unlock_skipped` / `proximity_lock_skipped`).
- +7 test (471/471).

### I. Kalibrasyon eskimesi — **TAMAM ✓** (`9543964`)
- `Core/ProximityCalibrationAge`: 30 gün eşiği, takvim günü hesabı; hiç
  kalibre edilmemiş durum uyarı üretmez. Ölçüm anı `ProximitySettings`
  içinde VIN bazlı saklanır; sıfırlamada temizlenir.
- Yakınlık kartında bilgilendirme notu (turuncu, komut/otomasyon etkisi
  yok). +6 test (477/477).

### J. İki telefon aynı VIN — **bilinen sınır, kod yok**
- İki iPhone da eşleşirse ikisi bağımsız otomatik komut üretebilir
  (çift bip / çakışma). Cihazlar arası koordinasyon yok (sunucu/ortak
  oturum gerekir).
- Karar: **tek aktif anahtar telefon** önerilir; ikincisi gözlemci
  kalmalı. Doküman notu; ileride sunucu tarafı kilit gerekirse ayrı iş.

### K. Saat tanısı — **TAMAM ✓** (`26486ea`)
- `Core/WatchDiagnostics`: saat UserDefaults'unda halka tampon
  (`toqdas.watch.diagnostics.v1`, 40 olay, mesaj 160 karakter).
- Kayıt noktaları (`Shared/WatchLink`): snapshot alındı, yenileme
  istendi/reddedildi/iletilemedi, komut sonucu (`status`), oturum
  etkinleşti, telefon erişilebilir/erişilemiyor.
- VIN/token yazılmaz; UI'da gösterilmez, komut/ağ kullanımı yok.
- Okuma: saatten plist çekimi (`com.toqdas.ios.dev.watchkitapp`),
  `toqdas.watch.diagnostics.v1` anahtarı. +6 test (483/483).
- **Cihaz kanıtı (13.11):** saat build + kurulum + launch ✓;
  `watch-tani.plist` olayları: `oturum etkin · erişilebilir=hayır`,
  `snapshot alındı` ×3, `telefon erişilebilir`, `telefon erişilemiyor`.
  Yani saat veriyi gerçekten alıyor; sorun veri gelmemesi değil.

### L. Kimlik doğrulama “sürekli kopuyor” — **TAMAM ✓** (`02fc072`)
- **Teşhis (13.11 logları, 18:32–18:51):** 8 kimlik doğrulamanın 8’i
  `Komut hazır`a ulaştı (sertifika akışı sağlam). Kopan katman oturum:
  9 kopma (5 araç kapattı, 4 zaman aşımı), RSSI −89…−98, oturum
  ömürleri 59/44/44/3/0 sn. 2× `pairing_lost` (araç eşleşme kaydını sildi).
- **Kök neden 1:** `BleConnection.start()` `needsRepair`i sıfırlıyordu →
  onarım durumu unutulup otomatik denemeler aynı iOS hatasına çarpıyordu.
  Çözüm: onarım kilidi (`BleReconnectPolicy.shouldStartConnection`).
  Otomatik yollar (geri çekilme, ön plan, yakınlık) kilidi açamaz; yalnız
  “Adımları tamamladım, yeniden dene” (`retryAfterRepair`) veya Komutlar
  ekranındaki elle bağlan açar.
- **Kök neden 2:** Zayıf sinyalde 8 denemelik döngü radyoyu/pili yoruyordu.
  Çözüm: üst üste 3 zayıf kopmada denemeler 60 sn (`weak_drop` tanısı);
  ön plana gelince sayaç sıfırlanır.
- +3 test (486/486). Araç 60 sn’de oturumu kapatmayı sürdürür (tasarım);
  her bağlantıda sertifika yenilenir, bu normaldir.

### M. Tutarlı yapı — tek yaşam döngüsü + dijital imza kimliği (`c987c60`)
- **A. Tek sahip:** `DashboardView` içindeki `reconnectTask`,
  `reconnectAttempts`, `stableConnectionTask`, `autoKeyStarted` kaldırıldı.
  Bağlantı yaşam döngüsünün tek sahibi `BleLinkCoordinator`.
- **B. Faz modeli:** `Core/BlePhase` + `BlePhaseMachine` (saf, testli).
  Öncelik: onarım > radyo kapalı > eşleştirme > bağlantı fazı. UI başlığı
  artık `model.link.phase.label`dan türer; “bağlı görünüp onarım isteyen”
  çelişkili gösterim imkânsız.
- **C. Dijital imza kimliği:** `Core/KeyIdentity` — açık anahtarın SHA-256
  ilk 4 baytı (8 hex) her auth’ta karşılaştırılır. Anahtar değişmişse
  **sessiz devam yok**: `repair_required` + açıklama, otomatik deneme durur.
  Sertifika parmak izi değişimi yalnız tanıya yazılır (`certificate_rotated`).
- **D. Kalıcılık:** `Core/PairingRepairState` + `PairingRepairStore`
  (`toqdas.pairing.repair.<vin>`): onarım gereksinimi uygulama kapanıp
  açılınca korunur; yalnız kullanıcı “yeniden dene” temizler.
  `Core/ReconnectBudget`: deneme/zayıf sinyal/eşleştirme sayaçları tek tip.
- **E. Faz günlüğü:** `Core/BlePhaseLog` (`toqdas.ble.phase.v1`, son 20
  geçiş + neden). Cihaz kanıtı: `22:28:57 connecting · Araç aranıyor…`.
- +25 test (511/511).

### N. “Araç başka bir telefon anahtarına bağlı” (`c1f27d8`)
- Sunucu yanıtı yalnız `resultEnum` taşıyor (`OverwriteDetection`,
  `OwnerChange`, `NotOwner`); başka telefonun kimliği gelmiyor. Bu yüzden
  uyarıda “hangi telefon” gösterilemiyor.
- `Core/ClaimResponseShape`: çakışma yanıtının **anahtar adları + tip +
  uzunluk** kaydı (`toqdas.claim.shape.v1`). Değer yazılmaz (e-posta,
  telefon, cihaz adı sızmaz). Bir sonraki saha olayında plist'ten alan
  listesi okunur; maskeli kimlik alanı varsa sonraki adımda gösterilir.
- Uyarı metni dürüstleştirildi: “hangi telefon olduğu sunucu tarafından
  paylaşılmıyor” + iki eylem (sahip anahtarını taşı / paylaşım daveti iste).
- +5 test (516/516).
