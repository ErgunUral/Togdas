# Sesli Asistanı Genişletme Rehberi

Sesli hat dört katmana ayrılmıştır. Yeni bir şey eklerken yalnızca ilgili katmana
dokunulur; UI hiçbir zaman eylem kararı vermez.

| Katman | Dosya | Sorumluluk |
|---|---|---|
| Ses yakalama / tanıma | `App/VoiceAssistant.swift` | Mikrofon, cihaz üstü tanıma, TTS |
| Anlama | `Core/VoiceCommandParser.swift` | Türkçe normalizasyon, tipli komut |
| Karar | `Core/VoiceCommandPolicy.swift` | Saf fonksiyon: komut + bağlam → karar |
| Yürütme / yanıt | `App/DashboardView.swift` | BLE/API çağrısı, Türkçe yanıt |
| Sohbet | `Core/VoiceChat.swift` | Komut olmayan sorulara yerel yanıt |

## 1. Sohbet sorusu eklemek (en küçük değişiklik)

Örnek: “saat kaç” ve “bugün günlerden ne” bu yolla eklendi.

1. `Core/VoiceChat.swift` içindeki `Topic` listesine yeni durum ekle.
2. `patterns` tablosuna normalize edilmiş kalıpları yaz (Türkçe karakter yok:
   `ş → s`, `ı → i`, `ğ → g`, `ü → u`, `ö → o`, `ç → c`).
3. `text(for:now:timeZone:)` içinde yanıtı üret. Zaman/rastgelelik gerekiyorsa
   dışarıdan parametre al; içeride `Date()` çağırma, test edilemez olur.
4. `Tests/VoiceChatTests.swift` içine sabit saatle test ekle.

Kurallar:

- Ağ, LLM, komut yürütme yok.
- Araç verisi iddia etme. Veri gerekiyorsa komut hattına bırak.
- Kalıp, mevcut bir komutla çakışmamalı. Çakışma testi:
  `XCTAssertEqual(VoiceCommandParser().parse(text), .unknown)`.

## 2. Salt okunur komut eklemek

Örnek: yeni bir telemetri alanı için `status(.yeniKonu)`.

1. `Core/VoiceCommand.swift` → `VoiceStatusTopic` içine `case` ve `title` ekle.
2. `Core/VoiceCommandParser.swift` → kalıpları ekle; olumsuzlama ve belirsizlik
   korumalarını atlamadan mevcut yardımcıları kullan.
3. `Core/VoiceCommandPolicy.swift` → `.read(.yeniKonu)` döndüğünü doğrula
   (salt okunur komutlar kapı istemez; yalnızca READY/telemetri kuralına uyar).
4. `App/DashboardView.swift` → `voiceStatusResponse` içine yanıt yaz:
   - Veri yoksa **“bilgi yok”**, asla `0` veya tahmin.
   - Birim açık olsun (PSI, km, °C).
   - Tazelik notu `voiceAge` / `voiceCloudAgeNote` ile eklensin.
5. `Tests/VoiceCommandParserTests.swift` → olumlu, olumsuz ve belirsiz cümleler.

## 3. Araçta eylem eklemek (yüksek risk)

1. `Core/VoiceCommand.swift` → `VoiceCommand` içine `case` ekle.
2. `isAction` listesine ekle; `requiresDeviceUnlock` ve `isPreview` kararını ver.
   - Araçta henüz doğrulanmadıysa `isPreview = true` (yanıtta “önizleme” denir).
   - Kilit açma gibi yüksek riskliyse `requiresDeviceUnlock = true` (Face ID).
3. `VoiceCommandPolicy` → izin verilen bağlam: `linkReady`, `telemetryAge < 15 sn`,
   onay, gerekirse `deviceUnlocked`.
4. `App/DashboardView.swift` → `dashboardCommand(for:)` eşlemesi + onay metni.
5. BLE komutu gerçekten gönderilmeden “gönderildi” denmez. Test edilmediyse
   “önizleme” ibaresi korunur.
6. `Tests/VoiceCommandPolicyTests.swift` → READY değil, telemetri bayat, onay yok,
   cihaz kilitli senaryoları.

## 4. Değişmez kurallar

- Ses sunucuya gönderilmez; tanıma `requiresOnDeviceRecognition = true`.
- Transkript ve ses kalıcı saklanmaz.
- Sesli “PIN” yok; kilit açma cihaz kilidi + Face ID/onay ister.
- Komut kuyruğu yok; kapı tutmuyorsa komut düşer ve kullanıcıya söylenir.
- Eksik veri “—” / “bilgi yok”, asla `0`.
- Konum/adres yalnızca sunucudan; istemcide adres çözümleme yok.

## 5. Doğrulama

```sh
swift test                                   # saf çekirdek testleri
xcodebuild -project Toqdas.xcodeproj -scheme Toqdas \
  -destination 'generic/platform=iOS' -derivedDataPath build-device \
  DEVELOPMENT_TEAM=2QAL5894CY -allowProvisioningUpdates build
```

Cihaz testleri için: `-voiceDemo "<metin>"` (parser + yanıt + TTS),
`-voiceRecorderTest` (5 sn kayıt, tepe/meter ve ses ortamı özeti).
Not: iPhone Mac'e kabloyla bağlıyken mikrofon sıfır veri döndürüyor; ses
testlerini kablosuz yap.
