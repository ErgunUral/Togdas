// Komut kapısı: hazır olmayan bağlantıda komut gönderilemez ve onay istenmez.

import XCTest

final class ToqdasCommandTests: ToqdasUITestCase {
    private let commandIdentifiers = [
        "commands.unlock",
        "commands.lock",
        "commands.trunkOpen",
        "commands.trunkClose",
        "commands.driveAuthorize"
    ]

    func testCommandGateExplainsWhyCommandsAreDisabled() {
        let app = launchFixture(["-openCommands"])
        XCTAssertTrue(app.staticTexts["Araç komutları"].waitForExistence(timeout: 10))

        let gate = app.staticTexts["commands.gateMessage"]
        XCTAssertTrue(gate.scrollIntoView(app), "Komut kapısı açıklaması bulunamadı")
        XCTAssertFalse(gate.label.isEmpty, "Kapı açıklaması boş")

        for identifier in commandIdentifiers {
            let button = app.buttons[identifier]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "\(identifier) yok")
            XCTAssertFalse(button.isEnabled,
                           "\(identifier) bağlantı hazır değilken etkin olmamalı")
        }
    }

    func testTappingDisabledCommandDoesNotAskForConfirmation() {
        let app = launchFixture(["-openCommands"])
        XCTAssertTrue(app.staticTexts["Araç komutları"].waitForExistence(timeout: 10))

        let unlock = app.buttons["commands.unlock"]
        XCTAssertTrue(unlock.scrollIntoView(app), "Kilidi aç düğmesi bulunamadı")
        XCTAssertFalse(unlock.isEnabled)
        // Devre dışı düğmeye dokunma: onay kapısı açılmamalı.
        unlock.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertFalse(app.alerts["Komut gönderilsin mi?"].waitForExistence(timeout: 2),
                       "Hazır olmayan bağlantıda onay istendi")
        XCTAssertTrue(app.staticTexts["Araç komutları"].exists)
    }

    func testHeaderMenuOpensCommandsSheetAndCloses() {
        let app = launchFixture()
        app.waitForDashboard()

        app.descendants(matching: .any)["header.menu"].tap()
        let commandsItem = app.buttons["Bluetooth komutları"]
        XCTAssertTrue(commandsItem.waitForExistence(timeout: 5), "Menü öğesi görünmedi")
        commandsItem.tap()

        XCTAssertTrue(app.staticTexts["Araç komutları"].waitForExistence(timeout: 10))

        let close = app.buttons["Kapat"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()

        XCTAssertTrue(app.staticTexts["TRUMORE"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Araç komutları"].exists)
    }
}
