import XCTest
@testable import ToqdasCore

final class VoiceCommandPolicyTests: XCTestCase {
    private let policy = VoiceCommandPolicy()

    private func context(
        linkReady: Bool = true,
        telemetryAge: TimeInterval? = 1,
        deviceUnlocked: Bool = true,
        confirmed: VoiceCommand? = nil,
        authenticated: VoiceCommand? = nil,
        climate: Bool = false,
        preview: Bool = true
    ) -> VoiceContext {
        VoiceContext(
            linkReady: linkReady,
            telemetryAge: telemetryAge,
            deviceUnlocked: deviceUnlocked,
            confirmedCommand: confirmed,
            authenticatedCommand: authenticated,
            climateServiceAvailable: climate,
            previewActionsEnabled: preview
        )
    }

    // MARK: Salt okunur

    func testStatusIsReadWithoutActionGates() {
        XCTAssertEqual(policy.decide(.status(.battery), context: context(linkReady: false)), .read(.battery))
        XCTAssertEqual(policy.decide(.status(.locks), context: context(linkReady: false)), .read(.locks))
    }

    func testHelpAndUnknownSpeak() {
        if case .speak(let text) = policy.decide(.help, context: context()) {
            XCTAssertTrue(text.contains("Şarj"))
        } else {
            XCTFail("help konuşmalı")
        }
        if case .speak(let text) = policy.decide(.unknown, context: context()) {
            XCTAssertTrue(text.contains("anlayamadım"))
        } else {
            XCTFail("unknown konuşmalı")
        }
    }

    // MARK: Eylem kapıları

    func testActionRejectedWhenLinkNotReady() {
        if case .reject(let text) = policy.decide(.lock, context: context(linkReady: false)) {
            XCTAssertTrue(text.contains("bağlantı"))
        } else {
            XCTFail("bağlantı kapısı reddetmeli")
        }
    }

    func testActionRejectedWhenTelemetryMissingOrStale() {
        if case .reject(let text) = policy.decide(.lock, context: context(telemetryAge: nil)) {
            XCTAssertTrue(text.contains("15 saniyeden eski"))
        } else {
            XCTFail("taze telemetri kapısı reddetmeli")
        }
        if case .reject(let text) = policy.decide(.lock, context: context(telemetryAge: 16)) {
            XCTAssertTrue(text.contains("15 saniyeden eski"))
        } else {
            XCTFail("eski telemetri kapısı reddetmeli")
        }
    }

    func testActionConfirmsBeforeExecuting() {
        guard case .confirm(let command, let prompt) = policy.decide(.lock, context: context()) else {
            return XCTFail("önce onay istemeli")
        }
        XCTAssertEqual(command, .lock)
        XCTAssertTrue(prompt.contains("onay"))

        XCTAssertEqual(policy.decide(.lock, context: context(confirmed: .lock)), .execute(.lock))
    }

    func testUnlockRequiresDeviceUnlock() {
        if case .reject(let text) = policy.decide(.unlock, context: context(deviceUnlocked: false)) {
            XCTAssertTrue(text.contains("telefonun kilidini"))
        } else {
            XCTFail("kilitli cihazda kilit açma reddedilmeli")
        }
    }

    func testUnlockRequiresConfirmationThenFaceID() {
        guard case .confirm = policy.decide(.unlock, context: context()) else {
            return XCTFail("önce onay istemeli")
        }

        guard case .authenticate(let command, let reason) = policy.decide(
            .unlock,
            context: context(confirmed: .unlock)
        ) else {
            return XCTFail("onaydan sonra Face ID istemeli")
        }
        XCTAssertEqual(command, .unlock)
        XCTAssertTrue(reason.contains("kimliğini doğrula"))

        XCTAssertEqual(
            policy.decide(.unlock, context: context(confirmed: .unlock, authenticated: .unlock)),
            .execute(.unlock)
        )
    }

    func testConfirmationDoesNotCarryToAnotherAction() {
        guard case .confirm = policy.decide(.unlock, context: context(confirmed: .lock)) else {
            return XCTFail("onay başka komuta taşınmamalı")
        }
    }

    func testPreviewPromptMentionsPreview() {
        guard case .confirm(_, let prompt) = policy.decide(.trunk(open: true), context: context()) else {
            return XCTFail("bagaj onay istemeli")
        }
        XCTAssertTrue(prompt.contains("önizleme"))

        guard case .confirm(_, let windowPrompt) = policy.decide(.windows(open: false), context: context()) else {
            return XCTFail("cam onay istemeli")
        }
        XCTAssertTrue(windowPrompt.contains("önizleme"))
    }

    func testPreviewCanBeDisabled() {
        if case .reject(let text) = policy.decide(.trunk(open: true), context: context(preview: false)) {
            XCTAssertTrue(text.contains("önizleme"))
        } else {
            XCTFail("önizleme kapalıysa reddetmeli")
        }
    }

    func testClimateUnavailableIsRejected() {
        if case .reject(let text) = policy.decide(.climate(on: true, temperature: 22), context: context()) {
            XCTAssertTrue(text.contains("İklimlendirme"))
        } else {
            XCTFail("klima servisi yokken reddetmeli")
        }
    }

    func testClimateAvailableUsesSameGates() {
        guard case .confirm(_, let prompt) = policy.decide(
            .climate(on: true, temperature: 22),
            context: context(climate: true)
        ) else {
            return XCTFail("klima onay istemeli")
        }
        XCTAssertTrue(prompt.contains("22"))
        XCTAssertEqual(
            policy.decide(.climate(on: true, temperature: 22), context: context(confirmed: .climate(on: true, temperature: 22), climate: true)),
            .execute(.climate(on: true, temperature: 22))
        )
    }

    func testFindVehicleIsPreviewOnly() {
        if case .reject(let text) = policy.decide(.findVehicle, context: context()) {
            XCTAssertTrue(text.contains("önizleme"))
        } else {
            XCTFail("aracı bulma komut göndermemeli")
        }
    }
}
