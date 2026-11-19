# Sürüm 1.0.0 (build 2) — 19.11.2026

İlk saha sürümü. Aşağıdakiler araç başında **gözle ve imzalı telemetriyle**
doğrulandı; doğrulanamayanlar açıkça yazıldı.

## Doğrulanan

- **Kilitle / kilidi aç:** araç başında fiziksel olarak çalıştı; makbuzlar
  imzalı telemetriyle "doğrulandı" (18.11 18:13:48 ve 18:13:57).
- **Yakınlık otomasyonu:** yaklaşınca kilit açma, uzaklaşınca kilitleme
  sahada çalıştı (18.11 akşam, kullanıcı gözlemi).
- **Kilit sonrası otomatik cam kapatma:** kilit onayından ~1 sn sonra
  gönderiliyor; araç alıyor.
- **Cam komutu:** tek komut camı kısa bir adım oynatıyor; tekrarlandıkça cam
  kapanıyor. Bu sürümde tek dokunuş 8 komutluk darbe dizisi gönderir.
- **Arayüz:** durum-önce düzen, en fazla üç öncelik kartı, kurumsal palet;
  dört sekmede erişilebilirlik denetimi temiz.

## Bilinen sınırlar (dürüstçe)

- **Cam konumu doğrulanamaz:** imzalı telemetride pencere durumu yok. Komutun
  araca ulaştığını görürüz, camın kapandığını göremeyiz. Tam kapanmazsa
  yeniden dokunmak gerekir.
- **Arka planda araç komutu yok:** yakınlık otomasyonu yalnız uygulama ön
  planda ve BLE bağlıyken komut gönderir (iOS kısıtı).
- **Ayna katlama, sunroof, far** protokolde yok; uygulama gönderemez.
- Cam komutu resmî uygulamada yalnız "kayıtlı test telefonu"nda manuel olarak
  açık; otomatik kapatma bu kapıdan muaf. Bizim akış resmî akışla aynı.

## Yapı

- `MARKETING_VERSION` 1.0.0, `CURRENT_PROJECT_VERSION` 2 (uygulama, widget,
  saat).
- Arşiv: `build/Toqdas-1.0.0.xcarchive`
- Geliştirme IPA: `build/ipa-1.0.0/Toqdas.ipa`
