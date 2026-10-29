import Combine
import Foundation

// MARK: - Kayıt / tanıma / yürütme sözleşmeleri

public struct VoiceRecording: Equatable, Sendable {
    public let url: URL?
    public let duration: TimeInterval
    public let peak: Float
    public let createdAt: Date

    public init(
        url: URL? = nil,
        duration: TimeInterval = 0,
        peak: Float = 0,
        createdAt: Date = Date()
    ) {
        self.url = url
        self.duration = duration
        self.peak = peak
        self.createdAt = createdAt
    }

    /// Sistem mikrofonu susturduğunda dosya neredeyse tamamen sessiz kalır.
    public var isSilent: Bool {
        peak < 0.0005
    }
}

public struct VoiceTranscript: Equatable, Sendable {
    public let text: String
    public let confidence: Double?
    public let isOnDevice: Bool

    public init(text: String, confidence: Double? = nil, isOnDevice: Bool = true) {
        self.text = text
        self.confidence = confidence
        self.isOnDevice = isOnDevice
    }
}

public enum VoiceExecutionResult: Equatable, Sendable {
    case success(String)
    case preview(String)
    case failure(String)
}

public struct VoiceTranscriptionFailure: Error, Equatable, Sendable {
    public let failure: VoiceFailure

    public init(_ failure: VoiceFailure) {
        self.failure = failure
    }
}

public enum VoiceFailure: Equatable, Sendable {
    case microphoneUnavailable
    case silentRecording
    case recognitionFailed(String)
    case onDeviceModelMissing
    case authenticationFailed
    case cancelled

    public var message: String {
        switch self {
        case .microphoneUnavailable:
            return "Mikrofon kullanılamıyor. Wi-Fi veya ekran paylaşımı kamerayı/mikrofonu kilitlemiş olabilir; Siri ile deneyebilirsin."
        case .silentRecording:
            return "Mikrofona ses ulaşmadı. Tekrar dene."
        case .recognitionFailed:
            return "Sesi yazıya çeviremedim. Tekrar dene."
        case .onDeviceModelMissing:
            return "Türkçe cihaz üstü konuşma modeli yok. Ayarlardan dili indir."
        case .authenticationFailed:
            return "Kimlik doğrulanamadı; komut gönderilmedi."
        case .cancelled:
            return "İptal edildi."
        }
    }
}

public protocol VoiceAudioCapturing: AnyObject {
    func start() async throws
    func stop() async throws -> VoiceRecording
    func cancel() async
}

public protocol VoiceTranscribing: AnyObject {
    func transcribe(_ recording: VoiceRecording) async throws -> VoiceTranscript
}

public protocol VoiceCommandExecuting: AnyObject {
    func execute(_ command: VoiceCommand) async -> VoiceExecutionResult
}

public protocol VoiceAuthenticating: AnyObject {
    func authenticate(reason: String) async -> Bool
}

public protocol VoiceSpeaking: AnyObject {
    func speak(_ text: String) async
}

// MARK: - Oturum durumu

public enum VoiceSessionState: Equatable, Sendable {
    case idle
    case recording
    case transcribing
    case understanding
    case awaitingConfirmation(command: VoiceCommand, prompt: String)
    case authenticating(command: VoiceCommand)
    case executing(command: VoiceCommand)
    case speaking(text: String)
    case failed(VoiceFailure)

    public var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    public var isAwaitingConfirmation: Bool {
        if case .awaitingConfirmation = self { return true }
        return false
    }
}

// MARK: - Oturum

/// Sesli komutun tek orkestrasyon noktası.
///
/// Katmanlar:
/// - `VoiceAudioCapturing`: kayıt
/// - `VoiceTranscribing`: cihaz üstü tanıma
/// - `VoiceCommandParser`: tipli komut
/// - `VoiceCommandPolicy`: saf güvenlik kapıları
/// - `VoiceCommandExecuting`: BLE/API
/// - `VoiceAuthenticating`: Face ID
/// - `VoiceSpeaking`: TTS
@MainActor
public final class VoiceSession: ObservableObject {
    @Published public private(set) var state: VoiceSessionState = .idle
    @Published public private(set) var transcript: String = ""
    @Published public private(set) var reply: String = ""
    @Published public private(set) var lastFailure: VoiceFailure?
    @Published public private(set) var isListening = false

    public let parser: VoiceCommandParser
    public let policy: VoiceCommandPolicy
    public var autoRelistenEnabled: Bool

    private let capture: VoiceAudioCapturing
    private let transcriber: VoiceTranscribing
    private let executor: VoiceCommandExecuting
    private let authenticator: VoiceAuthenticating
    private let speaker: VoiceSpeaking
    private let contextProvider: () -> VoiceContext
    private let responseProvider: (VoiceStatusTopic) -> String

    private var pendingCommand: VoiceCommand?
    private var confirmedCommand: VoiceCommand?
    private var authenticatedCommand: VoiceCommand?
    private var fillerRetryUsed = false
    private var speechGeneration = 0

