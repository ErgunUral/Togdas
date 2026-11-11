# Playwright Test Planı — Togg KeySharing Web UX — 2026-11-12

## 1. Amaç ve kapsam

**Amaç:** `share.togg.cloud/KeySharing` BLE dijital anahtar paylaşım linkinin **web UX durumlarını**
Playwright ile doğrulamak.

**Kapsam dışı (bilinçli):**
- EPDK şarj istasyonu hattı — canlı keşifte doğrulandı: `apigateway.epdk.gov.tr` UI'siz API yüzeyi
  (GET → 400, kök → 404, portal yok). UX/UI yalnızca iOS tarafında; Playwright web planı üretilmedi.
- Geçerli (canlı) paylaşım linki üretimi — gerçek cihaz oturumu gerektirir, saha doğrulamasıdır.
- iOS native UI metinleri (`Araç durumu`, `12 V` vb.) — web'e bakan yüzeyde değildir.

## 2. Kritik yol senaryoları

| # | Senaryo (tek cümle) | Beklenen sonuç | Durum |
|---|---|---|---|
| K1 | Geçersiz `seId` (kısa/base64 dışı) içeren link tarayıcıda açılır | 4xx; render edilebilir bir hata sayfası ya da hatasız boş yanıt; çökme/5xx yok | **keşifte doğrulandı** (ERR_HTTP_RESPONSE_CODE_FAILURE, 4xx) |
| K2 | Mükerrer `seId` parametresi (`seId=A&seId=A&no=B`) | 4xx; iOS URL doğrulayıcıyla aynı reddetme mantığı [doğrulanmadı — sunucu davranışı] | plan |
| K3 | Link sonunda `#fragment` olduğunda | Fragment yoksayılır ya da 4xx; iOS parite: fragment'lı URL reddedilir [doğrulanmadı] | plan |
| K4 | `userinfo@` içeren URL (`https://user@share.togg.cloud/...`) | 4xx / reddetme; iOS parite ile tutarlılık [doğrulanmadı] | plan |
| K5 | Yanlış host varyantı (`togg.cloud.evil.example`, `http://` düşürülmüş TLS) | Bağlantı kurulamaz ya da 4xx; iOS tarafı zaten reddediyor (KeySharingTests) | plan |
| K6 | Yanlış yol (`/notKeySharing`) | 4xx; doğru yol yalnız `/KeySharing` | plan |
| K7 | **Geçerli link** (gerçek cihaz oturumundan) açıldığında paylaşım/onay UX'i render edilir | Sayfa görünür, token/seId değeri DOM/log/ekran görüntüsünde **geçmez** | **saha doğrulaması** — Playwright dışı |

## 3. Veri kuralları (Invariants)

- Test malzemesi yalnızca **dummy** değerler (ToqdasIOS `Tests/KeySharingTests.swift` örnekleri: `seId=AQIDBAUG&no=BwgJCgsM`).
  Gerçek VIN, token, cihaz kimliği **kullanılmaz**; test çıktısı, isimler, ekran görüntüsü adları da aynı kurala tabi.
- Konum senaryoları plana konulmadı — telefon konumu hiçbir yüzeyle paylaşılmaz (iOS kuralı).
- Eksik/boş yanıt `0`'a çevrilmez; hata kodu + boş render ayrı bir UX durumu olarak kaydedilir (K1'de kanıtlandı).

## 4. Ortam ve önkoşullar

- Yüzey: `https://share.togg.cloud/KeySharing` — **oturumsuz, public** (negatif durumlar için).
- Araç: Playwright (TypeScript, `browser_navigate` + HTTP status + snapshot DOM kontrolü).
- storageState gerekmez — KeySharing linki cihaz kimliğiyle değil, link içindeki parametrelerle taşınır [doğrulanmadı — canlı link akışı saha testinde teyit edilmeli].
- Koşu frekansı düşük tutulur (bilinmeyen rate-limit'e karşı; EPDK'da 429 kota dersi alınmıştır).

## 5. Riskler ve bilinmeyenler

- **[onay gerekli]** Sunucunun (share.togg.cloud) negatif durumlar için HTML hata sayfası mı yoksa salt HTTP
  status mu döndüreceği — keşifte tarayıcı render yapmadı; UX hedefi (kullanıcıya anlamlı hata ekranı) için
  ürün tarafıyla konuşulmalı.
- **[doğrulanmadı]** K2–K5'te iOS doğrulayıcı paritesinin sunucu tarafında da geçerli olup olmadığı.
- **[doğrulanmadı]** Geçerli linkin ömrü, tek kullanımlık olup olmadığı, süresi dolan linkin UX'i (K7 alt senaryosu).
- Sunucu tarafı davranış değişikliği iOS sözleşme sürümüyle (1.0.24.42 paritesi) senkron kontrol edilmeli —
  iOS `refresh` akışı `VehicleTelemetry(data:)` ayrımı bu yüzeye dokunmaz.

## 6. Başarı ölçütü

- K1–K6 senaryolarının tamamı Playwright'ta koşulur ve her biri **kök nedenli** sonuç raporlar.
- K1 keşif bulgusu kanıt olarak plana işlenmiştir (4xx + boş render).
- K7 saha doğrulaması için ayrı test kaydı açılır; Playwright kapsamı bu maddeyi "saha" olarak raporlar.
- Hiçbir test çıktısında VIN/token/kimlik malzemesi geçmez (koşu log'u denetimiyle).
