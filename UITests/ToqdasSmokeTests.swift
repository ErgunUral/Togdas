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
}
