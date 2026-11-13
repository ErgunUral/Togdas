// Pano akışları: sekmeler, fixture telemetrisi, sağlık kartı, şarj sekmesi.

import XCTest

final class ToqdasFlowTests: ToqdasUITestCase {
    func testAllFourTabsArePresentAndSelectable() {
        let app = launchFixture()
        let dashboard = DashboardScreen(app: app)
        dashboard.waitForLoad()

        for title in DashboardScreen.tabs {
            XCTAssertTrue(dashboard.tab(title).waitForExistence(timeout: 5),
                          "\(title) sekmesi yok")
        }

        dashboard.selectTab("Araç Durumu")
        XCTAssertTrue(dashboard.healthHeading.waitForExistence(timeout: 5))
        XCTAssertEqual(dashboard.tab("Araç Durumu").textValue, "Seçili")
        XCTAssertEqual(dashboard.tab("Genel Bakış").textValue, "")
    }

    func testOverviewShowsFixtureVehicleAndTelemetry() {
        let app = launchFixture()
        let dashboard = DashboardScreen(app: app)
        dashboard.waitForLoad()

        XCTAssertTrue(dashboard.vehicleName.waitForExistence(timeout: 5))
        XCTAssertTrue(dashboard.batteryPercent.exists, "Akü yüzdesi gösterilmiyor")
        XCTAssertTrue(dashboard.range.exists, "Menzil gösterilmiyor")
    }

    func testClimateTabShowsTargetTemperatureControls() {
        let app = launchFixture()
        let dashboard = DashboardScreen(app: app)
        dashboard.waitForLoad()

        dashboard.selectTab("İklimlendirme")
        XCTAssertTrue(app.staticTexts["Klima & İklimlendirme"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Hedef Sıcaklık"].exists)
    }

    func testHealthTabShowsAuxBatteryAndKeepsMissingDataAsDash() {
        let app = launchFixture()
        let dashboard = DashboardScreen(app: app)
        dashboard.waitForLoad()

        dashboard.selectTab("Araç Durumu")
        XCTAssertTrue(dashboard.healthHeading.waitForExistence(timeout: 5))

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
        let dashboard = DashboardScreen(app: app)
        dashboard.waitForLoad()

        let stations = app.staticTexts["En Yakın Trugo Şarj İstasyonları"]
        XCTAssertTrue(stations.scrollIntoView(app), "Trugo istasyon kartı bulunamadı")
        XCTAssertTrue(app.staticTexts["Yakındaki istasyonları gör"].exists)
    }
}
