import XCTest
@testable import ToqdasCore

/// Saat ses/bildirim kararları: kanal, sönümleme, tazelik, ayarlar.
final class WatchSoundPolicyTests: XCTestCase {

    // MARK: - Kanal

    func testForegroundUsesChimeAndBackgroundUsesNotifications() {
        for event in WatchSoundPolicy.Event.allCases {
            let foreground = WatchSoundPolicy.decision(event: event, enabled: true,
                                                       fresh: true, foreground: true,
                                                       sinceLast: nil)
            guard case .announce(.chime(let tone)) = foreground else {
                return XCTFail("ön planda ton beklenirdi: \(event)")
            }
            XCTAssertEqual(WatchSoundPolicy.tone(for: event), tone)
        }
    }

    func testUnlockIsDistinguishableFromLockInBackground() {
        // watchOS özel bildirim sesi desteklemez: ayrım yalnız sayıyla.
        XCTAssertEqual(WatchSoundPolicy.notificationCount(for: .unlocked), 2)
        XCTAssertEqual(WatchSoundPolicy.notificationCount(for: .locked), 1)
        let unlocked = WatchSoundPolicy.decision(event: .unlocked, enabled: true,
                                                 fresh: true, foreground: false, sinceLast: nil)
        let locked = WatchSoundPolicy.decision(event: .locked, enabled: true,
                                               fresh: true, foreground: false, sinceLast: nil)
        XCTAssertEqual(unlocked, .announce(.notification(2)))
        XCTAssertEqual(locked, .announce(.notification(1)))
    }

    func testTonesDifferPerDirection() {
        XCTAssertEqual(WatchSoundPolicy.tone(for: .locked), .lock)
        XCTAssertEqual(WatchSoundPolicy.tone(for: .unlocked), .unlock)
        XCTAssertNotEqual(WatchSoundPolicy.tone(for: .locked),
                          WatchSoundPolicy.tone(for: .unlocked))
        XCTAssertNotEqual(WatchSoundPolicy.tone(for: .commandForwarded),
                          WatchSoundPolicy.tone(for: .commandFailed))
    }

    // MARK: - Tazelik

    func testStaleDataSuppressesVehicleAnnouncements() {
        for event in [WatchSoundPolicy.Event.connected, .resumed, .locked, .unlocked] {
            XCTAssertEqual(
                WatchSoundPolicy.decision(event: event, enabled: true,
                                          fresh: false, foreground: true, sinceLast: nil),
                .suppressed("imzalı veri eski"),
                "eski veriyle araç durumu duyurusu yapılmamalı: \(event)")
        }
    }

    func testCommandResultIsNotGatedByTelemetryFreshness() {
        XCTAssertEqual(
            WatchSoundPolicy.decision(event: .commandForwarded, enabled: true,
                                      fresh: false, foreground: false, sinceLast: nil),
            .announce(.notification(1)))
    }

    // MARK: - Sönümleme

    func testDampingSuppressesRepeatWithinWindow() {
        XCTAssertEqual(
            WatchSoundPolicy.decision(event: .locked, enabled: true, fresh: true,
                                      foreground: false, sinceLast: 3),
            .suppressed("sönümleme penceresi"))
        XCTAssertEqual(
            WatchSoundPolicy.decision(event: .locked, enabled: true, fresh: true,
                                      foreground: false, sinceLast: 16),
            .announce(.notification(1)))
    }

    func testConnectionDampingIsLongerThanLock() {
        XCTAssertEqual(WatchSoundPolicy.damping(for: .connected), 90)
        XCTAssertEqual(WatchSoundPolicy.damping(for: .resumed), 60)
        XCTAssertEqual(WatchSoundPolicy.damping(for: .locked), 15)
        XCTAssertEqual(WatchSoundPolicy.damping(for: .commandFailed), 5)
    }

    func testResumedSharesConnectionDampingKey() {
        XCTAssertEqual(WatchSoundPolicy.dampingKey(for: .resumed),
                       WatchSoundPolicy.dampingKey(for: .connected))
        XCTAssertNotEqual(WatchSoundPolicy.dampingKey(for: .locked),
                          WatchSoundPolicy.dampingKey(for: .unlocked))
    }

    // MARK: - Ayar

    func testDisabledToggleSuppressesEverything() {
        for event in WatchSoundPolicy.Event.allCases {
            XCTAssertEqual(
                WatchSoundPolicy.decision(event: event, enabled: false,
                                          fresh: true, foreground: true, sinceLast: nil),
                .suppressed("ayar kapalı"))
        }
    }

    func testToggleGroupingIsThreeSwitches() {
        XCTAssertEqual(WatchSoundPolicy.Toggle.allCases.count, 3)
        XCTAssertEqual(WatchSoundPolicy.toggle(for: .connected), .connection)
        XCTAssertEqual(WatchSoundPolicy.toggle(for: .resumed), .connection)
        XCTAssertEqual(WatchSoundPolicy.toggle(for: .locked), .lock)
        XCTAssertEqual(WatchSoundPolicy.toggle(for: .unlocked), .lock)
        XCTAssertEqual(WatchSoundPolicy.toggle(for: .commandForwarded), .command)
        XCTAssertEqual(WatchSoundPolicy.toggle(for: .commandFailed), .command)
    }

    func testSettingsDefaultToEnabledAndPersist() {
        let suite = UserDefaults(suiteName: "watch.sound.policy.tests")!
        WatchSoundSettings.reset(defaults: suite)
        for toggle in WatchSoundPolicy.Toggle.allCases {
            XCTAssertTrue(WatchSoundSettings.isEnabled(toggle, defaults: suite))
        }
        WatchSoundSettings.set(false, for: .lock, defaults: suite)
        XCTAssertFalse(WatchSoundSettings.isEnabled(.lock, defaults: suite))
        XCTAssertTrue(WatchSoundSettings.isEnabled(.connection, defaults: suite))
        WatchSoundSettings.reset(defaults: suite)
        XCTAssertTrue(WatchSoundSettings.isEnabled(.lock, defaults: suite))
    }

    func testSettingKeysAreStableAndCarryNoVIN() {
        for toggle in WatchSoundPolicy.Toggle.allCases {
            XCTAssertTrue(toggle.key.hasPrefix("toqdas.watch.sound."))
            XCTAssertFalse(toggle.key.contains("vin"))
        }
    }

    // MARK: - Metinler

    func testLockAndUnlockTextsAreDirectionSpecificAndHonest() {
        let locked = WatchSoundPolicy.body(for: .locked)
        let unlocked = WatchSoundPolicy.body(for: .unlocked)
        XCTAssertNotEqual(locked, unlocked)
        XCTAssertTrue(locked.contains("kilitli"))
        XCTAssertTrue(unlocked.contains("açık"))
        // Ack "uygulandı" diye yazılmaz.
        XCTAssertFalse(WatchSoundPolicy.body(for: .commandForwarded).contains("kilitlendi"))
        XCTAssertTrue(WatchSoundPolicy.body(for: .commandForwarded).contains("doğrulanır"))
        XCTAssertTrue(WatchSoundPolicy.body(for: .commandFailed).contains("gerekçe bildirmiyor"))
        for event in WatchSoundPolicy.Event.allCases {
            XCTAssertFalse(WatchSoundPolicy.title(for: event).isEmpty)
            XCTAssertFalse(WatchSoundPolicy.body(for: event).isEmpty)
        }
    }
}
