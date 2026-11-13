// Navigasyon dumanı: panodan açılan tüm ikincil yüzeyler açılır, doğru
// başlığı gösterir ve geri döner. Ağ/oturum yok — ekranlar dürüst boş veya
// hata durumunda açılır, çökme veya sessiz yönlendirme aranmaz.

import XCTest

final class ToqdasNavigationTests: ToqdasUITestCase {
    private func goBack(_ app: XCUIApplication) {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        XCTAssertTrue(back.waitForExistence(timeout: 5), "Geri düğmesi yok")
        back.tap()
        XCTAssertTrue(DashboardScreen(app: app).tab("Araç Durumu").waitForExistence(timeout: 5),
                      "Panoya dönülmedi")
    }

    func testVoiceAssistantSheetOpensAndCloses() {
        let app = launchFixture()
        let dashboard = DashboardScreen(app: app)
        dashboard.waitForLoad()

        dashboard.voiceAssistant.tap()
        XCTAssertTrue(app.staticTexts["Sesli Asistan"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Cihaz üstü Türkçe · internete gönderilmez"].exists)

        app.buttons["Kapat"].tap()
        XCTAssertTrue(app.staticTexts["Sesli Asistan"].waitForNonExistence(timeout: 3))
    }

    func testBLESetupGuideSheetOpensAndCloses() {
        let app = launchFixture()
        let dashboard = DashboardScreen(app: app)
        dashboard.waitForLoad()

        XCTAssertTrue(dashboard.bleSetupGuide.waitForExistence(timeout: 5),
                      "Kurulum girişi yok")
        dashboard.bleSetupGuide.tap()

        XCTAssertTrue(app.navigationBars["Dijital anahtar kurulumu"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ADIM 1 / 5"].exists)
        app.buttons["Kapat"].tap()
        XCTAssertTrue(app.navigationBars["Dijital anahtar kurulumu"].waitForNonExistence(timeout: 3))
    }

    func testKeyDiscoverySheetOpensAndCloses() {
        let app = launchFixture()
        let dashboard = DashboardScreen(app: app)
        dashboard.waitForLoad()

        XCTAssertTrue(dashboard.keyDiscovery.scrollIntoView(app), "Aday seç girişi yok")
        dashboard.keyDiscovery.tap()

        XCTAssertTrue(app.navigationBars["Aday Seç"].waitForExistence(timeout: 5))
        app.buttons["Kapat"].tap()
        XCTAssertTrue(app.navigationBars["Aday Seç"].waitForNonExistence(timeout: 3))
    }

    func testBluetoothDiscoverySheetOpensAndCloses() {
        let app = launchFixture()
        let dashboard = DashboardScreen(app: app)
        dashboard.waitForLoad()

        dashboard.openMenu().tap(.bluetoothScan)
        XCTAssertTrue(app.navigationBars["Bluetooth"].waitForExistence(timeout: 10))
        app.buttons["Kapat"].tap()
        XCTAssertTrue(app.navigationBars["Bluetooth"].waitForNonExistence(timeout: 3))
    }

    func testVehicleDetailOpensAndReturns() {
        let app = launchFixture()
        let dashboard = DashboardScreen(app: app)
        dashboard.waitForLoad()

        dashboard.openMenu().tap(.vehicleDetail)
        XCTAssertTrue(app.navigationBars["Araç bilgileri"].waitForExistence(timeout: 10))
        goBack(app)
    }

    func testServiceCardOpensAndReturns() {
        let app = launchFixture()
        let dashboard = DashboardScreen(app: app)
        dashboard.waitForLoad()

        dashboard.openMenu().tap(.serviceCard)
        XCTAssertTrue(app.navigationBars["Servis kartı"].waitForExistence(timeout: 10))
        goBack(app)
    }

    func testDriveExperienceOpensAndReturns() {
        let app = launchFixture()
        let dashboard = DashboardScreen(app: app)
        dashboard.waitForLoad()

        dashboard.openMenu().tap(.driveExperience)
        XCTAssertTrue(app.navigationBars["Sürüş & Şarj"].waitForExistence(timeout: 10))
        goBack(app)
    }

    func testAccountCenterOpensAndReturns() {
        let app = launchFixture()
        let dashboard = DashboardScreen(app: app)
        dashboard.waitForLoad()

        dashboard.openMenu().tap(.accountCenter)
        XCTAssertTrue(app.navigationBars["Bildirimler & Destek"].waitForExistence(timeout: 10))
        goBack(app)
    }
}
