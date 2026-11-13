// Görünüm tercihlerinin kalıcılığı ve oturum kapatma.
// `-uiTestResetLook` (yalnız DEBUG) tema/düzen anahtarlarını temizler;
// testler kendi başlangıç durumlarını garanti eder.

import XCTest

final class ToqdasSettingsTests: ToqdasUITestCase {
    private let themeTitles = ["Togg Gece", "Okyanus", "Grafit / Amber"]
    private let layoutTitles = [
        "Klasik · Tüm kartlar",
        "Minimal · Özet ve hızlı erişim",
        "Sportif · Kontroller önde",
        "Teknik · Tanı ve telemetri önde"
    ]

    private func openMenu(_ app: XCUIApplication) {
        app.descendants(matching: .any)["header.menu"].tap()
    }

    /// Menü uzun; ekran dışındaki öğeyi kaydırarak seçer.
    private func tapMenuItem(_ app: XCUIApplication, _ title: String) {
        let item = app.buttons[title]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Menüde \(title) yok")
        if !item.isHittable { app.swipeUp() }
        item.tap()
    }

    /// Yeniden başlatır; `-uiTestResetLook` gönderilmez ki tercihler korunsun.
    private func relaunch(_ app: XCUIApplication) -> XCUIApplication {
        app.terminate()
        let relaunched = XCUIApplication()
        relaunched.launchArguments = ["-uiTestSignedOut", "-uiTestFixture"]
        relaunched.launch()
        relaunched.waitForDashboard()
        return relaunched
    }

    func testThemeChoicePersistsAcrossRelaunch() {
        var app = launch(["-uiTestFixture", "-uiTestResetLook"])
        app.waitForDashboard()

        openMenu(app)
        tapMenuItem(app, "Okyanus")

        app = relaunch(app)
        openMenu(app)
        XCTAssertTrue(app.buttons["Okyanus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Okyanus"].isSelected, "Tema seçimi yeniden başlatmada korunmadı")
        XCTAssertFalse(app.buttons["Togg Gece"].isSelected)

        // Diğer testleri etkilememek için varsayılana dön.
        tapMenuItem(app, "Togg Gece")
    }

    func testLayoutChoicePersistsAcrossRelaunch() {
        var app = launch(["-uiTestFixture", "-uiTestResetLook"])
        app.waitForDashboard()
        XCTAssertTrue(app.buttons["proximity.scenarios"].scrollIntoView(app),
                      "Klasik düzende yakınlık kartı yok")

        openMenu(app)
        tapMenuItem(app, "Minimal · Özet ve hızlı erişim")

        XCTAssertTrue(app.buttons["proximity.scenarios"].waitForNonExistence(timeout: 3),
                      "Minimal düzende yakınlık kartı gizlenmedi")

        app = relaunch(app)
        XCTAssertTrue(app.buttons["proximity.scenarios"].waitForNonExistence(timeout: 3),
                      "Düzen seçimi yeniden başlatmada korunmadı")

        openMenu(app)
        XCTAssertTrue(app.buttons["Minimal · Özet ve hızlı erişim"].isSelected)
        tapMenuItem(app, "Klasik · Tüm kartlar")
        XCTAssertTrue(app.buttons["proximity.scenarios"].waitForExistence(timeout: 3))
    }

    func testMenuExposesExactlyOneSelectedThemeAndLayout() {
        let app = launch(["-uiTestFixture", "-uiTestResetLook"])
        app.waitForDashboard()
        openMenu(app)

        XCTAssertTrue(app.buttons["Togg Gece"].waitForExistence(timeout: 5))
        XCTAssertEqual(themeTitles.filter { app.buttons[$0].isSelected }.count, 1,
                       "VoiceOver tek bir tema seçili bildirmeli")
        XCTAssertEqual(layoutTitles.filter { app.buttons[$0].isSelected }.count, 1,
                       "VoiceOver tek bir düzen seçili bildirmeli")
    }

    func testLogoutReturnsToLoginScreen() {
        let app = launch(["-uiTestFixture", "-uiTestResetLook"])
        app.waitForDashboard()

        openMenu(app)
        tapMenuItem(app, "Çıkış yap")

        XCTAssertTrue(app.buttons["login.toggButton"].waitForExistence(timeout: 5),
                      "Çıkış sonrası giriş ekranı gelmedi")
        XCTAssertFalse(app.buttons["Araç Durumu sekmesi"].exists)
        XCTAssertTrue(app.staticTexts["Togg dijital anahtar ve araç kontrolü"].exists)
    }
}