    public init(
        capture: VoiceAudioCapturing,
        transcriber: VoiceTranscribing,
        executor: VoiceCommandExecuting,
        authenticator: VoiceAuthenticating,
        speaker: VoiceSpeaking,
        parser: VoiceCommandParser = VoiceCommandParser(),
        policy: VoiceCommandPolicy = VoiceCommandPolicy(),
        autoRelistenEnabled: Bool = true,
        contextProvider: @escaping () -> VoiceContext,
        responseProvider: @escaping (VoiceStatusTopic) -> String
    ) {
        self.capture = capture
        self.transcriber = transcriber
        self.executor = executor
        self.authenticator = authenticator
        self.speaker = speaker
        self.parser = parser
        self.policy = policy
        self.autoRelistenEnabled = autoRelistenEnabled
        self.contextProvider = contextProvider
        self.responseProvider = responseProvider
    }

    // MARK: Kullanıcı / UI girişi

    public func startListening() async {
        await beginCapture(resetFillerRetry: true)
    }

    public func stopListening() async {
        guard state == .recording else { return }
        isListening = false
        state = .transcribing

        do {
            let recording = try await capture.stop()
            guard !recording.isSilent else {
                await fail(.silentRecording)
                return
            }
            let result = try await transcriber.transcribe(recording)
            transcript = result.text
            state = .understanding
            await handle(text: result.text)
        } catch let failure as VoiceTranscriptionFailure {
            await fail(failure.failure)
        } catch {
            await fail(.recognitionFailed(error.localizedDescription))
        }
    }

    public func cancel() async {
        speechGeneration += 1
        await capture.cancel()
        clearAction()
        isListening = false
        state = .idle
    }

    /// Siri/App Intents/saat gibi metin yolları için ortak giriş.
    public func handle(text: String) async {
        transcript = text
        let result = parser.parseDetailed(text)
        await handle(command: result.command)
    }

    public func handle(command: VoiceCommand) async {
        switch command {
        case .affirm:
            if pendingCommand != nil {
                await confirm()
            } else {
                await affirmWithoutPending()
            }
        case .deny, .cancel:
            await deny()
        default:
            if state.isAwaitingConfirmation {
                clearAction()
            }
            fillerRetryUsed = false
            let decision = policy.decide(command, context: currentContext())
            await apply(decision, for: command)
        }
    }

    /// Kullanıcı onay ekranında "Evet" dediğinde/tıkladığında.
    public func confirm() async {
        guard let command = pendingCommand else {
            await speak("Onaylayacak bir komut yok.")
            return
        }
        confirmedCommand = command
        let decision = policy.decide(command, context: currentContext())
        await apply(decision, for: command)
    }

    /// Kullanıcı onay ekranında "Vazgeç" dediğinde/tıkladığında.
    public func deny() async {
        clearAction()
        await speak("Vazgeçildi.")
    }

    // MARK: İç akış

    private func beginCapture(resetFillerRetry: Bool) async {
        guard state == .idle || state.isFailed else { return }
        if resetFillerRetry { fillerRetryUsed = false }
        lastFailure = nil
        do {
            try await capture.start()
            isListening = true
            state = .recording
        } catch {
            isListening = false
            await fail(.microphoneUnavailable)
        }
    }

    private func affirmWithoutPending() async {
        await speak("Onaylayacak bir komut yok. Komutunu tekrar söyle.")
        guard autoRelistenEnabled, !fillerRetryUsed else { return }
        fillerRetryUsed = true
        await beginCapture(resetFillerRetry: false)
    }

    private func currentContext() -> VoiceContext {
        var context = contextProvider()
        context.confirmedCommand = confirmedCommand
        context.authenticatedCommand = authenticatedCommand
        return context
    }

    private func apply(_ decision: VoiceDecision, for command: VoiceCommand) async {
        switch decision {
        case .read(let topic):
            await speak(responseProvider(topic))

        case .speak(let text):
            await speak(text)

        case .confirm(let command, let prompt):
            pendingCommand = command
            let next = VoiceSessionState.awaitingConfirmation(command: command, prompt: prompt)
            state = next
            await speak(prompt, then: next)

        case .authenticate(let command, let reason):
            pendingCommand = command
            state = .authenticating(command: command)
            let authenticated = await authenticator.authenticate(reason: reason)
            guard authenticated else {
                await fail(.authenticationFailed)
                return
            }
            authenticatedCommand = command
            let next = policy.decide(command, context: currentContext())
            await apply(next, for: command)

        case .execute(let command):
            state = .executing(command: command)
            let result = await executor.execute(command)
            clearAction()
            switch result {
            case .success(let text), .preview(let text), .failure(let text):
                await speak(text)
            }

        case .reject(let text):
            clearAction()
            await speak(text)
        }
    }

    private func speak(_ text: String, then next: VoiceSessionState = .idle) async {
        speechGeneration += 1
        let generation = speechGeneration
        reply = text
        state = .speaking(text: text)
        await speaker.speak(text)
        guard generation == speechGeneration else { return }
        state = next
    }

    private func fail(_ failure: VoiceFailure) async {
        speechGeneration += 1
        clearAction()
        lastFailure = failure
        reply = failure.message
        state = .failed(failure)
        await speaker.speak(failure.message)
    }

    private func clearAction() {
        pendingCommand = nil
        confirmedCommand = nil
        authenticatedCommand = nil
    }
}
