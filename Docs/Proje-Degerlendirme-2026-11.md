# Proje Değerlendirmesi — Kasım 2026

Kapsam: `ToqdasIOS` repo (main, 83 commit, ~26.6k satır Swift).
Yöntem: kanıta dayalı — her bulgu dosya referanslı; ölçümler greple doğrulandı.
Kısıt: salt okunur; kod değişikliği yapılmadı.

| Boyut | Puan | Tek cümle |
|---|---|---|
| Mimari | **B+** | Katmanlama ve policy deseni güçlü; App katmanında god-file ve wiring boşlukları |
| Kod kalitesi | **A−** | Disiplin yüksek; sabit yönetimi ve küçük tekrarlar puan düşürüyor |
| Test edilebilirlik | **B−** | Core örnek düzeyinde; App katmanı sıfır, UI smoke tek dosya |
| Arayüz kullanılabilirliği | **B+** | Güvenli ve dürüst UX; ana ekran yoğunluğu ve Dynamic Type boşluğu |

---

## 1. Mimari — B+

**Güçlü:**
- Core bağımsız SPM paketi (`Package.swift:6-12`): 51 dosya / 8.5k satır, `swift test` ile CLI'da çalışıyor; iOS/watchOS hedefleri Core'u tüketiyor. Bağımlılık yönü doğru.
- Policy deseni tutarlı: `BleReconnectPolicy`, `BLECommandPolicy`, `VoiceCommandPolicy`, `AuxiliaryBatteryPolicy`, `TirePressurePolicy`, `GeofencePolicy`, `WidgetRefreshPolicy` — karar mantığı saf değer tiplerinde, UI ince tüketici.
- Hedef ayrımı küçük ve invariant'lı: Watch 344 satır (komut göndermez), Widget 201 satır (salt okunur snapshot).

**Bulgular:**

| Bulgu | Kanıt | Etki | Öneri | Maliyet |
|---|---|---|---|---|
| God-file: `DashboardView.swift` 3592 satır, 60 fonksiyon, içinde `LoginView` bile var | `App/DashboardView.swift:3536` | Değişiklik çakışmaları, gözden kaçan yan etkiler | Kart başına dosya + ViewModel'e iş mantığı | Orta |
| Ölü wiring: `BleStatusWatchdog` yalnız kendi dosyasında adı geçiyor | grep: App'te 0 kullanım | Testlenen mantık üretime bağlı değil | `BleLinkCoordinator`'a bağla ya da arşivle | Küçük |
| Watch hedefi 37 kaynağı manuel pbxproj ID'leriyle derliyor | `project.pbxproj` Sources fazı 995D61EA | Her dosya eklemede kırılgan (bugün de elle eklendi) | Xcode GUI ile üyelik veya dosya referansı şablonu | Küçük |
| `ToggAPI` somut singleton benzeri: paramsız `init()` | `App/ToggAPI.swift:69` | App katmanı mock'layamıyor | `protocol ToggAPIClient` + injectable init | Küçük-Orta |

## 2. Kod Kalitesi — A−

