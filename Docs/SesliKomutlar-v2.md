# Sesli Komutlar v2 — Yeniden Tasarım

Bu belge, mevcut sesli komut hattını yamamak yerine baştan kurulacak yapıyı tanımlar.
Amaç: tek bir sorumluluk zinciri, cihazsız test edilebilir çekirdek, net hata durumları
ve güvenli eylem kapıları.

## Durum (26 Ekim 2026)

- Saf çekirdek `Core/` altında: `VoiceCommand`, `VoiceCommandParser`, `VoiceCommandPolicy`,
  `VoiceSession`.
- `Tests/` altında parser, politika ve oturum testleri var; `swift test` 95/95 geçiyor.
- `DashboardView` ses işleyicisi yeni parser + politika hattını kullanıyor.
- Ses yakalama/tanıma hâlâ `App/VoiceAssistant.swift` üzerinde; v2 `VoiceSession`
  adaptörleri (recorder, transcriber, executor, authenticator, speaker) sıradaki adım.
- Politikadaki kapılar cihazda gerçek araçla henüz doğrulanmadı.

## 1. Neden yeniden tasarım?

Mevcut yapıda:

- Mikrofon, tanıma, niyet ayrıştırma, onay ve eylem kararları birkaç dosyaya dağılmış.
- `VoiceAssistant` hem ses oturumunu hem tanımayı hem akışı yönetiyor; test edilebilir değil.
- Niyet ayrıştırma büyük ölçüde metin eşleştirmeye dayanıyor; belirsizlik ve slot yönetimi zayıf.
- Mikrofon sistem tarafından kilitlendiğinde (Wi-Fi/Continuity/ekran paylaşımı) yalnızca
  hata mesajı var; Siri/App Intents gibi bir yedek yol yok.
- Eylem kapıları UI içinde dağınık; politika tek bir yerde test edilmiyor.

Bu nedenle v2, **katmanlı ve sözleşmeli** bir yapı kurar.

## 2. İlkeler

- Sürekli dinleme ve wake word yok; yalnızca kullanıcı mikrofona bastığında kayıt.
- Ses ve transkript sunucuya gönderilmez; tanıma cihaz üstünde.
- Transkript ve ses kalıcı saklanmaz; geçici dosya iş bitince silinir.
- LLM komut yürütmez; komutlar deterministik ayrıştırıcıdan geçer.
- Sesli PIN yok.
- Kilit açma: cihaz kilidi açık + Face ID/onay; kilitli telefondan Siri ile kilit açma yok.
- Eylem kapısı: BLE `READY` + telemetri yaşı < 15 sn + açık onay.
- Komut kuyruğu yok; aynı anda tek oturum.
- Sayfa açılınca otomatik dinleme yok.
- Kısa onaylar (“evet”, “tamam”, “peki”) komut sayılmaz; bir kez otomatik yeniden dinlenir.
- Lastik basıncı PSI, mesafe km, dış sıcaklık gösterilir.
- Doğrulanmamış kontrol “önizleme”; eksik veri “—” / “bilgi yok”, asla 0 değil.
- Konum/adres yalnızca sunucudan; istemcide geocoding yok.
- Şarj hesabı: 88,5 kWh, 10 ₺/kWh, kayıp yok.

## 3. Katmanlar

```
Core/
  VoiceCommand.swift          // tipli komutlar + risk sınıflandırması
  VoiceCommandParser.swift    // Türkçe normalizasyon + deterministik ayrıştırma
  VoiceCommandPolicy.swift    // saf karar fonksiyonu (kapılar)
  VoiceSession.swift          // durum makinesi + adaptör protokolleri

App/ (sıradaki adım)
  VoiceRecorder.swift         // AVAudioRecorder hattı
  VoiceTranscriber.swift      // SFSpeech / SpeechAnalyzer
  VoiceExecutor.swift         // BLE/API adaptörü
  VoiceAuthenticator.swift    // Face ID
  VoiceSpeaker.swift          // TTS
```

