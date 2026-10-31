import XCTest

final class ToqdasSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLoginScreenShowsToggEntryPoint() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSignedOut"]
        app.launch()

        XCTAssertTrue(app.staticTexts["TRUMORE"].waitForExistence(timeout: 8))
        let login = app.buttons["login.toggButton"]
        XCTAssertTrue(login.waitForExistence(timeout: 3))
        XCTAssertTrue(login.isEnabled)
        XCTAssertEqual(login.label, "Togg ID ile giriş yap")
    }

    func testTurkishCopySurvivesEnglishSystemLocale() {
        let app = XCUIApplication()
        app.launchArguments += [
            "-uiTestSignedOut",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()

        XCTAssertTrue(app.staticTexts["Togg ID ile giriş yap"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Togg dijital anahtar ve araç kontrolü"].exists)
    }

    func testFixtureDashboardShowsVehicleAndCommandTab() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSignedOut", "-uiTestFixture"]
        app.launch()

        XCTAssertTrue(app.staticTexts["TRUMORE"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["İklimlendirme sekmesi"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Araç Durumu sekmesi"].exists)
    }

    func testCommandGateDisablesVehicleCommandsWhenNotReady() {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSignedOut", "-uiTestFixture", "-openCommands"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Araç komutları"].waitForExistence(timeout: 10))

        let gate = app.staticTexts["commands.gateMessage"]
        _ = gate.waitForExistence(timeout: 5)
        for _ in 0..<8 where !gate.exists {
            app.swipeUp()
            _ = gate.waitForExistence(timeout: 2)
        }

        XCTAssertTrue(gate.waitForExistence(timeout: 5))
        let unlock = app.buttons["commands.unlock"]
        let lock = app.buttons["commands.lock"]
        XCTAssertTrue(unlock.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(unlock.firstMatch.isEnabled)
        XCTAssertTrue(lock.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(lock.firstMatch.isEnabled)
    }
}
