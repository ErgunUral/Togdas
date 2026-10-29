# Sesli komut çalışması

> Not: Bu belge ilk (v1) çalışmayı anlatır. Güncel mimari ve geçiş durumu için
> [SesliKomutlar-v2.md](SesliKomutlar-v2.md) belgesine bakın.

Tarih: 26 Ekim 2026 · Cihaz: iPhone (iOS 27.2) + Apple Watch Ultra 2 (watchOS 27.0.1)

## 1. Kısa özet ve öneri

Üç katmanlı bir yol öneriyorum; hiçbir katman diğerinin güvenlik kapılarını atlamaz:

1. **Uygulama içi bas-konuş** (birincil): mikrofon → cihaz üstü Türkçe konuşma tanıma →
   kural tabanlı niyet ayrıştırma → mevcut komut hattı. Çevrimdışı, test edilebilir, gecikmesi ölçülebilir.
2. **Siri / App Intents / Kısayollar** (ikincil): "Hey Siri, arabayı kilitle", kilit ekranından
   durum sorgusu, Kısayol otomasyonları (CarPlay bağlanınca vb.). Riskli eylemlerde cihaz
   kilidinin açık olması ve onay zorunlu.
3. **Saat**: dikte ile metin → WatchConnectivity isteği → komutu iPhone yürütür. Saatte
   mikrofonla sürekli dinleme yok; saat hâlâ sertifika/anahtar tutmaz.

**Yapay zekâ (LLM) yalnızca dili anlamak için kullanılmalı, komutu asla kendisi yürütmemeli.**
Önce deterministik ayrıştırıcı; anlaşılamayan serbest cümlede Apple'ın cihaz üstü Foundation
Models modeli kapalı bir niyet kümesine eşleme yapar (guided generation). Model "kapıyı aç"
derse bile kararı politika kapısı ve kullanıcı onayı verir.

Bu çalışmanın parçası olarak `Core/VoiceIntent.swift` içinde **kural tabanlı Türkçe niyet
ayrıştırıcı** ve birim testleri, ayrıca `App/VoiceAssistant.swift` + `App/VoiceSheet.swift`
içinde **uygulama içi bas-konuş** arayüzü eklendi. Siri/App Intents ve saat diktesi henüz yok.

## 2. Neden şimdi mantıklı

- Cihazda zaten güvenli komut hattı var: READY + taze imzalı telemetri + onay + doğrulama.
  Ses, bu hattın yalnızca yeni bir **girdi biçimi** olmalı.
- iOS 26.1'den itibaren Apple Intelligence ve Foundation Models **Türkçe** destekliyor;
  cihaz üstü çalıştığı için ses buluta gitmek zorunda değil.
- Siri/App Intents, uygulama kapalıyken bile eylem başlatabiliyor; kilit ekranı riski
  `authenticationPolicy` ile yönetilebiliyor.
- Kullanıcı senaryoları gerçek: elleri dolu bagaj açma, uzaktan kilitleme, "şarj ne kadar?",
  "kapılar kilitli mi?", "menzil kaç km?".

## 3. Teknik seçenekler (doğrulanmış sınırlarla)

