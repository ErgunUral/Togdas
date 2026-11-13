# Erişilebilirlik notları

Bu belge VoiceOver, Hareketi Azalt ve Dynamic Type kontrollerini ve bilinen
boşlukları özetler. Fiziksel VoiceOver testi gerçek iPhone + Apple Watch ile
yapılmadan tam erişilebilirlik iddia edilmez.

## Uygulananlar

- Kritik ikon düğmelerinde (`Kapat`, `Sesli komut`, `Konumu yenile`, `EPDK
  kataloğunu yenile`) VoiceOver etiketi var.
- Alt sekme çubuğu ve hesap merkezi sekmeleri seçili durumu `isSelected` olarak
  bildirir; her sekmenin etiketi ve değeri ayrı verilir.
- Sertifika durumu “Sertifika durumu” etiketi ve kalan gün değeriyle okunur.
- Araç durumu, lastik, kapı ve uyarı kartları `children: .ignore` ile tek bir
  anlamlı özet olarak sunulur; ham ikon adları okunmaz.
- Üst araç kartındaki büyük menzil/batarya ve alt ölçü metinleri artık semantik
  fontlar (`largeTitle`, `title3`, `body`, `footnote`, `caption2`) kullanır; bu
  kart Dynamic Type ile birlikte ölçeklenir.
- `VoiceSheet` mikrofon nabız animasyonu Hareketi Azalt açıksa durur.
- Watch kilit/açma/bagaj düğmeleri, komutun iPhone üzerinden ve taze imzalı
  telemetriyle gönderildiğini ipucu olarak bildirir.
- Eksik veri “—”, “bilgi yok” veya “okunmuyor” olarak okunur; 0 gösterilmez.

## Otomatik denetim (XCUITest)

`UITests/ToqdasAccessibilityAuditTests.swift` (4 test, iOS 17+):
Genel Bakış, üç sekme, Senaryolar rehberi ve komut sheet'i
`performAccessibilityAudit` ile taranır. Kapsam: dokunma hedefi, okunabilir
etiket, metin kırpılması ve trait.

2026-11-13 keşif koşusu 165 bulgu verdi: 134 Dynamic Type (kapsam dışı),
10 kontrast (kapsam dışı), 4 dokunma hedefi, 9 okunamayan ikon etiketi,
4 kırpılmış metin. Son 17 bulgu düzeltildi:

- Üç satır düğmesi 44 pt hedefe taşındı: "Kurulumu adım adım dinle",
  "Dijital anahtarı yeniden eşleştir", "Cihaz ortamında aday seç".
- "Eşik" düğmesi 44×44 pt oldu.
- Dekoratif ikonlar VoiceOver'dan gizlendi (`car.side.fill`,
  `bolt.car.fill` üç yerde); menü ikonuna "Menü" etiketi verildi.
- Üst araç başlığı 75'e kadar ölçeklenerek kırpılma giderildi; komut
  sheet'i satır içi başlığa geçti.

Kapsam dışı iki tür bilinçli: `.dynamicType` (uygulama `xxxLarge` ile
sınırlıyor; ayrı XXXL kullanılabilirlik testi var) ve `.contrast`
(koyu tema tokenları elle ölçüldü: `muted #9AA7BD` / yüzey `#131C2E`
≈ 6,9:1, AA üstü; otomatik denetim SwiftUI malzemelerinde yanlış
pozitif üretiyor).

## Bilinen boşluklar

- Bazı özel kartlarda hâlâ sabit punto (`font(.system(size:))`) kullanılıyor.
  Üst araç kartı semantik fonlara geçti; kalan kartlar için ortak bir tipografi
  katmanı gerekiyor.
- Harita üzerindeki istasyon iğneleri görsel; aynı istasyonlar erişilebilir
  liste kartlarında da sunuluyor.
- Watch'ta VoiceOver ve Hareketi Azalt fiziksel cihazda denenmedi.
- Renk kontrastı XCUITest denetiminde kapsam dışı; tokenlar elle ölçüldü
  (koyu tema AA üstü) ama yüksek kontrast modu ayrıca denenmeli.

## Elle kontrol listesi

1. VoiceOver açıkken pano, komutlar ve sesli asistan ekranını baştan sona gez.
2. Alt sekmelerde “seçili” bildirimini doğrula.
3. Hareketi Azalt açıkken sesli asistan nabzının durduğunu doğrula.
4. Dynamic Type en büyük boyutta düğme ve kartların kırpılmadığını kontrol et.
5. Watch'ta kilit/açma ve bagaj düğmelerinin ipucunu dinle.
6. Araç yokken/veri yokken ekran okuyucusunun 0 yerine “—” dediğini doğrula.