**Güçlü:**
- `try!` **0**, `as!`/TODO/FIXME **0** (grep doğrulandı). Hata metinleri Türkçe, kullanıcıya dönük.
- URL literalleri tek dosyada toplu: 4 endpoint `App/ToggAPI.swift:51-55,15` (config'e alma opsiyonel; dağınıklık yok).
- Her dosyada invariant amaçlı yorum; `Docs/` kültürü (Mimari.md, AppStore.md, Parite raporu).

**Bulgular:**

| Bulgu | Kanıt | Etki | Öneri | Maliyet |
|---|---|---|---|---|
| UserDefaults key literalleri merkezi değil | App'te 40 `UserDefaults.standard` çağrısı, 9 farklı `toqdas.*` key | Yazım hatası = sessiz veri kaybı | Key sabitleri tek enum/dosyada | Küçük |
| 12 V metin formatı 4 yerde kopya | `Watch/ToqdasWatchApp.swift:233`, `App/DashboardView.swift:3227`, `App/ToqdasApp.swift:629`, `Shared/VehicleWidgetSnapshot.swift:53` | Renk kuralı policy'de tutarlı ama metin formatı sapabilir | Ortak format fonksiyonu (Shared/Core) | Küçük |
| Bildirim gönderme 4 ayrı desen | `DashboardView`, `ChargingBudgetNotifier`, `MaintenanceNotifier`, `ProximityDetectionMonitor` | Yetki/identifer/sound davranışı yer yer farklı | `NotificationPoster` yardımcısı | Orta |
| Repo kökünde 45 `build-*` yerel dizin | `ls -d build*` | Disk çöpü (git temiz — `.gitignore` kapsıyor ✅) | Tek `derivedDataPath` + temizlik | Küçük |
| Uzun uncommitted yığın | `git status`: gözcü, test, watch, parite dokümanı | Kayıp riski; seçici commit gerektiriyor | Faz 1 commit'i tamamlanmalı | Küçük |

## 3. Test Edilebilirlik — B−

**Güçlü:**
- Core: 375 test / 46 dosya; deterministik imzalar (`now: Date` parametresi — `BleStatusWatchdog.reason`), helper-builder deseni (`Tests/BleReconnectPolicyTests.swift:4-20`), negatif senaryolar yazılıyor.
- Policy'lerin tamamı eşleşen test dosyasına sahip (46 ↔ Core dosyaları).

**Bulgular:**

| Bulgu | Kanıt | Etki | Öneri | Maliyet |
|---|---|---|---|---|
| App katmanı 0 test, 0 protokol | `grep "protocol " App` → 0 | ToggAPI/BleLinkCoordinator/VoiceAssistant davranış güvencesi yok | `ToggAPIClient` protokolü + ilk 3-5 test | Orta |
| `ToggAPI` bağımlılıkları içeri sabit | `App/ToggAPI.swift:51-69` (`SessionStore()` literal, session injectable değil) | Mock'suz → ağ mantığı test dışı | init'e `URLSession`/`SessionStore` inject et | Küçük |
| UI testi tek smoke dosyası | `UITests/ToqdasSmokeTests.swift` | Düzen değişikliğinde regresyon güvencesi yok | Kritik akışlara (login→dashboard, onay kapısı) 3-5 test | Orta |
| `swift test` 3 failure bekliyor | Son koşum: 375/3 | Yeşil taban bozuldu | Failure teşhisi + düzeltme (öncelik) | Küçük |

## 4. Arayüz Kullanılabilirliği — B+

**Güçlü:**
- Onay kapıları, dürüst veri invariant'ı (`—` ≠ 0), eksik verinin gösterilmemesi — UX kararları güvenlik invariant'larıyla hizalı.
- Cross-surface tutarlılık: 12 V renk kuralı tek kaynaktan (`AuxiliaryBatteryPolicy`) — Widget (`Widget/ToqdasWidget.swift:183-186`), Watch (`auxTint`), telefon kartı aynı bant.
- Erişilebilirlik farkındalığı: 33 `accessibilityLabel/Hint` noktası.

**Bulgular:**

| Bulgu | Kanıt | Etki | Öneri | Maliyet |
|---|---|---|---|---|
| Ana ekran yoğunluğu: HealthCard, ClimateCard, PremiumControls, bütçe, bakım, 12 V geçmiş, yakınlık… tek dosyada tek ekran ağacı | `DashboardView.swift:3039,3152,2947…` | Bilgi yükü; bulma maliyeti artıyor | Detay sayfası/katlanabilir kartlar (watch P2.1 planının telefon karşılığı) | Orta |
| Dynamic Type desteği kanıtı yok | `dynamicTypeSize`/`@ScaledMetric` grep → 0 | Büyük metin tercihinde yerleşim bozulabilir | Kritik ekranlarda `@ScaledMetric` + mutlak font yerine metin stili | Orta |
| Smoke testi dışında UI doğrulama yok | `UITests/` 1 dosya | UX regresoyna körü | Onay kapısı + widget/saat senaryosu testleri | Orta |

---

## Boyut başına en yüksek getirili 3 iyileştirme

**Mimari:** (1) DashboardView bölünmesi (kart dosyaları + ViewModel), (2) BleStatusWatchdog wiring'i, (3) watch hedef üyeliğinin sadeleştirilmesi.
**Kod kalitesi:** (1) UserDefaults key sabitleri, (2) ortak `NotificationPoster`, (3) build dizini tek klasöre indirme.
**Test:** (1) 3 failure düzeltmesi → 375/0, (2) `ToggAPI` protokol + injectable init, (3) App katmanına ilk testler.
**Arayüz:** (1) dashboard bilgi hiyerarşisi (detay sayfası), (2) Dynamic Type doğrulama, (3) onay kapısı UI testi.

## Parite planı ile ilişki

Faz 1 (gözcü) ve watch P1 işleri bu raporun "uncommitted" ve "wiring" bulgularıyla örtüşüyor: commit tamamlanması ve wiring aynı iş parçasında kapanabilir. `ToggAPI` protokolü parite dışı bağımsız fayda; DashboardView bölünmesi Faz 4 adayı (kullanıcı onayıyla).
