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
        XCTAssertEqual(dashboard.tab("Genel Bakış").textValue, "Seçili",
                       "Açılışta Genel Bakış seçili olmalı")

        dashboard.selectTab("İklimlendirme")
        XCTAssertEqual(dashboard.tab("İklimlendirme").textValue, "Seçili")
        XCTAssertEqual(dashboard.tab("Genel Bakış").textValue, "")
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
    }
}
