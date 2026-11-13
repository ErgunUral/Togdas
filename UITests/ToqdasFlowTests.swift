// Pano akışları: sekmeler, fixture telemetrisi, sağlık kartı, şarj sekmesi.

import XCTest

final class ToqdasFlowTests: ToqdasUITestCase {
    func testAllFourTabsArePresentAndSelectable() {
        let app = launchFixture()
        app.waitForDashboard()

        for title in ["Genel Bakış", "İklimlendirme", "Trugo Şarj", "Araç Durumu"] {
            XCTAssertTrue(app.buttons["\(title) sekmesi"].waitForExistence(timeout: 5),
                          "\(title) sekmesi yok")
        }

        app.buttons["Araç Durumu sekmesi"].tap()
        XCTAssertTrue(app.staticTexts["Araç Sağlığı & Lastik Basınçları"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["Araç Durumu sekmesi"].textValue, "Seçili")
        XCTAssertEqual(app.buttons["Genel Bakış sekmesi"].textValue, "")
    }

    func testOverviewShowsFixtureVehicleAndTelemetry() {
        let app = launchFixture()
        app.waitForDashboard()

        XCTAssertTrue(app.staticTexts["UI Test Aracı • UI 0001"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["%79"].exists, "Akü yüzdesi gösterilmiyor")
        XCTAssertTrue(app.staticTexts["365"].exists, "Menzil gösterilmiyor")
    }

    func testClimateTabShowsTargetTemperatureControls() {
        let app = launchFixture()
        app.waitForDashboard()

        app.buttons["İklimlendirme sekmesi"].tap()
        XCTAssertTrue(app.staticTexts["Klima & İklimlendirme"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Hedef Sıcaklık"].exists)
    }

    func testHealthTabShowsAuxBatteryAndKeepsMissingDataAsDash() {
        let app = launchFixture()
        app.waitForDashboard()

        app.buttons["Araç Durumu sekmesi"].tap()
        XCTAssertTrue(app.staticTexts["Araç Sağlığı & Lastik Basınçları"].waitForExistence(timeout: 5))

        let auxiliary = app.element(labelled: "12 V Akü")
        XCTAssertTrue(auxiliary.waitForExistence(timeout: 5))
        XCTAssertEqual(auxiliary.textValue, "%65")

        // Fixture'ın bulut anlık görüntüsü lastik basıncını taşımaz; eksik veri
        // 0 PSI'ye sıkıştırılmaz, açıkça "bilgi yok" olarak gösterilir.
        let frontLeft = app.element(labelled: "Sol Ön")
        XCTAssertTrue(frontLeft.waitForExistence(timeout: 5))
        XCTAssertEqual(frontLeft.textValue, "basınç bilgisi yok")

        // Değişmez: eksik veri 0 değil "—" olarak gösterilir (fixture'da sürüş modu yok).
        let driveMode = app.element(labelled: "Sürüş Modu")
        XCTAssertTrue(driveMode.waitForExistence(timeout: 5))
        XCTAssertEqual(driveMode.textValue, "—")
    }

    func testChargingTabOffersTrugoStationsEntry() {
        let app = launchFixture(["-openChargingTab"])
        app.waitForDashboard()

        let stations = app.staticTexts["En Yakın Trugo Şarj İstasyonları"]
        XCTAssertTrue(stations.scrollIntoView(app), "Trugo istasyon kartı bulunamadı")
        XCTAssertTrue(app.staticTexts["Yakındaki istasyonları gör"].exists)
    }
}
