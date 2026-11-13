# W4 — Araç Başı Yakınlık Otomasyonu Doğrulama Listesi

Tarih: 2026-11-13 · Durum: bekliyor
Sıralama onaylandı (kullanıcı, 2026-11-13). Her adımda kanıt: tanı log satırı
veya ekran görüntüsü (`~/Desktop/toqdas-analiz/w4-hazirlik/` altına).

Ön koşullar (araç başına giderken):
- iPhone 17 Pro Max USB'de bağlı, Xcode açık.
- 17'de oto-kapatma süresi kısa seçilmiş (örn. 1 dk) — test hızlanır.
- Araç beklemeye geçmiş (powerState == 2) ve kapılar kapalı.

## 1. Kalibrasyon (ilk iş — otomasyon bununla çalışır)
- [ ] 17'de Yakınlık ayarını aç (`toqdas.proximity.enabled` bugün False başlıyor)
- [ ] Kalibrasyon: araç yakınında ölçüm → uzakta ölçüm
- [ ] Şart: yakın−uzak **≥ 14 dB**; sağlanmazsa RSSI düzelt (farklı mesafe/kapı konumu)
- [ ] Kanıt: kalibrasyon sonucu (yakın/uzak dB), üretilen eşikler

## 2. 17 → READY (sahiplik/anahtar)
- [ ] Araç ekranında dijital anahtar eşleştirme onayı
- [ ] 17 uygulamasında `pairing_wait` → READY geçişi
- [ ] Kanıt: tanı akışı (plist: `w4-hazirlik/17-Sonra.plist`), READY + telemetri

## 3. Yaklaşma → otomatik açma döngüsü
- [ ] Uzaklaş → uygulama "uzaklaşma eşiği doğrulandı" görsün
- [ ] Yaklaş → tek `kilit açma` komutu; kapılar açılsın
- [ ] Aynı döngüde 2. yaklaşma → **yeni komut yok** (tek bilet)
- [ ] Yeni döngü: tekrar uzaklaş (teyitli) → yaklaş → yine açar
- [ ] Guard testleri:
  - [ ] Uygulamayı arka plana/öne al (RSSI bayatlasın) → 30 sn hold, açma yok
  - [ ] BLE oturumu yenilendiğinde → önce uzak taban bekleniyor (fresh cycle)
- [ ] Kanıt: tanı satırları `proximity_latency · …`, `Yakınlık otomasyonu kilit açma biletiyle…`

## 4. Uzaklaşma → otomatik kilit döngüsü
- [ ] 4 kapı kapalıyken uzaklaş → cam kapatma + kilit akışı
- [ ] **İmzalı telemetri teyidi**: çift bip; teyit sonrası oto-kapatma sayacı başlar
- [ ] Teyitsiz 30 sn → sayaç başlamaz ("Kilit telemetrisi doğrulanmadı…")
- [ ] Kapı açıkken uzaklaş → **kilitlenmez** ("kapılar kapalı doğrulanmadı")
- [ ] Süre dolunca otomasyon kapanır, komut gönderilmez
- [ ] Kanıt: tanı satırları + ekran görüntüsü (proximityStatus metinleri)

## 5. Saat + widget veri kanalı
- [ ] App group artık kayıtlı (4 profil doğrulandı): complication/widget verileri doluyor mu?
- [ ] `WatchSnapshotThrottle` 30 sn davranışı (veri tazelenmesi)
- [ ] Eski/eski veri rozeti: bilgi yok → gri, eski → turuncu (doğru ton)
- [ ] Kanıt: saat + widget ekran görüntüleri

## 6. iPhone 14 — kilit doğrulama hatası
- [ ] 14'te aynı senaryo (build kurulu ✓)
- [ ] 14 plist incelemesi (`w4-hazirlik/14-Once.plist` çekildi):
  **`pairing_lost · eşleşme bilgisi geçersiz`** — 14'ün BLE eşleşme bilgisi
  geçersiz; sertifika akışına gidemiyor. Kök neden bu olabilir (kilit teyidi
  değil, eşleşme).
- [ ] Karar: 14 yeniden eşleştirilir mi, yoksa gözlemci mi kalır?
- [ ] Flush notu: plist yalnız uygulama arka plana alınınca yazılır.

## Başlangıç durumu (bugün çekildi, 2026-11-13)
- 17: `pairing_wait`/`vehicleKeyMissing` döngüsü, proximity kapalı, profil
  balanced, oto-kapatma açık. Plist: `w4-hazirlik/17-Once.plist`.
- 14: `pairing_lost · eşleşme bilgisi geçersiz`. Plist: `w4-hazirlik/14-Once.plist`.
- Saat: app group'lu build kurulu, uygulama başlatıldı.
