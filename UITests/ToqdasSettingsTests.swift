// Görünüm tercihlerinin kalıcılığı ve oturum kapatma.
// `-uiTestResetLook` (yalnız DEBUG) tema/düzen anahtarlarını temizler;
// testler kendi başlangıç durumlarını garanti eder.

import XCTest

final class ToqdasSettingsTests: ToqdasUITestCase {
    /// Yeniden başlatır; `-uiTestResetLook` gönderilmez ki tercihler korunsun.
    private func relaunch(_ app: XCUIApplication) -> XCUIApplication {
        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["-uiTestSignedOut", "-uiTestFixture"]
        relaunched.launch()
        DashboardScreen(app: relaunched).waitForLoad()
        return relaunched
    }

    func testThemeChoicePersistsAcrossRelaunch() {
        var app = launch(["-uiTestFixture", "-uiTestResetLook"])
        DashboardScreen(app: app).waitForLoad()

        DashboardScreen(app: app).openMenu().selectTheme("Okyanus")

        app = relaunch(app)
        let menu = DashboardScreen(app: app).openMenu()
        XCTAssertTrue(menu.theme("Okyanus").waitForExistence(timeout: 5))
        XCTAssertTrue(menu.theme("Okyanus").isSelected,
                      "Tema seçimi yeniden başlatmada korunmadı")
        XCTAssertFalse(menu.theme("Togg Gece").isSelected)

        // Diğer testleri etkilememek için varsayılana dön.
        menu.selectTheme("Togg Gece")
    }

    func testLayoutChoicePersistsAcrossRelaunch() {
        var app = launch(["-uiTestFixture", "-uiTestResetLook"])
        var dashboard = DashboardScreen(app: app)
        dashboard.waitForLoad()
        XCTAssertTrue(dashboard.proximityScenarios.scrollIntoView(app),
                      "Klasik düzende yakınlık kartı yok")

        dashboard.openMenu().selectLayout("Minimal · Özet ve hızlı erişim")

        XCTAssertTrue(dashboard.proximityScenarios.waitForNonExistence(timeout: 3),
                      "Minimal düzende yakınlık kartı gizlenmedi")

        app = relaunch(app)
        dashboard = DashboardScreen(app: app)
        XCTAssertTrue(dashboard.proximityScenarios.waitForNonExistence(timeout: 3),
                      "Düzen seçimi yeniden başlatmada korunmadı")

        let menu = dashboard.openMenu()
        XCTAssertTrue(menu.layout("Minimal · Özet ve hızlı erişim").isSelected)
        menu.selectLayout("Klasik · Tüm kartlar")
        XCTAssertTrue(dashboard.proximityScenarios.waitForExistence(timeout: 3))
    }

    func testMenuExposesExactlyOneSelectedThemeAndLayout() {
        let app = launch(["-uiTestFixture", "-uiTestResetLook"])
        let dashboard = DashboardScreen(app: app)
        dashboard.waitForLoad()
        let menu = dashboard.openMenu()

        XCTAssertTrue(menu.theme("Togg Gece").waitForExistence(timeout: 5))
        XCTAssertEqual(MenuSheet.themeTitles.filter { menu.theme($0).isSelected }.count, 1,
                       "VoiceOver tek bir tema seçili bildirmeli")
        XCTAssertEqual(MenuSheet.layoutTitles.filter { menu.layout($0).isSelected }.count, 1,
                       "VoiceOver tek bir düzen seçili bildirmeli")
    }

    func testLogoutReturnsToLoginScreen() {
        let app = launch(["-uiTestFixture", "-uiTestResetLook"])
        let dashboard = DashboardScreen(app: app)
        dashboard.waitForLoad()

        dashboard.openMenu().tap(.logout)

        let login = LoginScreen(app: app)
        XCTAssertTrue(login.toggButton.waitForExistence(timeout: 5),
                      "Çıkış sonrası giriş ekranı gelmedi")
        XCTAssertFalse(dashboard.tab("Araç Durumu").exists)
        XCTAssertTrue(login.subtitle.exists)
    }
}
