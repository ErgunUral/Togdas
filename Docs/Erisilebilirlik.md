# Erişilebilirlik notları

Bu belge VoiceOver, Hareketi Azalt ve Dynamic Type kontrollerini ve bilinen
boşlukları özetler. Fiziksel VoiceOver testi gerçek iPhone + Apple Watch ile
yapılmadan tam erişilebilirlik iddia edilmez.

## Uygulananlar

- Kritik ikon düğmelerinde (`Kapat`, `Sesli komut`, `Konumu yenile`, `EPDK
  kataloğunu yenile`) VoiceOver etiketi var.
- Alt sekme çubuğu seçili sekmeyi `isSelected` olarak bildirir; her sekmenin
  etiketi ve değeri ayrı verilir.
- Sertifika durumu “Sertifika durumu” etiketi ve kalan gün değeriyle okunur.
- Araç durumu, lastik, kapı ve uyarı kartları `children: .ignore` ile tek bir
  anlamlı özet olarak sunulur; ham ikon adları okunmaz.
- `VoiceSheet` mikrofon nabız animasyonu Hareketi Azalt açıksa durur.
- Watch kilit/açma/bagaj düğmeleri, komutun iPhone üzerinden ve taze imzalı
  telemetriyle gönderildiğini ipucu olarak bildirir.
- Eksik veri “—”, “bilgi yok” veya “okunmuyor” olarak okunur; 0 gösterilmez.

## Bilinen boşluklar

- Bazı özel kartlarda sabit punto (`font(.system(size:))`) kullanılıyor.
  Dynamic Type ile tam ölçekleme için ortak bir tipografi katmanı gerekiyor.
- Harita üzerindeki istasyon iğneleri görsel; aynı istasyonlar erişilebilir
  liste kartlarında da sunuluyor.
- Watch'ta VoiceOver ve Hareketi Azalt fiziksel cihazda denenmedi.
- Renk kontrastı otomatik ölçülmüyor; koyu tema ve yüksek kontrast manuel
  kontrol edilmeli.

## Elle kontrol listesi

1. VoiceOver açıkken pano, komutlar ve sesli asistan ekranını baştan sona gez.
2. Alt sekmelerde “seçili” bildirimini doğrula.
3. Hareketi Azalt açıkken sesli asistan nabzının durduğunu doğrula.
4. Dynamic Type en büyük boyutta düğme ve kartların kırpılmadığını kontrol et.
5. Watch'ta kilit/açma ve bagaj düğmelerinin ipucunu dinle.
6. Araç yokken/veri yokken ekran okuyucusunun 0 yerine “—” dediğini doğrula.
