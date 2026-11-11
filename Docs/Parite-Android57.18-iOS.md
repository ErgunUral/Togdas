# Parite Karşılaştırması — Android 1.0.24.57.18 ↔ iOS

> Kaynak: `Toqdas-1.0.24.57.18-TEST.apk` (versionCode 225) jadx dekompilasyonu; referans `.57.14` fark analizi. Tarih: 2026-11-11.

## 1. Genel mimari

| | Android .57.18 | iOS (ToqdasIOS) |
|---|---|---|
| Yapı | Monolit + obfuscated sınıflar; servis-tabanlı arka plan | SwiftUI modüler monolit: Core (policy) + App + Shared + Widget + Watch |
| Arka plan | Foreground service (`BleConnectionService`, `ProximityService`), JobScheduler, `BOOT_COMPLETED`, `GeoSavingsReceiver` | `BleLinkCoordinator`; boot-parite kısmi (iOS kısıtı, bilinçli) |
| Kalıcılık | SharedPreferences + JSON (`aux_history_<x>_<vin>`) | UserDefaults + JSON store (`KeyValueStore`, `CloudSnapshotStore`, `BLECommandHistoryStore`) |
| Test | APK'da yok | 369 birim testi, 45 Core dosyası |

## 2. Bileşen eşlemesi

| Android | iOS | Not |
|---|---|---|
| `MainActivity` | `DashboardView` + `ToqdasApp` | |
| `BleConnectionService` | `BleLinkCoordinator` + Core/BLE* | |
| `ProximityService` | `ProximityDetectionMonitor` + `ProximityAutomation`/`CycleGuard`/`LatencyMeter` | |
| `VehicleWidget` | `ToqdasWidget` + `VehicleWidgetSnapshot` | |
| `WidgetControlService` (unlock gönderir, 45 sn timeout) | **yok** | **Invariant: widget komut göndermez (karar: korunur)** |
| `KeyPreparationReceiver49` | `BleAuth` + `PhoneKeyStore` + `CertificateLifecycle` | |
| Sesli: Gemini `gemini-3.8-flash` function-calling | `VoiceCommandParser` + `VoiceCommandPolicy` | Kapalı set; LLM iOS'ta yok |
| `C0112n1` aux_history | `AuxiliaryBatteryHistory` | Fark aşağıda |
| `Q4` keyDiscovery | yok | `.57.18` yeni; geliştirme kararı alındı |
| — | watchOS app + WCSession | iOS ekstra |

## 3. Özellik matrisi

| Özellik | Android | iOS | Durum |
|---|---|---|---|
| Telemetri soruları | ✓ | ✓ | Parite |
| Kilit/aç/bagaj/cam/klima + onay kapısı | ✓ | ✓ | Parite; ACK ≠ fiziksel sonuç |
| `set_automatic_lock` + autoOff (1–1440) | ✓ | ✓ | Parite ✅ |
| `aux_history` | 500 zaman damgalı örnek, eskiyi siler (`updatedOn` bazlı) | 30 gün, gün başına en güncel, eksik gün `—` | Bilinçli varyasyon |
| Widget 12 V | bar + ≤%65 kırmızı (`#C6283D`/`#FF7279`) | metin + ≤%25 kritik / ≤%40 uyarı | Bilinçli ayrım |
| Widget internet kartı | ✓ | yok | Boşluk (opsiyonel) |
| Widget'tan komut | ✓ unlock | yok | **Bilinçli invariant (korunur)** |
| EPDK istasyon | ses → 5 km konumlu arama açar (`openNearby`) | ses → kayıtlı katalog özeti (konum açmaz) + tam liste görünümü | Ses davranışı farklı, dürüst bildirim korunur |
| Geofence | background location | `GeofenceManager` + policy | Parite (kısıtlı arka plan) |
| Reconnect etiketleri | `stale_telemetry_reconnect`, `first_status_timeout` (15 sn) | `BleRestorePlan` kısmen | Faz 1 parite |
| keyDiscovery aday seçim | ✓ yeni | — | Geliştirilecek (karar) |
| Yakınlık tanı durumları | "geçici güvenlik beklemesi", "başlatma yetkisi" | — | Faz 1 gösterim paritesi |

## 4. Güvenlik invarianları (iki tarafta da)
ACK fiziksel sonuç değildir; ses kayıtları saklanmaz; VIN/anahtar/ham reklam verisi tanıya yazılmaz; "bilgi yok" ≠ 0; widget hassas veri taşımaz. Android bunları *tanı metinleriyle* söyler; iOS aynı kuralları *Core testleriyle* zorunlu tutar.

## 5. `.57.18`'de `.57.14`'e göre yeni
1. keyDiscovery aday seçim akışı (`keyDiscoveryScan/Select/Pair/Connect/Learn`, `selection_accepted`; "Aday seçimi kabul edildi; eşleşme ve araç kimliği henüz ayrıca doğrulanmalı").
2. `stale_telemetry_reconnect` + `first_status_timeout` etiketleri.
3. Yakınlık tanısına "geçici güvenlik beklemesi" + "başlatma yetkisi" durumları.
4. Sesli functionDeclarations değişmedi.

## 6. Plan kararları (2026-11-11, kullanıcı onayı)
- Widget komut gönderme invariant'ı **korunur** (Android unlock düğmesi taşınmaz).
- keyDiscovery aday seçim akışı iOS'ta **geliştirilir** (invariantlar: aday seçimi eşleşme kanıtı değildir; araç kimliği ayrıca doğrulanmalı; VIN/ham reklam verisi günlüğe yazılmaz).
- `aux_history` iOS varyasyonu (30 gün/gün başına) korunur; 500 örneklik Android davranışı taşınmaz.
