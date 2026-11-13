// Navigasyon dumanı: panodan açılan tüm ikincil yüzeyler açılır, doğru
// başlığı gösterir ve geri döner. Ağ/oturum yok — ekranlar dürüst boş veya
// hata durumunda açılır, çökme veya sessiz yönlendirme aranmaz.

import XCTest

final class ToqdasNavigationTests: ToqdasUITestCase {
    private func openMenuItem(_ app: XCUIApplication, _ title: String) {
        app.descendants(matching: .any)["header.menu"].tap()
        let item = app.buttons[title]
        if !item.waitForExistence(timeout: 3) {
            app.swipeUp()
        }
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Menüde \(title) yok")
        item.tap()
    }

    private func goBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5), "Geri düğmesi yok")
        back.tap()
        XCTAssertTrue(app.buttons["Araç Durumu sekmesi"].waitForExistence(timeout: 5),
                      "Panoya dönülmedi")
    }

    func testVoiceAssistantSheetOpensAndCloses() {
        let app = launchFixture()
        app.waitForDashboard()

        app.buttons["Sesli komut"].tap()
        XCTAssertTrue(app.staticTexts["Sesli Asistan"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Cihaz üstü Türkçe · internete gönderilmez"].exists)

        app.buttons["Kapat"].tap()
        XCTAssertTrue(app.staticTexts["Sesli Asistan"].waitForNonExistence(timeout: 3))
    }

    func testBLESetupGuideSheetOpensAndCloses() {
        let app = launchFixture()
        app.waitForDashboard()

        let setup = app.buttons["Kurulumu adım adım dinle"]
        XCTAssertTrue(setup.waitForExistence(timeout: 5), "Kurulum girişi yok")
        setup.tap()

        XCTAssertTrue(app.navigationBars["Dijital anahtar kurulumu"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ADIM 1 / 5"].exists)
        app.buttons["Kapat"].tap()
        XCTAssertTrue(app.navigationBars["Dijital anahtar kurulumu"].waitForNonExistence(timeout: 3))
    }

    func testKeyDiscoverySheetOpensAndCloses() {
        let app = launchFixture()
        app.waitForDashboard()

        let entry = app.buttons["Cihaz ortamında aday seç"]
        XCTAssertTrue(entry.scrollIntoView(app), "Aday seç girişi yok")
        entry.tap()

        XCTAssertTrue(app.navigationBars["Aday Seç"].waitForExistence(timeout: 5))
        app.buttons["Kapat"].tap()
        XCTAssertTrue(app.navigationBars["Aday Seç"].waitForNonExistence(timeout: 3))
    }

    func testBluetoothDiscoverySheetOpensAndCloses() {
        let app = launchFixture()
        app.waitForDashboard()

        openMenuItem(app, "Bluetooth taraması")
        XCTAssertTrue(app.navigationBars["Bluetooth"].waitForExistence(timeout: 10))
        app.buttons["Kapat"].tap()
        XCTAssertTrue(app.navigationBars["Bluetooth"].waitForNonExistence(timeout: 3))
    }

    func testVehicleDetailOpensAndReturns() {
        let app = launchFixture()
        app.waitForDashboard()

        openMenuItem(app, "Araç detayı")
        XCTAssertTrue(app.navigationBars["Araç bilgileri"].waitForExistence(timeout: 10))
        goBack(app)
    }

    func testServiceCardOpensAndReturns() {
        let app = launchFixture()
        app.waitForDashboard()

        openMenuItem(app, "Servis kartı")
        XCTAssertTrue(app.navigationBars["Servis kartı"].waitForExistence(timeout: 10))
        goBack(app)
    }

    func testDriveExperienceOpensAndReturns() {
        let app = launchFixture()
        app.waitForDashboard()

        openMenuItem(app, "Seyahatname")
        XCTAssertTrue(app.navigationBars["Sürüş & Şarj"].waitForExistence(timeout: 10))
        goBack(app)
    }

    func testAccountCenterOpensAndReturns() {
        let app = launchFixture()
        app.waitForDashboard()

        openMenuItem(app, "Bildirimler & destek")
        XCTAssertTrue(app.navigationBars["Bildirimler & Destek"].waitForExistence(timeout: 10))
        goBack(app)
    }
}