| Yöntem | Ne verir | Sınır / risk | Bu projede rolü |
|---|---|---|---|
| `SFSpeechRecognizer` (tr-TR, `requiresOnDeviceRecognition = true`) | Uygulama içi, çevrimdışı, ücretsiz tanıma | Cihazda dikte dili indirilmiş olmalı; gürültüde doğruluk düşer; 1 dk istek sınırı; sunucu moduna sessiz düşüş olabilir | **Birincil** girdi |
| Foundation Models (`SystemLanguageModel`, iOS 26+) | Türkçe serbest cümleyi yapılandırılmış niyete çevirme, özetleme | Apple Intelligence açık + destekli cihaz; 4096 token; Türkçe kalitesi İngilizce'den düşük; halüsinasyon | Yalnızca **yedek ayrıştırıcı** |
| App Intents + App Shortcuts | Siri, Kısayollar, Spotlight, Action Button, kilit ekranı | Siri dil/cihaz ayarı gerekir; kilit ekranından çalışabilir → kimlik doğrulama şart; ücretsiz sağlama ile test sınırlı olabilir | **Hands-free** katman |
| Kısayol otomasyonları | "CarPlay bağlanınca", "saat 18:00'de" gibi tetikleyiciler | Kullanıcı kurar; arka planda BLE oturumu 60 sn'de kapanıyor | İleri aşama |
| Saatte dikte / watch App Shortcuts | Bilekten metin veya Siri | Saat uygulaması kurulumu zaten kırılgan; Siri ipuçları watchOS'ta daha katı | **İstek** katmanı |
| Sürekli dinleme (wake word) | "Togg aç" gibi ellersiz | Pil, gizlilik, App Store politikaları, arka planda mikrofon yok | **Önerilmez** |

## 4. Komut matrisi

### 4.1 Salt okunur (sesli yanıt, komut yok)

| Söylem | Yanıt kaynağı | Not |
|---|---|---|
| "Şarj ne kadar?" | imzalı telemetri / bulut | Veri yoksa "—" |
| "Menzil kaç km?" | telemetri | km |
| "Kapılar kilitli mi?" | telemetri + yaş | "Son telemetri 4 sn önce" |
| "Bagaj açık mı?" | telemetri | |
| "Dış sıcaklık kaç derece?" | telemetri | |
| "Lastik basınçları?" | telemetri | **PSI** |
| "12 V akü?" / "Odometre?" | telemetri | |
| "Şarj oluyor mu?" | bulut/telemetri | |
| "Son yolculuk ne kadar?" | Drive Experience | Sunucu verisi |

### 4.2 Eylemler (politika kapısından geçer)

| Komut | Risk | Gerekli kapılar |
|---|---|---|
| Kilitle | Düşük | READY, telemetri <15 sn, kapılar kapalı |
| Kilit aç | **Yüksek** | Cihaz kilidi açık + Face ID/onay, READY, taze telemetri |
| Bagaj aç/kapat | Orta | Onay, READY, taze telemetri |
| Cam aç/kapat | Orta/yüksek | Onay, READY, taze telemetri |
| Klima aç/kapat, sıcaklık | — | Servis şu an 504/`upstream 111`; "kullanılamıyor" yanıtı |
| Aracı bul (korna/far) | Düşük ama **doğrulanmadı** | "Önizleme" etiketi |

**Hiçbir sesli komut** mevcut otomasyon kapılarını atlamaz: READY değilse, telemetri eskiyse
veya güç durumu uygun değilse komut gönderilmez ve sesli yanıt nedeni söyler. Komut kuyruğa
alınmaz; süresi geçen sesli istek sessizce yürütülmez.

### 4.3 Yapılmayacaklar

- Sesli "PIN" veya ses iziyle kilit açma (üçüncü taraf uygulamalarda güvenilir konuşmacı
  doğrulaması yok).
- Kilitli telefondan Siri ile kilit açma.
- LLM'in doğrudan BLE komutu üretmesi.
- Arka planda biriken sesli komut kuyruğu.
- Doğrulanmamış işlevi doğrulanmış gibi göstermek.

## 5. Mimari

```
Mikrofon (AVAudioEngine, 16 kHz)
   ↓
SFSpeechRecognizer(tr-TR, on-device)  →  metin
   ↓
VoiceIntentParser (kural tabanlı, Core)  →  VoiceIntent
   ↓  (anlaşılamadıysa, izinliyse)
Foundation Models: serbest cümle → kapalı küme + güven
   ↓
VoicePolicy (READY, taze telemetri, risk sınıfı, onay)
   ↓
Mevcut komut hattı (BleConnection / WatchLink)
   ↓
AVSpeechSynthesizer(tr-TR) ile sözlü geri bildirim + ekranda durum
```

