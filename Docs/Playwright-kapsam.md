# Playwright Kapsam Raporu — 2026-11-12

## Kapsam tablosu

| Yüzey | Senaryo | Plan | Kod | Son çalıştırma | Durum |
|---|---|---|---|---|---|
| EPDK istasyon sitesi | E1–E5 sözleşme + E6 gövdesiz GET→400 | ✔ | ✔ | 2026-11-12 | **kod hazır** — E6 testli (400 paritesi kanıtlandı); E1–E5 ilk yeşil koşum kota penceresinde (bugün 429: saatlik kota doldu, skip-safe) |
| Togg web servisleri (KeySharing) | K1: geçersiz `seId` → içerik sunulmaz, sunucu çökmez | ✔ | ✔ | 2026-11-12 | **testli** (keşif kanıtlı) |
| Togg web servisleri (KeySharing) | K2: mükerrer `seId` → 4xx (iOS parite) | ✔ | ✔ | 2026-11-12 | **testli** |
| Togg web servisleri (KeySharing) | K3: fragment'lı link → 2xx ya da 4xx, 5xx yok | ✔ | ✔ | 2026-11-12 | **testli** |
| Togg web servisleri (KeySharing) | K4: `userinfo@` URL → 4xx | ✔ | ✔ | 2026-11-12 | **testli** |
| Togg web servisleri (KeySharing) | K5: sahte host → bağlantı kurulamaz/200 içerik yok | ✔ | ✔ | 2026-11-12 | **testli** |
| Togg web servisleri (KeySharing) | K5b: TLS düşürme → https yükseltme ya da 3xx/4xx reddi | ✔ | ✔ | 2026-11-12 | **testli** |
| Togg web servisleri (KeySharing) | K6: `/notKeySharing` yanlış yol → 4xx | ✔ | ✔ | 2026-11-12 | **testli** |
| Togg web servisleri (KeySharing) | K7: geçerli link paylaşım/onay UX'i | ✔ | ✖ | — | **planlı** — gerçek cihaz oturumu ister, **saha doğrulaması** |
| İleride: web panel | — (yüzey yok) | ✖ | ✖ | — | boş (varsayım; plan üretilmez) |

Son koşum sonucu: `playwright/tests/key-sharing.spec.ts` — **7/7 passed** (chromium, 4.5 sn, commit `e8b1c56`).

## Özet

**Örtülü kritik yol sayısı:** 7 / planlı toplam 8 (K1–K6 + K5b ayrıştırılmış alt madde dahil; K7 kod bekliyor)

**Boşluklar (öncelik sırasıyla):**
1. **EPDK API sözleşme nöbetçisi — kod:** plan onaylı (`Docs/Playwright-EPDK-plan.md` E1–E7), kod yok `[kod bekliyor]`.
2. **K7 — geçerli link UX'i:** tek kanıtlı senaryo boşluğu; saha kayıt şablonu hazır (`Docs/Playwright-K7-saha-test-kaydi.md`), doldurulma bekliyor.
3. **K2–K5 sunucu paritesi teyidi:** koşular yeşil ama iOS doğrulayıcı eşdeğerliği ürün tarafında resmî onaylanmadı `[doğrulanmadı]`.
4. **Negatif durumda HTML hata sayfası UX'i:** sunucu 4xx'te salt status döndürüyor; kullanıcıya anlamlı hata ekranı ürün kararı `[onay gerekli]`.
5. **Watch/app yüzeysel paritesi:** web yüzeyinden bağımsız; kapsam raporunda yalnız hatırlatma.

**Kâğıt üstünde kalanlar** (`[kod bekliyor]`):
- EPDK sözleşme nöbetçisi E1–E7 — plan ✔, kod ✖ (generate onayı bekleniyor)
- K7 geçerli link UX'i — plan ✔, kod ✖ (saha doğrulaması; Playwright üretilemez ta ki canlı link sahadan sağlanana dek)

## İki yüzeyin toplam durumu

| Yüzey | Araç | Fonksiyon | Son koşum | Not |
|---|---|---|---|---|
| iOS app (Swift) | `swift test` | **377** | **377/0 failure** (2026-11-12 koşumu) | eski 3 failure kapatıldı — yeşil taban |
| Web (Playwright) | `playwright test` | **7** | 7/7 passed (2026-11-12) | commit `e8b1c56` |

*Not: `swift test` sayısı canlı koşumdan (2026-11-12); skill belleğindeki 352 ve dokümandaki 375/3 eski kalmıştır.*
