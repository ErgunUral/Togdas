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

        DashboardScreen(app: app).openMenu().selectTheme("Yüksek Kontrast")

        app = relaunch(app)
        let menu = DashboardScreen(app: app).openMenu()
        XCTAssertTrue(menu.theme("Yüksek Kontrast").waitForExistence(timeout: 5))
        XCTAssertTrue(menu.theme("Yüksek Kontrast").isSelected,
                      "Tema seçimi yeniden başlatmada korunmadı")
        XCTAssertFalse(menu.theme("Kurumsal").isSelected)

        // Diğer testleri etkilememek için varsayılana dön.
        menu.selectTheme("Kurumsal")
    }

    /// Eski 4 "düzen" 2 gerçek tercihe indi: Rahat / Sıkı. Sıkı yoğunluk
    /// içeriği gizlemez; yalnız blok aralığını daraltır (bilgi kaybı yok).
    func testDensityChoicePersistsAcrossRelaunch() {
        var app = launch(["-uiTestFixture", "-uiTestResetLook"])
        var dashboard = DashboardScreen(app: app)
        dashboard.waitForLoad()

        dashboard.openMenu().selectLayout("Sıkı")

        // Yoğunluk değişse de ilk ekran aynı blokları gösterir.
        XCTAssertTrue(dashboard.allControls.waitForExistence(timeout: 3),
                      "Sıkı yoğunlukta kontroller kayboldu")

        app = relaunch(app)
        dashboard = DashboardScreen(app: app)
        let menu = dashboard.openMenu()
        XCTAssertTrue(menu.layout("Sıkı").waitForExistence(timeout: 5))
        XCTAssertTrue(menu.layout("Sıkı").isSelected,
                      "Yoğunluk seçimi yeniden başlatmada korunmadı")
        menu.selectLayout("Rahat")
        // Seçim menüyü kapatır; kalıcılığı doğrulamak için yeniden açılır.
        XCTAssertTrue(DashboardScreen(app: app).openMenu().layout("Rahat").isSelected)
    }

    func testMenuExposesExactlyOneSelectedThemeAndLayout() {
        let app = launch(["-uiTestFixture", "-uiTestResetLook"])
        let dashboard = DashboardScreen(app: app)
        dashboard.waitForLoad()
        let menu = dashboard.openMenu()

        XCTAssertTrue(menu.theme("Kurumsal").waitForExistence(timeout: 5))
        XCTAssertEqual(MenuSheet.themeTitles.filter { menu.theme($0).isSelected }.count, 1,
                       "VoiceOver tek bir tema seçili bildirmeli")
        XCTAssertEqual(MenuSheet.layoutTitles.filter { menu.layout($0).isSelected }.count, 1,
                       "VoiceOver tek bir yoğunluk seçili bildirmeli")
    }

    func testLogoutReturnsToLoginScreen() {
        let app = launch(["-uiTestFixture", "-uiTestResetLook"])
        let dashboard = DashboardScreen(app: app)
        dashboard.waitForLoad()

        dashboard.openMenu().tap(.logout)

        let login = LoginScreen(app: app)
        XCTAssertTrue(login.toggButton.waitForExistence(timeout: 5),
                      "Çıkış sonrası giriş ekranı gelmedi")
        XCTAssertFalse(dashboard.tab("Bakım").exists)
        XCTAssertTrue(login.subtitle.exists)
    }
}