### 3.1 VoiceSession (orkestrasyon)

Durumlar:

```
idle -> recording -> transcribing -> understanding
     -> answering
     -> confirming -> authenticating -> executing -> speaking
     -> idle | failed
```

Kurallar:

- Aynı anda tek oturum; yeni basış öncekini iptal eder.
- Kayıt en fazla 15 sn; sessizlik kapısı tanımadan **önce**.
- `cancel()` her durumda geçici dosyayı ve görevleri temizler.
- UI yalnızca `VoiceSession.state` ve yayınlanan özellikleri okur.
- Eylem kararı UI'da değil, `VoiceCommandPolicy` içinde verilir.

### 3.2 Ses yakalama

Protokol:

```swift
protocol VoiceAudioCapturing {
    func start() async throws -> VoiceRecording
    func stop() async throws -> VoiceRecording
    func cancel()
}
```

- Varsayılan: `AVAudioRecorder` + AAC 44.1 kHz mono `.m4a` (cihazda çalıştığı doğrulandı).
- `.playAndRecord`, `.default`, `.defaultToSpeaker`, dahili mikrofon.
- Kayıt sonrası dosya tepe değeri ölçülür; `< 0.0005` ise tanımaya gönderilmez.
- Geçici dosya `finally` benzeri tek bir temizlik noktasında silinir.
- Mikrofon sistem tarafından kilitliyse `VoiceFailure.microphoneUnavailable` döner;
  bu durumda Siri/App Intents yedeği önerilir.
- iOS 26+ varsa `SpeechAnalyzer` akışı ikinci bir adaptör olarak eklenebilir; varsayılan
  davranış değişmeden önce cihazda doğrulanır.

### 3.3 Tanıma

Protokol:

```swift
protocol VoiceTranscribing {
    func transcribe(_ recording: VoiceRecording) async throws -> VoiceTranscript
}
```

- `requiresOnDeviceRecognition = true`.
- `tr-TR`; dil modeli yoksa `.onDeviceModelMissing`.
- `VoiceTranscript`: metin, süre, güven (varsa), cihaz üstü bayrağı.
- Boş/sessiz kayıt tanımaya gönderilmez.
- Tanıma hatası ile sessizlik hatası ayrı tiplerde raporlanır.

### 3.4 Komut modeli

Metin yerine tipli komutlar:

```swift
enum VoiceCommand: Equatable {
    case status(StatusTopic)          // şarj, menzil, kapılar, lastik, sıcaklık, klima
    case lock
    case unlock
    case trunk(open: Bool)
    case windows(open: Bool)
    case climate(on: Bool)
    case findVehicle
    case help
    case cancel
    case affirm
    case deny
    case unknown
}
```

- Slotlar: `StatusTopic`, `Bool`, sayılar (sıcaklık, şarj hedefi) ayrı modellerde.
- Ayrıştırıcı deterministik; LLM yalnızca **öneri** üretir, komut yürütmez.
- Belirsizlikte komut çalıştırılmaz; “Neyi kastettin?” sorusu sorulur.
- “Evet/tamam/peki” `affirm`; tek başına eylem değil.

### 3.5 Politika (saf fonksiyon)

```swift
struct VoiceContext {
    let appState: AppState
    let bleState: BleState
    let telemetryAge: TimeInterval?
    let isDeviceUnlocked: Bool
    let confirmation: VoiceConfirmation?
}

enum VoiceDecision {
    case answer(String)
    case confirm(String)
    case authenticate(String)
    case execute(VoiceCommand)
    case reject(String)
}

func decide(_ command: VoiceCommand, context: VoiceContext) -> VoiceDecision
```

Eylem kapıları:

- `READY` değilse: eylem yok, açıklama.
- Telemetri yok veya yaş ≥ 15 sn: eylem yok, tazelik isteği.
- Onay yoksa: `.confirm`.
- Kilit açma: cihaz kilidi açık değilse reddet; onaydan sonra Face ID.
- Kuyruk yok; onay başka komuta taşınmaz.
- Okuma komutları önbellekten yanıtlanır; veri yaşı yanıta eklenir.

