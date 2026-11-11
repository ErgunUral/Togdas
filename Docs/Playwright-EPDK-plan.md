# Playwright Test Planı — EPDK Şarj İstasyonu API Sözleşme Nöbetçisi — 2026-11-12

## 1. Amaç ve kapsam

**Amaç:** iOS UX'inin veri kaynağı olan EPDK kamu kataloğunu (`https://apigateway.epdk.gov.tr/sarjIstasyonlari`)
**API sözleşme nöbetçisi** olarak Playwright ile doğrulamak. Bu **web UI planı değildir** —
canlı keşifte doğrulandı: `apigateway.epdk.gov.tr` UI'siz (GET → 400, kök → 404, portal yok);
UX durumları iOS tarafında (`ChargingStationsView`) yaşar.

**Test edilir:** sözleşme alanları, veri kuralları, koordinat sınırı, katalog boyutu, davranışsal yanıt kodları.
**Test edilmez:** canlı soket doluluğu/fiyat (katalog bu bilgiyi sağlamaz — repo dokümanı), geocoding (istemci yapmaz),
konum senaryoları (telefon konumu EPDK'ya gönderilmez — invariant), UI metinleri.

## 2. Kritik yol senaryoları

| # | Senaryo (tek cümle) | Beklenen sonuç | Not |
|---|---|---|---|
| E1 | `POST /sarjIstasyonlari` + `{}` gövdesi | 200; `statusCode` ve `numRows` alanları mevcut ve tutarlı | repo dokümanı: GET gövde reddi, Network.framework POST taşıması |
| E2 | Her istasyon kaydında ad/marka/işletmeci/adres/koordinat/soket alanları | Şemaya uyumlu; eksik alan `null`/boş olabilir, **0'a zorlanmaz** | tam alan adları ilk koşumda şema snapshot'ıyla sabitlenecek `[doğrulanmadı]` |
| E3 | `numRows` değeri | > 0; kamu katalogu boş olamaz → `numRows==0` test **hatasıdır** (bu bir "gerçek 0 meşrudur" durumu değildir) | 0 ≠ bilgi yok kuralının istisna kalemi: burada 0 = bozulma |
| E4 | Koordinatlar Türkiye sınırları içinde | ~35.8–42.1°N, ~25.6–45.0°E dışında koordinat bozulma sinyalidir | repo invariant'ı |
| E5 | Yanıt gövde boyutu | 32 MB sınırı altında; ilk gövde ~16 MB | test timeout'u buna göre büyük (≥120 sn) |
| E6 | `GET /sarjIstasyonlari` | 400 (gövdesiz GET reddi — keşifte kanıtlandı) | UI yok paritesi kanıt görevi |
| E7 | 429 + `Retry-After` davranışı | **Aktif tetiklenmez** — yalnız gözlemci alan; kota yeme = kabul edilemez | kota saatlik; test frekansı günde 1 / elle tetik |

## 3. Veri kuralları (Invariants)

- Konum hiç gönderilmez; test POST gövdesi sabit `{}` — parametreleştirme/koordinat ekleme yok.
- Test çıktısında VIN/token yok; istasyon adları rastgele örneklemle loglanmaz (yalnız sayım + şema anahtarları).
- Eksik alan `—`/null meşru; 0'a çevirme **yanıt tarafında olmaz** — test ham alan doğrular, iOS normalizasyonuna karışmaz.

## 4. Ortam ve önkoşullar

- Public API, oturumsuz; `page.request` / APIRequestContext ile koşulur (UI navigasyonu yok).
- **Kota kuralı:** saatlik kota → koşu günde en fazla 1 kez (CI'da gece cron) veya elle tetikleme; paralel koşum yasak.
- Timeout ≥ 120 sn (16 MB gövde); `maxRedirects` default; TLS proxy notu repo dokümanında `[taşıma farkı]`.
- Playwright ayarı: `playwright/tests/epdk-contract.spec.ts` (yüzey kökü `playwright/`).

## 5. Riskler ve bilinmeyenler

- **[doğrulanmadı]** Tam alan adları/şema — ilk koşumda şema snapshot'ı alınana dek E2 gevşek doğrular.
- **[onay gerekli]** EPDK kota kullanım politikası: günde 1 koşu + iOS uygulaması gerçek kullanımını
  aynı kota havuzuna basar mı? (aynı ağdan ayrı paylaşımlıdır — repo dokümanı §Sınırlar)
- **[doğrulanmadı]** 16 MB gövde + saatlik kota kombinasyonunda CI kaynak maliyeti.
- EPDK şema değişikliği iOS `EPDKCatalogTests` paritesini kırabilir → nöbetçi + Swift test birlikte bakılır.

## 6. Başarı ölçütü

- E1–E6 koşulur ve yeşil; E7 gözlemci alan olarak raporda yalnız iz bırakır.
- Şema snapshot'ı ilk koşumdan `Docs/EPDK-schema-snapshot.md`'ye sabitlenir.
- Koşu frekansı planla sınırlıdır (günde 1) — kota ihlali raporlanmazsa plan "tamamlandı" sayılır.
