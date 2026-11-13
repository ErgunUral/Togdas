import XCTest

final class ToqdasSmokeTests: ToqdasUITestCase {
    func testLoginScreenShowsToggEntryPoint() {
        let app = launch()
        let login = LoginScreen(app: app)

        XCTAssertTrue(login.title.waitForExistence(timeout: 8))
        XCTAssertTrue(login.toggButton.waitForExistence(timeout: 3))
        XCTAssertTrue(login.toggButton.isEnabled)
        XCTAssertEqual(login.toggButton.label, "Togg ID ile giriş yap")
    }

    func testTurkishCopySurvivesEnglishSystemLocale() {
        let app = launch(["-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
        let login = LoginScreen(app: app)

        XCTAssertTrue(login.signInCopy.waitForExistence(timeout: 8))
        XCTAssertTrue(login.subtitle.exists)
    }

    func testFixtureDashboardShowsVehicleAndCommandTab() {
        let app = launchFixture()
        let dashboard = DashboardScreen(app: app)

        XCTAssertTrue(dashboard.title.waitForExistence(timeout: 8))
        XCTAssertTrue(dashboard.tab("İklimlendirme").waitForExistence(timeout: 3))
        XCTAssertTrue(dashboard.tab("Araç Durumu").exists)
    }

    func testCommandGateDisablesVehicleCommandsWhenNotReady() {
        let app = launchFixture(["-openCommands"])
        let commands = CommandSheet(app: app)
        commands.waitForOpen()

        let gate = commands.gateMessage
        XCTAssertTrue(gate.scrollIntoView(app), "Komut kapısı açıklaması bulunamadı")

        let unlock = commands.unlock
        let lock = commands.lock
        XCTAssertTrue(unlock.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(unlock.firstMatch.isEnabled)
        XCTAssertTrue(lock.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(lock.firstMatch.isEnabled)
    }
}
