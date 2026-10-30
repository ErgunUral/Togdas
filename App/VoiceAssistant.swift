import AVFoundation
import CallKit
import Foundation
import Speech

/// Uygulama içi bas-konuş oturumu.
///
/// - Tanıma yalnızca cihaz üstünde çalışır (`requiresOnDeviceRecognition`).
/// - Ses kaydı ve transkript kalıcı olarak saklanmaz.
/// - Niyet ayrıştırma ve komut yürütme bu sınıfın dışında; burada yalnızca
///   mikrofon, tanıma ve sesli yanıt yönetilir.
@MainActor
final class VoiceAssistant: NSObject, ObservableObject {
    enum Phase: Equatable {
        case idle
        case listening
        case processing
        case denied(String)
        case unavailable(String)
        case failed(String)

        var message: String {
            switch self {
            case .idle: return "Konuşmak için mikrofona dokun."
            case .listening: return "Dinliyorum… Komutunu söyle."
            case .processing: return "Anlıyorum…"
            case .denied(let text), .unavailable(let text), .failed(let text): return text
            }
        }

        var isProblem: Bool {
            switch self {
            case .denied, .unavailable, .failed: return true
            default: return false
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var transcript = ""
    @Published private(set) var reply = ""
    @Published private(set) var isListening = false

    /// Niyet ayrıştırma ve yanıt üretimi için geri çağırma. Dönen metin sesli okunur.
    var onUtterance: ((String) -> String)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR"))
    private let synthesizer = AVSpeechSynthesizer()
    private let callObserver = CXCallObserver()

    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var urlRequest: SFSpeechURLRecognitionRequest?
    private var activeRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var task: SFSpeechRecognitionTask?
    private var tapInstalled = false
    private var finished = false
    private var timeoutTask: Task<Void, Never>?
    private var speechGeneration = 0
    private var recognitionGeneration = 0
    private var lastLoggedTranscript = ""
    private var fillerRetryUsed = false
    private var fillerRestartTask: Task<Void, Never>?
    private var bufferCounter = VoiceBufferCounter()
    private var audioObservers: [NSObjectProtocol] = []

    /// "Evet", "tamam" gibi kısa onay sözleri komut değildir; tek kez yeniden dinlenir.
    private static let fillerPhrases: Set<String> = [
        "evet", "tamam", "tamamdir", "olur", "peki",
        "dinliyorum", "hazirim", "hazir", "buyrun"
    ]
    #if DEBUG
    private var diagnosticMode = false
    #endif

    override init() {
        super.init()
        #if DEBUG
        print("[Voice] tr-TR tanıyıcı: \(recognizer != nil), cihaz üstü: \(recognizer?.supportsOnDeviceRecognition ?? false)")
        #endif
        installAudioObservers()
    }

    deinit {
        for observer in audioObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Ses ortamı teşhisi

    /// Rota değişimi, kesinti ve medya servisi sıfırlanmasını canlı konsola yazar.
    /// Mikrofonun başka bir süreç (ör. Mac süreklilik kamerası) tarafından
    /// alınması burada görünür.
    private func installAudioObservers() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        audioObservers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            let reason = raw.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            Task { @MainActor in
                self?.logAudioEnvironment("rota değişti: \(Self.describe(reason))")
            }
        })

        audioObservers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] note in
            let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let type = rawType.flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            let rawReason = note.userInfo?[AVAudioSessionInterruptionReasonKey] as? UInt
            Task { @MainActor in
                self?.logAudioEnvironment("kesinti: \(Self.describe(type)), neden \(rawReason.map(String.init) ?? "—")")
            }
        })

        audioObservers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: session,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.logAudioEnvironment("medya servisi sıfırlandı")
            }
        })
    }

    /// Kayıt öncesi/sonrası ses ortamını tek satırda özetler.
    private func logAudioEnvironment(_ label: String) {
        let session = AVAudioSession.sharedInstance()
        let inputs = session.currentRoute.inputs
            .map { "\($0.portType.rawValue):\($0.portName)" }
            .joined(separator: ", ")
        let outputs = session.currentRoute.outputs
            .map { "\($0.portType.rawValue):\($0.portName)" }
            .joined(separator: ", ")
        let available = session.availableInputs?
            .map { "\($0.portType.rawValue):\($0.portName)" }
            .joined(separator: ", ") ?? "—"
        var muted = "—"
        if #available(iOS 17.0, *) {
            muted = AVAudioApplication.shared.isInputMuted ? "evet" : "hayır"
        }
        VoiceLog.debug("[\(label)] kategori \(session.category.rawValue)/\(session.mode.rawValue) · giriş var=\(session.isInputAvailable) · rota giriş=\(inputs.isEmpty ? "—" : inputs) · rota çıkış=\(outputs.isEmpty ? "—" : outputs) · mevcut=\(available) · kanal=\(session.inputNumberOfChannels) · muted=\(muted) · başka ses=\(session.isOtherAudioPlaying)")
    }

    private static func describe(_ reason: AVAudioSession.RouteChangeReason?) -> String {
        guard let reason else { return "bilinmiyor" }
        switch reason {
        case .unknown: return "bilinmiyor"
        case .newDeviceAvailable: return "yeni cihaz"
        case .oldDeviceUnavailable: return "cihaz ayrıldı"
        case .categoryChange: return "kategori değişti"
        case .override: return "geçersiz kılındı"
        case .wakeFromSleep: return "uyanma"
        case .noSuitableRouteForCategory: return "uygun rota yok"
        case .routeConfigurationChange: return "yapılandırma değişti"
        @unknown default: return "bilinmiyor"
        }
    }

    private static func describe(_ type: AVAudioSession.InterruptionType?) -> String {
        guard let type else { return "bilinmiyor" }
        switch type {
        case .began: return "başladı"
        case .ended: return "bitti"
        @unknown default: return "bilinmiyor"
        }
    }

    // MARK: - Genel akış

    func begin() {
        guard !isListening else {
            stopListening()
            return
        }
        VoiceLog.debug("begin: yeni bas-konuş")
        synthesizer.stopSpeaking(at: .immediate)
        speechGeneration += 1
        teardownAudio()
        fillerRestartTask?.cancel()
        fillerRestartTask = nil
        fillerRetryUsed = false
        reply = ""
        transcript = ""
        phase = .idle
        Task { await startRecognition() }
    }

    /// Metni konuşma tanımadan geçirir; örnek komutlar ve hata ayıklama için.
    func submit(_ text: String) {
        teardownAudio()
        finished = true
        fillerRestartTask?.cancel()
        fillerRestartTask = nil
        fillerRetryUsed = false
        transcript = text
        process(text)
    }

    /// Mikrofonu kapatır ve tanımayı iptal eder; yanıt üretmez.
    func cancel() {
        fillerRestartTask?.cancel()
        fillerRestartTask = nil
        teardownAudio()
        finished = true
        isListening = false
        phase = .idle
    }

    /// Mikrofonu kapatır ve bellekteki transkript/yanıtı temizler; yanıt üretmez.
    func end() {
        fillerRestartTask?.cancel()
        fillerRestartTask = nil
        teardownAudio()
        synthesizer.stopSpeaking(at: .immediate)
        speechGeneration += 1
        transcript = ""
        reply = ""
        phase = .idle
    }

    /// Kullanıcı durdurduğunda veya süre dolduğunda kaydı bitirir ve dosyayı tanımaya verir.
    func stopListening() {
        guard isListening else { return }
        isListening = false
        timeoutTask?.cancel()
        timeoutTask = nil
        activeRecorder?.stop()
        activeRecorder = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let url = recordingURL
        let generation = recognitionGeneration
        VoiceLog.debug("stopListening: kayıt durdu, dosya \(url?.lastPathComponent ?? "—")")
        phase = .processing

        // AVAudioRecorder dosyayı kapatırken kısa bir gecikme bırak; hemen okumak
        // son AAC paketlerinin eksik kalmasına yol açabilir.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard let self, self.recognitionGeneration == generation else { return }
            self.handleRecordedFile(url, generation: generation)
        }
    }

    /// Kayıt dosyasının tepe değerini ölçer; sessizse tanımaya hiç göndermez.
    private func handleRecordedFile(_ url: URL?, generation: Int) {
        guard let url else {
            teardownAudio()
            phase = .failed("Ses kaydı oluşmadı. Tekrar dene.")
            return
        }
        guard let peak = voiceFilePeak(url) else {
            teardownAudio()
            phase = .failed("Ses kaydı okunamadı. Tekrar dene.")
            return
        }
        _ = bufferCounter.observe(peak)
        let stats = bufferCounter.snapshot
        VoiceLog.debug("kayıt tamam: dosya tepe \(String(format: "%.4f", peak)), tampon \(stats.count)")
        guard stats.peak >= 0.0005 else {
            teardownAudio()
            phase = .failed("Mikrofona ses ulaşmadı. Mikrofonun açık olduğundan ve başka bir uygulama/arama tarafından kullanılmadığından emin ol.")
            return
        }
        recognizeRecording(url, generation: generation)
    }

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        VoiceLog.debug("TTS: \(trimmed)")
        synthesizer.stopSpeaking(at: .immediate)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: "tr-TR")
        utterance.rate = 0.47
        speechGeneration += 1
        let generation = speechGeneration
        synthesizer.speak(utterance)
        #if DEBUG
        print("[Voice] TTS başladı")
        #endif
        releaseSessionWhenIdle(generation: generation)
    }

    /// Konuşma bitince ses oturumunu bırakır; diğer uygulamaların sesi kısık kalmasın.
    private func releaseSessionWhenIdle(generation: Int) {
        Task { @MainActor [weak self] in
            for _ in 0..<30 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, generation == self.speechGeneration else { return }
                guard !self.synthesizer.isSpeaking, !self.isListening else { continue }
                try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                return
            }
        }
    }

    // MARK: - İzinler ve tanıma

    private func startRecognition() async {
        guard await ensurePermissions() else {
            VoiceLog.debug("izin reddedildi veya eksik")
            phase = .denied("Mikrofon ve konuşma tanıma izni gerekli. Ayarlar > Gizlilik üzerinden izin ver.")
            return
        }
        guard let recognizer else {
            VoiceLog.debug("tr-TR tanıyıcı yok")
            phase = .unavailable("Türkçe konuşma tanıma bu cihazda kullanılamıyor.")
            return
        }
        guard recognizer.supportsOnDeviceRecognition else {
            VoiceLog.debug("cihaz üstü tr-TR modeli yok")
            phase = .unavailable("Cihaz üstü Türkçe tanıma hazır değil. Ayarlar > Genel > Klavye > Dikte bölümünden Türkçe dilini indir.")
            return
        }
        VoiceLog.debug("izinler hazır; cihaz üstü tanıma açık")
        let activeCall = callObserver.calls.contains { !$0.hasEnded }
        VoiceLog.debug("aktif telefon araması: \(activeCall)")
        guard !activeCall else {
            phase = .failed("Telefon görüşmesi sırasında mikrofon kullanılamıyor. Görüşmeyi kapatıp tekrar dene.")
            return
        }

        do {
            try startRecording()
        } catch {
            teardownAudio()
            let nsError = error as NSError
            VoiceLog.debug("mikrofon hatası: \(nsError.domain) \(nsError.code) — \(nsError.localizedDescription)")
            phase = .failed("Mikrofon başlatılamadı: \(error.localizedDescription)")
        }
    }

    /// Ana ses hattı: AVAudioRecorder ile dosyaya kaydeder.
    ///
    /// `AVAudioEngine` + tampon tanıma hattı bu cihazda sürekli sıfır ses verdiği
    /// için kayıt dosyaya alınır, sessizlik ölçülür ve yalnızca ses varsa
    /// `SFSpeechURLRecognitionRequest` ile cihaz üstünde tanınır.
    private func startRecording() throws {
        recognitionGeneration += 1
        let generation = recognitionGeneration
        lastLoggedTranscript = ""
        task?.cancel()
        task = nil
        urlRequest = nil
        if let old = recordingURL {
            try? FileManager.default.removeItem(at: old)
            recordingURL = nil
        }
        let counter = VoiceBufferCounter()
        bufferCounter = counter

        if #available(iOS 17.0, *) {
            let inputMuted = AVAudioApplication.shared.isInputMuted
            VoiceLog.debug("oturum \(generation): uygulama mikrofon girdisi sessiz=\(inputMuted)")
            if inputMuted {
                do {
                    try AVAudioApplication.shared.setInputMuted(false)
                    VoiceLog.debug("oturum \(generation): mikrofon girdisi açıldı (muted=false)")
                } catch {
                    VoiceLog.debug("oturum \(generation): mikrofon girdisi açılamadı: \(error.localizedDescription)")
                }
            }
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            VoiceLog.debug("önceki ses oturumu kapatılamadı: \(error.localizedDescription)")
        }
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true, options: [])
        if let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
            do {
                try session.setPreferredInput(builtIn)
            } catch {
                VoiceLog.debug("dahili mikrofon seçilemedi: \(error.localizedDescription)")
            }
        }
        let availableInputs = session.availableInputs?
            .map { "\($0.portType.rawValue):\($0.portName)" }
            .joined(separator: ", ") ?? "—"
        VoiceLog.debug("oturum \(generation): kayıt oturumu etkin, kategori \(session.category.rawValue), mod \(session.mode.rawValue)")
        VoiceLog.debug("oturum \(generation): giriş mevcut=\(session.isInputAvailable), kanal=\(session.inputNumberOfChannels), örnekleme=\(session.sampleRate), seçili=\(session.preferredInput?.portName ?? "—"), kaynak=\(session.inputDataSource?.dataSourceName ?? "—")")
        VoiceLog.debug("oturum \(generation): mevcut girişler=\(availableInputs)")
        logAudioEnvironment("oturum \(generation): etkin")

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.prepareToRecord(), recorder.record(forDuration: 15) else {
            try? FileManager.default.removeItem(at: url)
            throw VoiceError.recordingFailed
        }
        activeRecorder = recorder
        recordingURL = url
        finished = false
        isListening = true
        phase = .listening
        let route = session.currentRoute.inputs
            .map { "\($0.portType.rawValue):\($0.portName)" }
            .joined(separator: ", ")
        VoiceLog.debug("oturum \(generation): kayıt çalışıyor=\(recorder.isRecording), giriş yolu=\(route.isEmpty ? "—" : route)")

        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.stopListening() }
        }
    }

    private func recognizeRecording(_ url: URL, generation: Int) {
        guard let recognizer else {
            teardownAudio()
            phase = .unavailable("Türkçe konuşma tanıma bu cihazda kullanılamıyor.")
            return
        }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        urlRequest = request
        VoiceLog.debug("oturum \(generation): dosya tanımaya gönderildi")

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.recognitionGeneration == generation else {
                    VoiceLog.debug("eski oturum \(generation) sonucu yok sayıldı (güncel \(self.recognitionGeneration))")
                    return
                }
                self.consume(result, error, generation: generation)
            }
        }

        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.recognitionGeneration == generation, !self.finished else { return }
                self.teardownAudio()
                self.phase = .failed("Tanıma tamamlanamadı. Tekrar dene.")
            }
        }
    }

    private func ensurePermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else { return false }

        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func startEngine(with recognizer: SFSpeechRecognizer) throws {
        // Ses oturumu, mikrofon düğümüne dokunmadan önce etkinleştirilmeli; aksi halde
        // giriş biçimi 0 kanal/0 Hz gelebilir veya motor başlatma hatası verir.
        recognitionGeneration += 1
        let generation = recognitionGeneration
        lastLoggedTranscript = ""
        let counter = VoiceBufferCounter()
        bufferCounter = counter
        if #available(iOS 17.0, *) {
            let inputMuted = AVAudioApplication.shared.isInputMuted
            VoiceLog.debug("oturum \(generation): uygulama mikrofon girdisi sessiz=\(inputMuted)")
            if inputMuted {
                do {
                    try AVAudioApplication.shared.setInputMuted(false)
                    VoiceLog.debug("oturum \(generation): mikrofon girdisi açıldı (muted=false)")
                } catch {
                    VoiceLog.debug("oturum \(generation): mikrofon girdisi açılamadı: \(error.localizedDescription)")
                }
            }
        }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            VoiceLog.debug("önceki ses oturumu kapatılamadı: \(error.localizedDescription)")
        }
        try session.setCategory(.record, mode: .default, options: [])
        try session.setActive(true, options: [])
        if let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
            do {
                try session.setPreferredInput(builtIn)
            } catch {
                VoiceLog.debug("dahili mikrofon seçilemedi: \(error.localizedDescription)")
            }
        }
        let availableInputs = session.availableInputs?
            .map { "\($0.portType.rawValue):\($0.portName)" }
            .joined(separator: ", ") ?? "—"
        VoiceLog.debug("oturum \(generation): kayıt oturumu etkin, kategori \(session.category.rawValue), mod \(session.mode.rawValue)")
        VoiceLog.debug("oturum \(generation): giriş mevcut=\(session.isInputAvailable), kanal=\(session.inputNumberOfChannels), örnekleme=\(session.sampleRate), seçili=\(session.preferredInput?.portName ?? "—")")
        VoiceLog.debug("oturum \(generation): mevcut girişler=\(availableInputs)")

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.addsPunctuation = true
        request.taskHint = .dictation

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            VoiceLog.debug("oturum \(generation): giriş biçimi geçersiz")
            throw VoiceError.audioInputUnavailable
        }
        VoiceLog.debug("oturum \(generation): giriş \(format.sampleRate) Hz, \(format.channelCount) kanal")
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
            let level = voiceBufferLevel(buffer)
            let stats = counter.observe(level)
            if stats.count == 1 {
                VoiceLog.debug("oturum \(generation): ilk ses tamponu geldi (\(buffer.frameLength) frame, float=\(buffer.floatChannelData != nil))")
            }
            if stats.count % 10 == 0 {
                VoiceLog.debug("oturum \(generation): ses seviyesi \(String(format: "%.4f", level)), tepe \(String(format: "%.4f", stats.peak))")
            }
        }
        tapInstalled = true

        audioEngine = engine
        self.request = request
        finished = false

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.recognitionGeneration == generation else {
                    VoiceLog.debug("eski oturum \(generation) sonucu yok sayıldı (güncel \(self.recognitionGeneration))")
                    return
                }
                self.consume(result, error, generation: generation)
            }
        }

        engine.prepare()
        try engine.start()
        isListening = true
        phase = .listening
        let route = session.currentRoute.inputs
            .map { "\($0.portType.rawValue):\($0.portName)" }
            .joined(separator: ", ")
        VoiceLog.debug("oturum \(generation): motor çalışıyor=\(engine.isRunning), giriş yolu=\(route.isEmpty ? "—" : route), başka ses=\(session.secondaryAudioShouldBeSilencedHint)")

        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.stopListening() }
        }
    }

    private func consume(_ result: SFSpeechRecognitionResult?, _ error: Error?, generation: Int) {
        guard !finished else { return }

        if let result {
            transcript = result.bestTranscription.formattedString
            if transcript != lastLoggedTranscript {
                lastLoggedTranscript = transcript
                VoiceLog.debug("oturum \(generation): duyulan \"\(transcript)\", final=\(result.isFinal)")
            }
            if result.isFinal {
                finish(with: transcript)
                return
            }
        }

        guard let error else { return }
        let nsError = error as NSError
        VoiceLog.debug("oturum \(generation): tanıma hatası \(nsError.domain) \(nsError.code) — \(nsError.localizedDescription)")
        if nsError.domain == "kAFAssistantErrorDomain", nsError.code == 216 || nsError.code == 1110 {
            // Konuşma yok veya oturum iptal edildi.
            if transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                teardownAudio()
                finished = true
                phase = .failed("Ses algılanamadı. Tekrar dene.")
            } else {
                finish(with: transcript)
            }
        } else if transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            teardownAudio()
            finished = true
            phase = .failed("Tanıma hatası: \(error.localizedDescription)")
        } else {
            finish(with: transcript)
        }
    }

    private func finish(with text: String) {
        guard !finished else { return }
        finished = true
        let stats = bufferCounter.snapshot
        VoiceLog.debug("işleniyor: \"\(text)\" (tampon \(stats.count), tepe \(String(format: "%.4f", stats.peak)))")
        guard stats.peak >= 0.0005 else {
            teardownAudio()
            phase = .failed("Mikrofona ses ulaşmadı. Mikrofonun açık olduğundan ve başka bir uygulama/arama tarafından kullanılmadığından emin ol.")
            return
        }
        teardownAudio()
        process(text)
    }

    private func process(_ text: String) {
        #if DEBUG
        if diagnosticMode {
            teardownAudio()
            phase = .idle
            return
        }
        #endif
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            phase = .failed("Ses algılanamadı. Tekrar dene.")
            return
        }

        let normalized = VoiceCommandParser.normalize(trimmed)
        if Self.fillerPhrases.contains(normalized) {
            VoiceLog.debug("kısa onay algılandı: \"\(trimmed)\" (yeniden deneme: \(fillerRetryUsed))")
            if !fillerRetryUsed {
                fillerRetryUsed = true
                reply = ""
                transcript = ""
                phase = .idle
                fillerRestartTask?.cancel()
                fillerRestartTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    guard !Task.isCancelled, let self, !self.isListening else { return }
                    await self.startRecognition()
                }
                return
            }
            transcript = trimmed
            let answer = "Komutunu duyamadım. Mikrofona dokunup tekrar söyle."
            reply = answer
            phase = .idle
            speak(answer)
            return
        }
        fillerRetryUsed = false

        transcript = trimmed
        phase = .processing
        let answer: String
        if let onUtterance {
            answer = onUtterance(trimmed)
        } else {
            VoiceLog.debug("onUtterance tanımlı değil")
            answer = "Bu komutu anlayamadım."
        }
        VoiceLog.debug("yanıt: \(answer)")
        reply = answer
        phase = .idle
        speak(answer)
    }

    // MARK: - Teşhis

    #if DEBUG
    /// Konuşma tanıma ve AVAudioEngine olmadan, yalnızca AVAudioRecorder ile
    /// 5 saniyelik kayıt alır. Mikrofon hattının ham ses verip vermediğini ayırt eder.
    /// Kayıt yalnızca geçici dosyada tutulur ve test sonunda silinir.
    func runRecorderTest(seconds: Double = 5) async -> String {
        speechGeneration += 1
        fillerRestartTask?.cancel()
        fillerRestartTask = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        teardownAudio()
        synthesizer.stopSpeaking(at: .immediate)

        let granted = await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard granted else { return "Mikrofon izni yok." }

        if #available(iOS 17.0, *) {
            VoiceLog.debug("kayıt testi: izin=\(String(describing: AVAudioApplication.shared.recordPermission)), muted=\(AVAudioApplication.shared.isInputMuted)")
            if AVAudioApplication.shared.isInputMuted {
                try? AVAudioApplication.shared.setInputMuted(false)
            }
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true, options: [])
            if let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
                try? session.setPreferredInput(builtIn)
            }
        } catch {
            VoiceLog.debug("kayıt testi: ses oturumu hatası \(error.localizedDescription)")
            return "Ses oturumu kurulamadı: \(error.localizedDescription)"
        }
        logAudioEnvironment("test: oturum etkin")

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mic-test-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord(), recorder.record(forDuration: seconds) else {
                let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
                VoiceLog.debug("kayıt testi: başlatılamadı, dosya \(size) bayt")
                try? FileManager.default.removeItem(at: url)
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
                return "Kayıt başlatılamadı."
            }
            VoiceLog.debug("kayıt testi: kayıt başladı, isRecording=\(recorder.isRecording)")

            var meterPeak: Float = -160
            let deadline = Date().addingTimeInterval(seconds + 0.75)
            while recorder.isRecording, Date() < deadline {
                try? await Task.sleep(nanoseconds: 100_000_000)
                recorder.updateMeters()
                meterPeak = max(meterPeak, recorder.peakPower(forChannel: 0))
            }
            let recordedTime = recorder.currentTime
            recorder.stop()
            try? await Task.sleep(nanoseconds: 250_000_000)

            let size = ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
            VoiceLog.debug("kayıt testi: durdu, süre \(String(format: "%.2f", recordedTime)) sn, meter \(String(format: "%.1f", meterPeak)) dB, dosya \(size) bayt")
            logAudioEnvironment("test: durdu")

            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            let frameCount = AVAudioFrameCount(file.length)
            guard frameCount > 0,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                try? FileManager.default.removeItem(at: url)
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
                return "Kayıt dosyası boş (meter \(TurkishFormat.decimal(Double(meterPeak), digits: 1)) dB, dosya \(size) bayt)."
            }
            try file.read(into: buffer)

            var peak: Float = 0
            if let channel = buffer.floatChannelData?[0] {
                for index in 0..<Int(buffer.frameLength) {
                    peak = max(peak, abs(channel[index]))
                }
            }
            let decibels = 20 * log10(max(peak, 0.000_000_1))
            let duration = format.sampleRate > 0 ? Double(frameCount) / format.sampleRate : 0
            try? FileManager.default.removeItem(at: url)
            try? session.setActive(false, options: .notifyOthersOnDeactivation)

            let verdict = peak >= 0.0005 ? "ses var" : "sessiz"
            VoiceLog.debug("kayıt testi: \(verdict), tepe \(String(format: "%.4f", peak)), meter \(String(format: "%.1f", meterPeak)) dB")
            return "Kayıt testi: \(verdict) · tepe \(TurkishFormat.decimal(Double(peak), digits: 4)) (\(TurkishFormat.decimal(Double(decibels), digits: 1)) dB) · \(TurkishFormat.decimal(duration, digits: 1)) sn · meter \(TurkishFormat.decimal(Double(meterPeak), digits: 1)) dB"
        } catch {
            VoiceLog.debug("kayıt testi: hata \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: url)
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            return "Kayıt hatası: \(error.localizedDescription)"
        }
    }

    /// Mikrofon hattını konuşma içeriğini işlemeden açar ve kapatır.
    /// Yalnızca hata ayıklama argümanıyla çalışır; transkript yazdırmaz.
    func runMicrophoneDiagnostic() async -> String {
        guard await ensurePermissions() else { return "izin yok" }
        guard let recognizer else { return "tanıyıcı yok" }
        guard recognizer.supportsOnDeviceRecognition else { return "cihaz üstü destek yok" }

        diagnosticMode = true
        defer { diagnosticMode = false }

        do {
            try startEngine(with: recognizer)
        } catch {
            let nsError = error as NSError
            teardownAudio()
            return "başlatılamadı [\(nsError.domain) \(nsError.code)]: \(nsError.localizedDescription)"
        }

        try? await Task.sleep(nanoseconds: 2_000_000_000)
        teardownAudio()
        return "mikrofon açıldı"
    }
    #endif

    // MARK: - Temizlik

    private func teardownAudio() {
        let stats = bufferCounter.snapshot
        VoiceLog.debug("temizlik: oturum \(recognitionGeneration), tampon \(stats.count), tepe \(String(format: "%.4f", stats.peak))")
        finished = true
        timeoutTask?.cancel()
        timeoutTask = nil

        if let recorder = activeRecorder {
            if recorder.isRecording { recorder.stop() }
        }
        activeRecorder = nil

        if let engine = audioEngine {
            if engine.isRunning { engine.stop() }
            if tapInstalled { engine.inputNode.removeTap(onBus: 0) }
        }
        tapInstalled = false

        request?.endAudio()
        task?.cancel()
        task = nil
        urlRequest = nil

        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
        }

        recognitionGeneration += 1
        audioEngine = nil
        request = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Kayıt dosyasının en yüksek örnek değeri. Sessiz kaydı tanımaya göndermemek için.
