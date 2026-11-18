// Erişilebilirlik: VoiceOver etiketleri, seçili durum, 44pt hedefler,
// büyük Dynamic Type ile açılış.

import XCTest

final class ToqdasAccessibilityTests: ToqdasUITestCase {
    func testTabBarTargetsAreAtLeastFortyFourPoints() {
        let app = launchFixture()
        let dashboard = DashboardScreen(app: app)
        dashboard.waitForLoad()

        for title in DashboardScreen.tabs {
            let tab = dashboard.tab(title)
            XCTAssertTrue(tab.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(tab.frame.height, 43.5,
                                        "\(title) dokunma hedefi 44pt'den küçük")
            XCTAssertTrue(tab.isHittable, "\(title) sekmesi dokunulabilir değil")
        }
    }

    func testTabBarExposesVoiceOverLabelsAndSelectedState() {
        let app = launchFixture()
        let dashboard = DashboardScreen(app: app)
        dashboard.waitForLoad()

        for title in DashboardScreen.tabs {
            let tab = dashboard.tab(title)
            XCTAssertTrue(tab.waitForExistence(timeout: 5))
            XCTAssertEqual(tab.label, "\(title) sekmesi")
        }
        XCTAssertEqual(dashboard.tab("Araç").textValue, "Seçili",
                       "Açılışta Araç sekmesi seçili olmalı")

        dashboard.selectTab("Enerji")
        XCTAssertEqual(dashboard.tab("Enerji").textValue, "Seçili")
        XCTAssertEqual(dashboard.tab("Araç").textValue, "")
    }

    func testDashboardSurvivesAccessibilityExtraExtraExtraLargeType() {
        let app = launchFixture([
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        let dashboard = DashboardScreen(app: app)
        dashboard.waitForLoad()

        for title in DashboardScreen.tabs {
            let tab = dashboard.tab(title)
            XCTAssertTrue(tab.waitForExistence(timeout: 5),
                          "\(title) büyük yazıda kayboldu")
            XCTAssertTrue(tab.isHittable)
        }
        XCTAssertTrue(dashboard.batteryPercent.exists)

        // Yeni durum şeritleri büyük yazıda da var olmalı (kırpma denetimi
        // ayrı: ToqdasAccessibilityAuditTests).
        dashboard.selectTab("Enerji")
        XCTAssertTrue(app.staticTexts["ENERJİ"].waitForExistence(timeout: 5),
                      "Enerji durum şeridi büyük yazıda yok")
        XCTAssertTrue(app.staticTexts["Veriyi yenile"].exists)

        dashboard.selectTab("Bakım")
        XCTAssertTrue(app.staticTexts["BAKIM"].waitForExistence(timeout: 5),
                      "Bakım durum şeridi büyük yazıda yok")
    }
}
