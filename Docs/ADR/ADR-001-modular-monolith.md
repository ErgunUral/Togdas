# ADR-001 — Modüler monolit

**Durum:** Kabul edildi  
**Tarih:** 30 Ekim 2026

## Bağlam

Toqdas iOS; iPhone, watchOS ve widget hedeflerini tek Xcode projesinde taşıyor.
Uygulama çalışıyor ve 301 test geçiyor. Ancak `DashboardView` 3.208 satır,
`BleConnection` 1.445 satır ve `GarageModel` birçok platform servisini birlikte
yönetiyor. Sıfırdan yeniden yazım; BLE protokolü, sertifika akışı ve saha
doğrulamalarını riske atar.

## Karar

Uygulama **modüler monolit** olarak kademeli biçimde ayrıştırılacak. Tek
deployment birimi korunacak; modüller derleme zamanında sınır oluşturacak.

Hedef katmanlar:

- `Domain`: saf modeller, politikalar, tipli hatalar.
- `Services`: API, BLE, Keychain, Watch, Widget, bildirim, konum, ses.
- `Features`: ekran/özellik store'ları ve görünümleri.
- `DesignSystem`: ortak tema ve bileşenler.
- `App`: kompozisyon kökü ve yaşam döngüsü.

Bağımlılık yönü:

```text
Features -> Domain + Service protokolleri
Services -> Domain
Domain -> yalnız Foundation
App -> hepsi
```

Özellik modülleri birbirini import etmeyecek. Ortak ihtiyaç `Domain` veya
`DesignSystem` içine taşınacak.

## Sonuçlar

Olumlu:

- Mevcut çalışan davranış korunur.
- Her faz sonunda uygulama çalışır ve testler yeşil kalır.
- BLE ve UI bağımsız test edilebilir hale gelir.
- watchOS/widget hedefleri aynı modülleri paylaşabilir.

Olumsuz:

- Geçiş sırasında geçici adaptörler ve iki yönlü köprüler gerekir.
- Modül sınırları yanlış seçilirse gereksiz soyutlama oluşur.

## Uygulama sırası

1. Ölçüm ve ADR'ler.
2. BLE sınırının ayrılması.
3. Kompozisyon kökü ve bağımlılık enjeksiyonu.
4. Dashboard'un özellik store'larına bölünmesi.
5. Yerel SPM paketleriyle modülleştirme.
6. CI ve kalite kapıları.

## Reddedilen seçenekler

- **Sıfırdan rewrite:** BLE ve saha bilgisini riske atar; geri dönüş maliyeti yüksek.
- **Mikroservis/çoklu uygulama:** Tek istemci için gereksiz operasyon yükü.
- **TCA'yı zorunlu kılmak:** Önce servis sınırları ve DI oturmalı; TCA ancak
  karmaşık akışlarda değerlendirilmeli.
