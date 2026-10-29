import XCTest
@testable import ToqdasCore

@MainActor
final class VoiceSessionTests: XCTestCase {
    private final class FakeCapture: VoiceAudioCapturing {
        var startError: Error?
        var recording = VoiceRecording(duration: 1, peak: 0.1)
        var startCount = 0
        var didCancel = false

        func start() async throws {
            if let startError { throw startError }
            startCount += 1
        }

        func stop() async throws -> VoiceRecording {
            recording
        }

        func cancel() async {
            didCancel = true
        }
    }

    private final class FakeTranscriber: VoiceTranscribing {
        var transcript = VoiceTranscript(text: "Şarjım ne kadar?", confidence: 0.9)
        var error: Error?
        var calls = 0

        func transcribe(_ recording: VoiceRecording) async throws -> VoiceTranscript {
            calls += 1
            if let error { throw error }
            return transcript
        }
    }

    private final class FakeExecutor: VoiceCommandExecuting {
        var result: VoiceExecutionResult = .success("Tamam.")
        var commands: [VoiceCommand] = []

        func execute(_ command: VoiceCommand) async -> VoiceExecutionResult {
            commands.append(command)
            return result
        }
    }

    private final class FakeAuthenticator: VoiceAuthenticating {
        var result = true
        var calls = 0

        func authenticate(reason: String) async -> Bool {
            calls += 1
            return result
        }
    }

    private final class FakeSpeaker: VoiceSpeaking {
        var spoken: [String] = []

        func speak(_ text: String) async {
            spoken.append(text)
        }
    }

    private struct Harness {
        let session: VoiceSession
        let capture: FakeCapture
        let transcriber: FakeTranscriber
        let executor: FakeExecutor
        let authenticator: FakeAuthenticator
        let speaker: FakeSpeaker
    }

    private func makeHarness(
        context: VoiceContext = VoiceContext(linkReady: true, telemetryAge: 1, deviceUnlocked: true),
        autoRelisten: Bool = false
    ) -> Harness {
        let capture = FakeCapture()
        let transcriber = FakeTranscriber()
        let executor = FakeExecutor()
        let authenticator = FakeAuthenticator()
        let speaker = FakeSpeaker()
        let session = VoiceSession(
            capture: capture,
            transcriber: transcriber,
            executor: executor,
            authenticator: authenticator,
            speaker: speaker,
            autoRelistenEnabled: autoRelisten,
            contextProvider: { context },
            responseProvider: { "response:\($0.rawValue)" }
        )
        return Harness(
            session: session,
            capture: capture,
            transcriber: transcriber,
            executor: executor,
            authenticator: authenticator,
            speaker: speaker
        )
    }

    // MARK: Salt okunur

    func testReadCommandUsesResponseProvider() async {
        let harness = makeHarness()
        await harness.session.handle(text: "Şarjım ne kadar?")

        XCTAssertEqual(harness.speaker.spoken, ["response:battery"])
        XCTAssertEqual(harness.session.state, .idle)
        XCTAssertTrue(harness.executor.commands.isEmpty)
    }

    func testReadCommandWorksWhenLinkNotReady() async {
        let harness = makeHarness(
            context: VoiceContext(linkReady: false, telemetryAge: nil, deviceUnlocked: true)
        )
        await harness.session.handle(text: "Kapılar kilitli mi?")

        XCTAssertEqual(harness.speaker.spoken, ["response:locks"])
        XCTAssertEqual(harness.session.state, .idle)
    }

    // MARK: Onay

    func testLockRequiresConfirmationThenExecutes() async {
        let harness = makeHarness()
        await harness.session.handle(text: "Kapıları kilitle")

        guard case .awaitingConfirmation(let command, let prompt) = harness.session.state else {
            return XCTFail("onay beklenmeli")
        }
        XCTAssertEqual(command, .lock)
        XCTAssertTrue(prompt.contains("onay"))
        XCTAssertTrue(harness.executor.commands.isEmpty)

        await harness.session.confirm()

        XCTAssertEqual(harness.executor.commands, [.lock])
        XCTAssertEqual(harness.session.state, .idle)
        XCTAssertEqual(harness.speaker.spoken.last, "Tamam.")
    }

    func testDenyClearsPendingAction() async {
        let harness = makeHarness()
        await harness.session.handle(text: "Kapıları kilitle")
        await harness.session.handle(text: "Hayır")

        XCTAssertEqual(harness.session.state, .idle)
        XCTAssertTrue(harness.executor.commands.isEmpty)
        XCTAssertEqual(harness.speaker.spoken.last, "Vazgeçildi.")
    }

    func testCancelClearsPendingAction() async {
        let harness = makeHarness()
        await harness.session.handle(text: "Kapıları kilitle")
        await harness.session.handle(text: "İptal")

        XCTAssertEqual(harness.session.state, .idle)
        XCTAssertTrue(harness.executor.commands.isEmpty)
    }

    func testNewCommandWhileAwaitingConfirmationDropsPendingAction() async {
        let harness = makeHarness()
        await harness.session.handle(text: "Kapıları kilitle")
        await harness.session.handle(text: "Şarjım ne kadar?")

        XCTAssertEqual(harness.speaker.spoken.last, "response:battery")
        XCTAssertEqual(harness.session.state, .idle)

        await harness.session.confirm()
        XCTAssertTrue(harness.speaker.spoken.last?.contains("Onaylayacak") == true)
        XCTAssertTrue(harness.executor.commands.isEmpty)
    }

