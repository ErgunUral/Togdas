# K7 Saha Test Kaydı — KeySharing Geçerli Link UX — şablon

> Plan referansı: `Docs/Playwright-KeySharing-plan.md` K7.
> Bu kayıt **kodu olmayan tek plan maddesidir**; Playwright dışı, elle doldurulur.

## Kayıt bilgileri

| Alan | Değer |
|---|---|
| Tarih | [YYYY-MM-DD] |
| Test eden | [isim] |
| Cihaz / iOS sürümü | [ör. iPhone 15 Pro / iOS 18.2] |
| Android parite cihazı | [varsa model + sürüm 1.0.24.42] |
| Link üretim yöntemi | [BLE eşleşme akışı → paylaşım kartı → web linki] |
| Playwright tarafı | [koşuldu mu: https://share.togg.cloud üzerinde görsel inceleme] |

## Doğrulama maddeleri (her biri işaretlenir)

- [ ] Geçerli link tarayıcıda **paylaşım/onay sayfası** olarak render ediliyor (boş sayfa değil)
- [ ] Sayfa Türkçe metin içeriyor ve okunaklı (tam metin buraya yapıştırılır)
- [ ] `seId`/`no` değeri DOM'da, sayfa başlığında, URL çubuğunda **okunabilir şekilde tekrarlanmıyor**
- [ ] Süresi dolmuş link UX'i ayrıca denenir: [beklenen] anlaşılır hata; [gözlenen] —
- [ ] Tek kullanımlık link ikinci açılışta: [beklenen] reddedilir; [gözlenen] —
- [ ] HTTP durum kodu (DevTools Network): [200 / —]
- [ ] Konsol hatası yok (DevTools console ekran görüntüsü: `k7-console-<tarih>.png`, isimde VIN/token yok)
- [ ] **Gizlilik denetimi:** test kaydında, ekran görüntülerinde, loglarda gerçek VIN/token/kimlik malzemesi geçmiyor
- [ ] Konum hiçbir adımda gönderilmiyor (iOS invariant) — ağ izleyici özeti: [—]

## Sonuç

- Genel durum: [GEÇTİ / KISMEN / KIRIK]
- Playwright K1–K6 sonuçlarıyla tutarlılık: [evet / hayır — neden]
- Takip görevleri: [görev adları / Xray-Web gibi]

## İmza

Onaylayan: ________  Tarih: ________