### 3.6 Yürütme

- `VoiceCommandExecutor` BLE/API adaptörü; UI ve parser bunu bilmez.
- Her eylem sonrası doğrulama; sonuç `VoiceExecutionResult` olarak döner.
- “Önizleme” gereken kontroller sonuçta açıkça işaretlenir.

### 3.7 Siri / App Intents / Saat

- Siri ve saat, metni aynı `VoiceCommandParser` + `VoiceCommandPolicy` hattına verir.
- Telefon tek doğruluk kaynağı; saat yalnızca dikte/komut gönderir.
- Kilitli telefondan kilit açma yok; Siri yalnızca okuma ve güvenli eylemler.
- App Shortcuts: “Şarjım ne kadar?”, “Kapılar kilitli mi?”, “Lastik basınçları”.

## 4. Akış

1. Kullanıcı mikrofona basar.
2. `VoiceSession` kaydı başlatır; durum `.recording`.
3. Kullanıcı durdurur veya 15 sn dolar.
4. Dosya tepe değeri ölçülür; sessizse `.failed` ve tanımaya gitmez.
5. Cihaz üstü tanıma; durum `.transcribing`.
6. Parser tipli komut üretir; durum `.understanding`.
7. Politika karar verir:
   - okuma → yanıt + TTS,
   - eylem → onay iste,
   - kilit açma → onay + Face ID,
   - belirsiz → açıklama.
8. Eylem yürütülür, sonuç doğrulanır, TTS ile okunur.
9. Geçici dosya silinir; durum `.idle`.

## 5. Hata durumları

- `microphoneUnavailable`: sistem mikrofonu kilitli; “Siri ile dene” önerisi.
- `silentRecording`: ses ulaşmadı; tanımaya gönderilmez.
- `onDeviceModelMissing`: dil modeli indirilmeli.
- `recognitionFailed`: tanıma hatası; transkript yoksa eylem yok.
- `ambiguousCommand`: netleştirme sorusu.
- `actionNotReady`: BLE/telemetri/onay kapısı.
- `authenticationFailed`: Face ID iptal/başarısız; eylem yok.

## 6. Test stratejisi

- **Parser**: 100+ Türkçe cümle; eş anlamlılar, olumsuzlama, sayılar, gürültü.
- **Policy**: tablo testi; READY/taze değil/onay yok/kilitli cihaz/Face ID.
- **Session**: sahte capture/transcriber/executor ile durum geçişleri; iptal ve temizlik.
- **Sessizlik**: dosya tepe eşiği; boş sesin tanımaya gitmemesi.
- **Cihaz**: gerçek iPhone + gerçek araç; BLE READY, taze telemetri, Face ID.
- **Regresyon**: `swift test` her PR'da.

## 7. Aşamalar

1. **Tasarım + iskelet**: protokoller, tipler, sahte adaptörler, testler. Davranış değişmez.
2. **Salt okunur MVP**: şarj, menzil, kapılar, lastik, sıcaklık; kayıt + tanıma + yanıt.
3. **Güvenli eylemler**: kilit/aç, bagaj, cam; onay + Face ID + kapılar.
4. **Siri/App Intents + saat**: aynı parser/politika.
5. **Eski kodu kaldır**: `VoiceAssistant`/`VoiceIntent` emekliye ayrılır.

## 8. Açık kararlar

- v1 komut seti hangileri? (öneri: şarj, menzil, kapılar, lastik, sıcaklık, kilit/aç)
- iOS 16 uyumluluğu korunacak mı? (SFSpeech fallback + iOS 26 SpeechAnalyzer)
- Mevcut `VoiceSheet` korunacak mı, yoksa yeni sade “bas-konuş + durum” ekranı mı?
- Siri/App Intents v1'e girsin mi, yoksa v2'ye mi kalsın?