    func testAffirmWithoutPendingDoesNotExecute() async {
        let harness = makeHarness(autoRelisten: false)
        await harness.session.handle(text: "Evet")

        XCTAssertTrue(harness.speaker.spoken.last?.contains("Onaylayacak") == true)
        XCTAssertTrue(harness.executor.commands.isEmpty)
    }

    func testAffirmWithoutPendingRelistensOnce() async {
        let harness = makeHarness(autoRelisten: true)
        await harness.session.handle(text: "Evet")

        XCTAssertEqual(harness.capture.startCount, 1)
        XCTAssertEqual(harness.session.state, .recording)

        await harness.session.handle(text: "Evet")
        XCTAssertEqual(harness.capture.startCount, 1)
    }

    // MARK: Eylem kapıları

    func testLockRejectedWhenLinkNotReady() async {
        let harness = makeHarness(
            context: VoiceContext(linkReady: false, telemetryAge: 1, deviceUnlocked: true)
        )
        await harness.session.handle(text: "Kapıları kilitle")

        XCTAssertEqual(harness.session.state, .idle)
        XCTAssertTrue(harness.speaker.spoken.last?.contains("bağlantı") == true)
        XCTAssertTrue(harness.executor.commands.isEmpty)
    }

    func testLockRejectedWhenTelemetryStale() async {
        let harness = makeHarness(
            context: VoiceContext(linkReady: true, telemetryAge: 16, deviceUnlocked: true)
        )
        await harness.session.handle(text: "Kapıları kilitle")

        XCTAssertEqual(harness.session.state, .idle)
        XCTAssertTrue(harness.speaker.spoken.last?.contains("15 saniyeden eski") == true)
        XCTAssertTrue(harness.executor.commands.isEmpty)
    }

    func testUnlockRejectedWhenDeviceLocked() async {
        let harness = makeHarness(
            context: VoiceContext(linkReady: true, telemetryAge: 1, deviceUnlocked: false)
        )
        await harness.session.handle(text: "Kilitleri aç")

        XCTAssertEqual(harness.session.state, .idle)
        XCTAssertTrue(harness.speaker.spoken.last?.contains("telefonun kilidini") == true)
        XCTAssertTrue(harness.executor.commands.isEmpty)
    }

    func testUnlockConfirmationThenFaceIDThenExecute() async {
        let harness = makeHarness()
        await harness.session.handle(text: "Kilitleri aç")

        guard case .awaitingConfirmation(.unlock, _) = harness.session.state else {
            return XCTFail("onay beklenmeli")
        }

        await harness.session.confirm()

        XCTAssertEqual(harness.authenticator.calls, 1)
        XCTAssertEqual(harness.executor.commands, [.unlock])
        XCTAssertEqual(harness.session.state, .idle)
    }

    func testUnlockAuthenticationFailureDoesNotExecute() async {
        let harness = makeHarness()
        harness.authenticator.result = false

        await harness.session.handle(text: "Kilitleri aç")
        await harness.session.confirm()

        XCTAssertEqual(harness.session.state, .failed(.authenticationFailed))
        XCTAssertTrue(harness.executor.commands.isEmpty)
    }

    func testTrunkPromptMentionsPreview() async {
        let harness = makeHarness()
        await harness.session.handle(text: "Bagajı aç")

        guard case .awaitingConfirmation(.trunk(open: true), let prompt) = harness.session.state else {
            return XCTFail("bagaj onayı beklenmeli")
        }
        XCTAssertTrue(prompt.contains("önizleme"))
    }

    // MARK: Kayıt / tanıma

    func testSilentRecordingDoesNotTranscribe() async {
        let harness = makeHarness()
        harness.capture.recording = VoiceRecording(duration: 1, peak: 0)

        await harness.session.startListening()
        XCTAssertEqual(harness.session.state, .recording)

        await harness.session.stopListening()

        XCTAssertEqual(harness.transcriber.calls, 0)
        XCTAssertEqual(harness.session.state, .failed(.silentRecording))
        XCTAssertTrue(harness.speaker.spoken.last?.contains("ses ulaşmadı") == true)
    }

    func testMicrophoneUnavailableIsReported() async {
        let harness = makeHarness()
        harness.capture.startError = NSError(domain: "test", code: 1)

        await harness.session.startListening()

        XCTAssertEqual(harness.session.state, .failed(.microphoneUnavailable))
        XCTAssertTrue(harness.speaker.spoken.last?.contains("Mikrofon") == true)
    }

    func testTranscriptionFlowsIntoParser() async {
        let harness = makeHarness()
        harness.transcriber.transcript = VoiceTranscript(text: "Şarjım ne kadar?", confidence: 0.9)

        await harness.session.startListening()
        await harness.session.stopListening()

        XCTAssertEqual(harness.transcriber.calls, 1)
        XCTAssertEqual(harness.speaker.spoken, ["response:battery"])
        XCTAssertEqual(harness.session.transcript, "Şarjım ne kadar?")
        XCTAssertEqual(harness.session.state, .idle)
    }

    func testOnDeviceModelMissingFailure() async {
        let harness = makeHarness()
        harness.transcriber.error = VoiceTranscriptionFailure(.onDeviceModelMissing)

        await harness.session.startListening()
        await harness.session.stopListening()

        XCTAssertEqual(harness.session.state, .failed(.onDeviceModelMissing))
        XCTAssertTrue(harness.speaker.spoken.last?.contains("konuşma modeli") == true)
    }

    func testCancelStopsListening() async {
        let harness = makeHarness()
        await harness.session.startListening()
        await harness.session.cancel()

        XCTAssertEqual(harness.session.state, .idle)
        XCTAssertTrue(harness.capture.didCancel)
        XCTAssertFalse(harness.session.isListening)
    }
}
