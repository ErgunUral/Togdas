// Komut kapısı: hazır olmayan bağlantıda komut gönderilemez ve onay istenmez.

import XCTest

final class ToqdasCommandTests: ToqdasUITestCase {
    func testCommandGateExplainsWhyCommandsAreDisabled() {
        let app = launchFixture(["-openCommands"])
        let commands = CommandSheet(app: app)
        commands.waitForOpen()

        let gate = commands.gateMessage
        XCTAssertTrue(gate.scrollIntoView(app), "Komut kapısı açıklaması bulunamadı")
        XCTAssertFalse(gate.label.isEmpty, "Kapı açıklaması boş")

        for identifier in CommandSheet.identifiers {
            let button = commands.button(identifier)
            XCTAssertTrue(button.waitForExistence(timeout: 5), "\(identifier) yok")
            XCTAssertFalse(button.isEnabled,
                           "\(identifier) bağlantı hazır değilken etkin olmamalı")
        }
    }

    func testTappingDisabledCommandDoesNotAskForConfirmation() {
        let app = launchFixture(["-openCommands"])
        let commands = CommandSheet(app: app)
        commands.waitForOpen()

        let unlock = commands.unlock
        XCTAssertTrue(unlock.scrollIntoView(app), "Kilidi aç düğmesi bulunamadı")
        XCTAssertFalse(unlock.isEnabled)
        // Devre dışı düğmeye dokunma: onay kapısı açılmamalı.
        unlock.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertFalse(app.alerts["Komut gönderilsin mi?"].waitForExistence(timeout: 2),
                       "Hazır olmayan bağlantıda onay istendi")
        XCTAssertTrue(commands.navigationBar.exists)
    }

    func testHeaderMenuOpensCommandsSheetAndCloses() {
        let app = launchFixture()
        let dashboard = DashboardScreen(app: app)
        dashboard.waitForLoad()

        let commands = dashboard.openMenu().openCommands()
        XCTAssertTrue(commands.closeButton.waitForExistence(timeout: 5))
        commands.closeButton.tap()

        XCTAssertTrue(dashboard.title.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Araç komutları"].exists)
    }
}
