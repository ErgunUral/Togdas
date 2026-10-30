# Lokalizasyon ve biçimlendirme kuralları

Uygulama tek dilli Türkçe. Cihaz dili farklı olsa da kullanıcıya gösterilen
sayı, para ve tarih biçimleri `tr_TR` kalır. Teknik/protokol değerleri ise
bilinçli olarak `en_US_POSIX` kullanır.

## Kullanıcıya gösterilen değerler

- Ondalık ayırıcı virgül, binlik ayırıcı noktadır: `12,3`, `1.234,5`.
- Ortak kaynak `Core/TurkishFormat.swift`:
  - `decimal(_:digits:)` ondalık ve binlik biçimlendirme.
  - `integer(_:)` / `money(_:)` para ve tam sayı.
  - `date(_:format:)` Türkçe ay/gün adları.
- `ExperienceFormat.whole`, `oneDecimal`, `twoDecimals` bu kaynağı kullanır;
  Seyahatname, şarj hesaplayıcısı ve sürüş istatistikleri aynı biçimi gösterir.
- Eksik/geçersiz değer `—` veya “bilgi yok” olur; 0 gösterilmez.
- SwiftUI `.formatted(...)` çağrıları kök görünümdeki
  `.environment(\.locale, TurkishFormat.locale)` ile Türkçe biçim alır.

## Teknik değerler

Aşağıdaki alanlarda nokta ondalık ayırıcı bilinçli olarak korunur:

- Protokol/BLE ikili verisi, hex gösterimleri ve imza/test vektörleri.
- Enlem/boylam koordinatları (`39.98705, 32.58542`); ayırıcı virgülle
  karışmaması için.
- HTTP `Retry-After`, `grpc-timeout`, ISO-8601 tarih ayrıştırma ve CSV dosya
  adları gibi makine tarafından okunan değerler.
- Konsol günlükleri ve hata ayıklama çıktıları.

Bu alanlarda `String(format:)` veya `Locale(identifier: "en_US_POSIX")`
kullanımı normaldir; kullanıcı arayüzünde kullanılmamalıdır.

## Denetim

Yeni bir kullanıcı metni eklerken:

```sh
rg -n 'String\(format:|\.formatted\(|DateFormatter|NumberFormatter' App Core Watch Shared
```

- Kullanıcıya gösterilen sayı ise `TurkishFormat` kullan.
- Tarih ise `TurkishFormat.date` veya kök `tr_TR` ortamına güven.
- Sunucudan gelen adres varsa olduğu gibi göster; istemci geocoding yapmaz.
- Yeni testte Türkçe ayırıcıyı doğrula.

## Bilinen boşluklar

- Bazı özel kartlarda sabit punto kullanılıyor; Dynamic Type taraması ayrı bir
  erişilebilirlik işi.
- İngilizce çeviri kapsam dışı; `Localizable.xcstrings` yalnız Türkçe kaynak
  metinleri tutuyor.
- Fiziksel cihazda tarih/saat dilimi ve 12/24 saat ayarı ayrıca denenmeli.
