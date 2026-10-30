# Toqdas iOS — Mimari Yol Haritası

Bu belge, mevcut çalışan uygulamayı bozmadan **modüler monolit** hedefe taşımak
için sıralamayı ve sınırları tanımlar. Sıfırdan yeniden yazım bu planın parçası
değildir; BLE protokolü, sertifika akışı ve saha doğrulamaları korunacaktır.

## 1. Mevcut durum

Ölçülen başlangıç noktası:

- `App`: 29 Swift dosyası, yaklaşık 11.014 satır.
- `Core`: 37 Swift dosyası, yaklaşık 7.365 satır.
- `Tests`: 33 dosya, 283 test.
- `App/DashboardView.swift`: 3.208 satır, 58 `@State`.
- `Core/BleConnection.swift`: 1.379 satır, 14 `@Published`.
- `App/ToqdasApp.swift`: 615 satır; `GarageModel` ve `GarageView` aynı dosyada.

Güçlü yanlar:

- `Core` büyük ölçüde App katmanından ayrılmış.
- BLE protokolü, komut kapıları, yakınlık, şarj ve ses politikaları test edilebilir.
- Gerçek API ile çalışan E2E harness mevcut.
- Hata ve tanı bilgisi kullanıcıya gösteriliyor.

Darboğazlar:

- `DashboardView` hem görünüm hem feature state hem de yan etki taşıyor.
- `BleConnection` taşıma, el sıkışma, komut kuyruğu, tanı ve hata yönetimini birlikte yürütüyor.
- `GarageModel` oturum, araç listesi, BLE, Watch, Widget ve geofence'i birlikte yönetiyor.
- Hata nedenleri çoğunlukla `lastEvent: String`; güvenlik kararları için tipli model yok.
- UI doğrudan servis ve `UserDefaults` erişimi yapıyor.
- `Core` içinde `CoreBluetooth` ve `CoreLocation` var; domain tamamen saf değil.

## 2. Hedef modül haritası

```text
ToqdasApp/                 # kompozisyon kökü, DI, uygulama yaşam döngüsü
Features/
  Garage/
  Dashboard/
  DigitalKey/
  Commands/
  Charging/
  Trips/
  Voice/
  Account/
Domain/
  Models/
  Policies/
  Errors/
Services/
  API/
  BLE/
  Keychain/
  Watch/
  Widget/
  Notifications/
  Location/
  Speech/
DesignSystem/
```

Bağımlılık kuralları:

- `Features -> Domain + Service protokolleri`
- `Services -> Domain`
- `App -> hepsi`
- `Domain -> yalnız Foundation`
- Özellik modülleri birbirini import etmez.
- UI; `ToggAPI`, `BleConnection`, `UserDefaults` gibi somut servisleri doğrudan kullanmaz.

## 3. BLE sınırı

BLE, tek bir sınıftan şu parçalara ayrılacak:

- `BLETransport`: yalnız CoreBluetooth tarama, bağlanma, yazma ve ham olay.
- `BLESession`: sertifika, araç anahtarı, challenge, READY durum makinesi.
- `BLECommandService`: komut kuyruğu, zaman aşımı, onay ve telemetri doğrulaması.
- `BLEDiagnostics`: tanı olayları, RSSI, hata sınıflandırması ve rapor.
- `BLEClient`: SwiftUI için `@MainActor ObservableObject` kabuk.

Durumlar:

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

Hata nedenleri string yerine tipli olacak:

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

Komut sonucu `Bool` yerine aşamalı olacak:

```swift
enum CommandReceipt {
    case queued
    case sent
    case acknowledged
    case verified
    case failed(BLEIssue)
}
```

Bu değişiklikler, "kapı açılmadı" durumunda komutun hangi aşamada ve neden
durduğunu kullanıcıya göstermeyi zorunlu hale getirir.

## 4. Feature state sınırı

`DashboardView` yalnız sekme yönlendirmesi ve ortak kabuk olacak. Her sekme
kendi görünümüne ve store'una ayrılacak:

- `OverviewView` + `OverviewStore`
- `ClimateView` + `ClimateStore`
- `ChargingView` + `ChargingStore`
- `HealthView` + `HealthStore`
- `BLEStatusView` + `BLEStatusStore`
- `QuickActionsView`

Store sözleşmesi:

```swift
@MainActor
final class DashboardStore: ObservableObject {
    struct State { /* yükleniyor, veri, hata, seçili araç */ }
    enum Action { case refresh, selectTab, lock, unlock, ... }
    func send(_ action: Action) async
}
```

Görünümler state okur, action gönderir. API/BLE yan etkileri store'da kalır.

## 5. Kompozisyon kökü ve DI

`GarageModel` şu parçalara ayrılacak:

- `SessionStore`: oturum, giriş/çıkış.
- `GarageStore`: araç listesi ve seçim.
- `WatchBridge`: WatchConnectivity.
- `WidgetBridge`: snapshot ve yenileme.
- `GeofenceCoordinator`: bölge giriş/çıkışı.
- `BLEConnectionCoordinator`: bağlantı yaşam döngüsü.

Bağımlılıklar `AppDependencies` üzerinden enjekte edilecek:

```swift
struct AppDependencies {
    let api: any ToggAPIProtocol
    let ble: any BLEClientProtocol
    let clock: any ClockProtocol
    let preferences: GaragePreferences
    let notifications: any NotificationService
}
```

Testlerde `FakeAPI`, `FakeBLE`, `FakeClock` kullanılacak. Tekil (singleton)
servis ve doğrudan `UserDefaults` erişimi azaltılacak.

## 6. Uygulama sırası

Her faz sonunda uygulama çalışır ve mevcut testler yeşil kalır.

1. **Ölç ve dondur**
   - Bu belge ve ADR'ler.
   - Başlangıç metrikleri: build süresi, crash/CPU, READY süresi, kopma sayısı,
     komut başarı oranı.

2. **BLE'yi ayır**
   - Davranış değişmeden transport, session, command ve diagnostics ayrımı.
   - Scripted BLE olaylarıyla state machine testleri.
   - En yüksek fayda burada.

3. **Kompozisyon kökü + DI**
   - `AppDependencies` ve protokoller.
   - `GarageModel`'i parçala.
   - Testlerde fake servisler.

4. **Dashboard'u böl**
   - Sekmeler ve kartlar ayrı dosyalara.
   - `DashboardStore` ile tek yönlü akış.
   - Dosya başına hedef: mümkünse 500 satır altı.

5. **Modülerleştir**
   - Önce `ToqdasDomain`, `ToqdasServices`, `ToqdasUI` local SPM paketleri.
   - Sonra özellik modülleri.
   - `generate_project.rb` kullanılıyorsa paket yapısı oraya işlenmeli.

6. **Kalite kapıları**
   - CI: build + test + SwiftFormat + strict concurrency uyarıları.
   - UI testleri: komut neden kapalı, sahip anahtarı çakışması, eşleştirme bekliyor.
   - Fiziksel BLE testleri ayrı manuel smoke checklist.

## 7. Başarı ölçütleri

- Kapı komutu: gönderilen / onaylanan / telemetriyle doğrulanan oranı.
- READY'ye ulaşma süresi.
- Oturum başına kopma ve yeniden bağlanma sayısı.
- `vehicleKeyMissing` ve `ownerKeyConflict` sayıları.
- Crash-free session ve CPU watchdog olayları.
- En büyük dosya boyutu, build süresi ve test kapsamı.

## 8. İlerleme

- `BLEDiagnosticStore` `BleConnection` içinden ayrıldı.
- `BLECommandRejection` tipli hale getirildi.
- `BLETransport` merkezi (central) yaşam döngüsü ayrıldı; `BleConnection`
  hâlâ servis/karakteristik keşfi, yazma kuyruğu ve el sıkışmayı taşıyor.
- `BLETransporting` protokolü ve `FakeBLETransport` ile radyo/tarama testleri
  eklendi.
- `BLEIssue` eklendi; `BleConnection.State.failed` artık serbest metin yerine
  tipli hata nedeni taşıyor.

## 9. İlkeler

- Sıfırdan rewrite yok; strangler pattern benzeri kademeli geçiş.
- Bir seferde tek sınır: önce BLE, sonra DI, sonra UI.
- Davranış değişikliği ile refactor aynı PR'da karıştırılmaz.
- Güvenlik kapıları UI'da değil, domain/servis katmanında kalır.
- Anahtar, token ve VIN gibi hassas veriler loglanmaz.