private func voiceFilePeak(_ url: URL) -> Float? {
    guard let file = try? AVAudioFile(forReading: url) else { return nil }
    let frameCount = AVAudioFrameCount(file.length)
    guard frameCount > 0,
          let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else {
        return nil
    }
    do {
        try file.read(into: buffer)
    } catch {
        return nil
    }
    guard let channel = buffer.floatChannelData?[0] else { return nil }
    var peak: Float = 0
    for index in 0..<Int(buffer.frameLength) {
        peak = max(peak, abs(channel[index]))
    }
    return peak
}

/// Ses tamponunun kaba RMS seviyesi; yalnızca tanı logu için.
private func voiceBufferLevel(_ buffer: AVAudioPCMBuffer) -> Float {
    guard let channel = buffer.floatChannelData?[0] else { return 0 }
    let count = Int(buffer.frameLength)
    guard count > 0 else { return 0 }
    var sum: Float = 0
    for index in 0..<count {
        let sample = channel[index]
        sum += sample * sample
    }
    return sqrt(sum / Float(count))
}

/// Ses tanıma oturumlarının tampon sayacı; audio iş parçacığından güvenli artırılır.
private final class VoiceBufferCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var peak: Float = 0

    func observe(_ level: Float) -> (count: Int, peak: Float) {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        if level > peak { peak = level }
        return (count, peak)
    }

    var snapshot: (count: Int, peak: Float) {
        lock.lock()
        defer { lock.unlock() }
        return (count, peak)
    }
}

/// Yalnızca DEBUG derlemesinde canlı konsola yazar.
/// Transkript dosyaya veya sunucuya gönderilmez; kalıcı saklanmaz.
enum VoiceLog {
    static func debug(_ message: @autoclosure () -> String) {
        #if DEBUG
        let time = Date().formatted(date: .omitted, time: .standard)
        print("[Voice \(time)] \(message())")
        #endif
    }
}

private enum VoiceError: LocalizedError {
    case audioInputUnavailable
    case recordingFailed

    var errorDescription: String? {
        switch self {
        case .audioInputUnavailable: return "Mikrofon girişi kullanılamıyor."
        case .recordingFailed: return "Ses kaydı başlatılamadı."
        }
    }
}
