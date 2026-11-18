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

        dashboard.selectTab("Bakım")
        XCTAssertTrue(dashboard.healthHeading.waitForExistence(timeout: 5))
        XCTAssertEqual(dashboard.tab("Bakım").textValue, "Seçili")
        XCTAssertEqual(dashboard.tab("Araç").textValue, "")
    }

    func testOverviewShowsFixtureVehicleAndTelemetry() {
        let app = launchFixture()
        let dashboard = DashboardScreen(app: app)
        dashboard.waitForLoad()

        XCTAssertTrue(dashboard.vehicleName.waitForExistence(timeout: 5))
        XCTAssertTrue(dashboard.batteryPercent.exists, "Akü yüzdesi gösterilmiyor")
        XCTAssertTrue(dashboard.range.exists, "Menzil gösterilmiyor")
        // İmzalı durum yokken dört "Bilinmiyor" karosu yerine tek eylem kartı.
        XCTAssertTrue(app.staticTexts["Araç durumu henüz okunmadı"].exists,
                      "Durum yokken eylem kartı gösterilmeli")
    }

    func testClimateTabShowsTargetTemperatureControls() {
        let app = launchFixture()
        let dashboard = DashboardScreen(app: app)
        dashboard.waitForLoad()

        // İklimlendirme ayrı sekme değil: "Araç → Tüm kontroller" derinliğinde.
        dashboard.selectTab("Araç")
        app.buttons["vehicle.allControls"].tap()
        XCTAssertTrue(app.staticTexts["Klima & İklimlendirme"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Hedef Sıcaklık"].exists)
    }

    func testHealthTabShowsAuxBatteryAndKeepsMissingDataAsDash() {
        let app = launchFixture()
        let dashboard = DashboardScreen(app: app)
        dashboard.waitForLoad()

        dashboard.selectTab("Bakım")
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
