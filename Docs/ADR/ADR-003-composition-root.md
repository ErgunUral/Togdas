# ADR-003 — Kompozisyon kökü ve bağımlılık enjeksiyonu

**Durum:** Kabul edildi  
**Tarih:** 30 Ekim 2026

## Bağlam

`GarageModel` oturum, araç listesi, BLE, Watch, Widget ve geofence'i birlikte
yönetiyor. Görünümler somut servislere ve `UserDefaults`'a doğrudan erişiyor.
Bu durum testlerde gerçek ağ, gerçek Bluetooth ve kalıcı yan etki gerektiriyor.

## Karar

Uygulama tek bir kompozisyon kökünde (`AppDependencies`) kurulacak. Servisler
protokol arkasında enjekte edilecek.

```swift
struct AppDependencies {
    let api: any ToggAPIProtocol
    let ble: any BLEClientProtocol
    let clock: any ClockProtocol
    let preferences: GaragePreferences
    let notifications: any NotificationService
}
```

`GarageModel` şu parçalara ayrılacak:

- `SessionStore`: oturum ve giriş/çıkış.
- `GarageStore`: araç listesi ve seçim.
- `WatchBridge`: WatchConnectivity.
- `WidgetBridge`: snapshot ve yenileme.
- `GeofenceCoordinator`: bölge giriş/çıkışı.
- `BLEConnectionCoordinator`: bağlantı yaşam döngüsü.

## Kurallar

- Görünümler yalnız store ve protokol bağımlılığı alır.
- `UserDefaults`, `Keychain`, `URLSession` ve `CBCentralManager` doğrudan
  görünümde kullanılmaz.
- Testlerde `FakeAPI`, `FakeBLE`, `FakeClock` kullanılır.
- Singleton erişimi yalnız kompozisyon kökünde ve varsayılan üretim
  bağımlılıklarında bulunur.
- Geçiş sırasında mevcut `GarageModel` façade olarak korunur; parçalar
  hazır oldukça devreye alınır.

## Sonuçlar

Olumlu:

- Ağ/BLE olmadan deterministik test.
- Watch/Widget/geofence yan etkileri izole edilir.
- Özellik store'ları bağımsız geliştirilebilir.

Olumsuz:

- Başlangıçta ek protokol ve adaptör kodu.
- Yanlış enjeksiyon sınırı, gereksiz karmaşıklık üretebilir.