İlkeler:

- **Deterministik birincil**: 10–15 niyet için kural tabanlı ayrıştırıcı, LLM'den daha hızlı,
  çevrimdışı ve test edilebilir. LLM yalnızca "anlamadım" durumunda devreye girer.
- **Kapalı küme**: LLM çıktısı yalnızca tanımlı niyetlerden biri olabilir; serbest metin
  komuta dönüşmez.
- **Tek ses kaynağı**: Tanıma biter bitmez mikrofon kapanır; ses kaydı saklanmaz.
- **Yanıt = gerçek veri**: eksik değer "—", asla 0 değil.
- **Gecikme bütçesi**: tanıma 1–2 sn + politika <10 ms + BLE bağlanma 2–6 sn (60 sn oturum
  nedeniyle) + komut doğrulama 2–5 sn. Kullanıcıya "bağlanıyor" durumu gösterilir.

### Niyet modeli (eklenen prototip)

`VoiceIntent`: batarya, menzil, kilit durumu, lastik, sıcaklık, odometre, 12 V, şarj durumu,
kilitle, kilit aç, bagaj aç/kapat, cam aç/kapat, klima aç (sıcaklık), klima kapat, araç bul,
yardım, bilinmiyor.

Ayrıştırıcı Türkçe ek/ünlü normalizasyonu yapar ("kilitleri aç", "kapıyı kilitle", "bagajı
kapat", "şarjım ne kadar", "22 derece"). Olumsuzlama ("açma", "kapatma") güvenli tarafta
`bilinmiyor` döner. Testler `Tests/VoiceIntentTests.swift` içinde.

## 6. Güvenlik ve gizlilik

- **Kilit açma**: App Intent'te `authenticationPolicy = .requiresLocalDeviceAuthentication`
  (Face ID/Touch ID) + uygulama içinde açık onay. Siri kilit ekranından çalışabildiği için bu
  şart; aksi halde telefonu ele geçiren biri sesle aracı açabilir.
- **Kilitleme**: eller serbest kullanılabilir; yine READY + taze telemetri.
- **Konuşmacı doğrulama yok**: sesli komut bir kimlik doğrulama yöntemi değildir; yalnızca
  kolaylık. Kilit açmada cihaz sahipliği (Face ID) asıl güvencedir.
- **Röle/mesafe**: BLE RSSI güvenli mesafe ölçümü değil; sesli kilit açma yeni bir saldırı
  yüzeyi ekler. Bu yüzden kilit açma yalnızca cihaz açıkken ve onayla.
- **Gizlilik**: ses tanıma cihaz üstünde; ses kaydı ve transkript kalıcı saklanmaz. Tanıma
  cihaz üstünde mümkün değilse özellik kapalı kalır (sessizce buluta gönderme yok).
- **Denetim günlüğü**: zaman, komut, kaynak (uygulama/Siri/saat), sonuç, red nedeni.
  Transkript opsiyonel ve varsayılan kapalı.

## 7. UX örnekleri

- "Şarjım ne kadar?" → "Batarya yüzde 62, menzil 318 kilometre."
- "Kapılar kilitli mi?" → "Evet, kilitli. Son araç verisi 4 saniye önce geldi."
- "Bagajı aç" → onay → "Bagaj açma komutu gönderildi; araç doğrulaması bekleniyor."
  (komut doğrulanmadığı sürece "önizleme" etiketi)
- "Klimayı 22 derece yap" → "İklimlendirme servisi şu anda yanıt vermiyor."
- "Kilitleri aç" (telefon kilitli) → "Kilitleri açmak için iPhone'u açıp Face ID ile onayla."
- "Aracı bul" → "Korna/far komutu henüz doğrulanmadı; önizleme."

## 8. Aşamalı plan ve tahmini efor

| Aşama | İçerik | Efor | Doğrulama |
|---|---|---|---|
| 0 | Bu çalışma + niyet ayrıştırıcı prototipi | tamam | `swift test` |
| 1 | Bas-konuş arayüzü, salt-okunur sorgular, Türkçe TTS, izin metinleri | kodlandı | Gerçek mikrofon ve uçak modu testi bekliyor |
| 2 | Onaylı eylemler + politika kapısı (denetim günlüğü hariç) | kodlandı | Araç başında kilit/aç, bagaj, cam doğrulaması bekliyor |
| 3 | App Intents + App Shortcuts (kilitle, durum, menzil) | 2 gün | Siri, kilit ekranı reddi, Kısayollar |
| 4 | Saatte dikte veya watch App Shortcuts | 1–2 gün | Saat kurulumu düzeldikten sonra |
| 5 | Foundation Models yedek ayrıştırıcı + ölçüm | 2–3 gün | Türkçe doğruluk seti |

### Uygulama durumu (26 Ekim 2026)

- `VoiceAssistant` mikrofonu yalnızca bas-konuş sırasında açar, 15 saniye sonra kendiliğinden
  durur, tanıma bitince ses oturumunu kapatır ve yanıtı Türkçe seslendirir.
- Pano başlığındaki mikrofon düğmesi `VoiceSheet` sayfasını açar; örnek komut düğmeleri
  mikrofon olmadan da aynı niyet hattını çalıştırır.
- `-voiceDemo "<metin>"` hata ayıklama argümanı transkripti doğrudan hattı verir.
- Cihazda doğrulanan: tr-TR cihaz üstü tanıma desteği (`supportsOnDeviceRecognition = true`),
  mikrofon hattının açılması (tanı testi), batarya/menzil yanıtı, kilit ve bagaj için bağlantı
  yok yanıtı, lastik basınçlarının PSI okunuşu, Türkçe TTS.
- Henüz doğrulanmayan: arayüzden tam sesli komut cümlesi, araç içi gürültü, sesli eylem onayı
  ve kilit açmada Face ID, araç üzerinde komut doğrulaması.

## 9. Riskler ve azaltma

- **60 sn BLE oturumu / zayıf sinyal** → sesli komut öncesi bağlantı durumu gösterilir;
  READY değilse komut gönderilmez, kuyruk yok.
- **Araç komutları doğrulanmadı** → sesli eylemler de "önizleme"; doğrulama gelene kadar
  kilit açma dışındaki eylemler onay ister.
- **Gürültüde Türkçe tanıma** → özel dil modeli (otomotiv sözlüğü: bagaj, menzil, şarj,
  kilit) ve kısa komut kalıpları; yanlış anlamada tekrar sor.
- **Foundation Models koşulu** → cihaz/Apple Intelligence yoksa özellik sessizce kural
  tabanlıya düşer; LLM'e bağımlılık yok.
- **Siri kilit ekranı** → `.requiresLocalDeviceAuthentication`, onay, denetim günlüğü.
- **Ücretsiz sağlama** → Siri/App Intents ve saat kurulumu kısıtlı olabilir; uygulama içi
  bas-konuş bu kısıtların dışında çalışır.

## 10. Doğrulama kontrol listesi

- [ ] Uçak modunda (cihaz üstü) tanıma çalışıyor
- [ ] 70 dB araç içi gürültüde 30 komut denemesi; yanlış eylem = 0
- [ ] "aç" / "açma" ve "kapat" / "kapatma" ayrımı
- [ ] Sayı ve yüzde ("yüzde 62", "22 derece")
- [ ] Eski telemetriyle komut reddi
- [ ] Telefon kilitliyken kilit açma reddi
- [ ] Kilit komutu sonrası imzalı telemetriyle doğrulama
- [ ] Denetim günlüğü kaydı
- [ ] Ses kaydı/transkript saklanmıyor
