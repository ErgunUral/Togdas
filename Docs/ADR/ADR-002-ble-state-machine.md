# ADR-002 — BLE durum makinesi ve tipli hata

**Durum:** Kabul edildi  
**Tarih:** 30 Ekim 2026

## Bağlam

`BleConnection` CoreBluetooth taşıması, sertifika el sıkışması, komut kuyruğu,
zaman aşımı, telemetri doğrulaması ve tanı üretimini tek sınıfta yürütüyor.
Hata nedenleri çoğunlukla `lastEvent: String`; güvenlik kararları ve UI bu
metne bağlı. Kapı komutunun hangi aşamada durduğu makine tarafından
okunabilir değil.

## Karar

BLE şu sınırlara ayrılacak:

- `BLETransport`: yalnız CoreBluetooth tarama, bağlanma, yazma ve ham olay.
- `BLESession`: sertifika, araç anahtarı, challenge ve READY durum makinesi.
- `BLECommandService`: komut kuyruğu, zaman aşımı, onay ve telemetri doğrulaması.
- `BLEDiagnostics`: tanı olayları, RSSI, hata sınıflandırması ve rapor.
- `BLEClient`: SwiftUI için `@MainActor ObservableObject` kabuk.

Durum modeli:

```swift
enum BLESessionState {
    case idle
    case scanning
    case connecting
    case certificate
    case awaitingVehicleKey
    case ready
    case failed(BLEIssue)
}
```

Hata modeli:

```swift
enum BLEIssue {
    case ownerKeyConflict
    case vehicleKeyMissing
    case staleTelemetry
    case commandInFlight
    case disconnected
    case transportTimeout
}
```

Komut sonucu:

```swift
enum CommandReceipt {
    case queued
    case sent
    case acknowledged
    case verified
    case failed(BLEIssue)
}
```

## Kurallar

- UI yalnız tipli durum ve `CommandReceipt` okur; `lastEvent` metni karar
  vermek için kullanılmaz.
- Komut kapısı UI'da değil, `BLECommandService` içinde uygulanır.
- `Bool` dönen komut API'si geçiş süresince korunabilir; yeni API
  `CommandReceipt` döndürür.
- Tanı kaydı VIN, anahtar, token veya ham paket içermez.
- Fiziksel doğrulama yapılmadan READY veya kapı komutu başarısı iddia edilmez.

## Geçiş

1. `BLEDiagnosticStore` ve tipli komut reddi gibi küçük sınırları ayır.
2. `BLETransport` protokolünü ve scripted olay testlerini ekle.
3. `BLESession` durum makinesini mevcut davranışı koruyarak çıkar.
4. `BLECommandService` ve `CommandReceipt`'e geç.
5. `BLEClient` kabuğunu UI'a bağla.

## Sonuçlar

Olumlu:

- Kapı komutu başarısızlığı aşama ve neden olarak görünür.
- State machine simülatörde ve CI'da test edilebilir.
- UI, CoreBluetooth'a bağımlı olmaz.

Olumsuz:

- Geçiş sırasında eski `BleConnection` API'si ile yeni servis birlikte yaşar.
- Durum makinesi ayrıntıları başlangıçta mevcut kodun davranışına birebir
  uymak zorunda; erken sadeleştirme risklidir.
