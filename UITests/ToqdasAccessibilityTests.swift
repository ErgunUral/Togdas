// Erişilebilirlik: VoiceOver etiketleri, seçili durum, 44pt hedefler,
// büyük Dynamic Type ile açılış.

import XCTest

final class ToqdasAccessibilityTests: ToqdasUITestCase {
    private let tabTitles = ["Genel Bakış", "İklimlendirme", "Trugo Şarj", "Araç Durumu"]

    func testTabBarTargetsAreAtLeastFortyFourPoints() {
        let app = launchFixture()
        app.waitForDashboard()

        for title in tabTitles {
            let tab = app.buttons["\(title) sekmesi"]
            XCTAssertTrue(tab.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(tab.frame.height, 43.5,
                                        "\(title) dokunma hedefi 44pt'den küçük")
            XCTAssertTrue(tab.isHittable, "\(title) sekmesi dokunulabilir değil")
        }
    }

    func testTabBarExposesVoiceOverLabelsAndSelectedState() {
        let app = launchFixture()
        app.waitForDashboard()

        for title in tabTitles {
            let tab = app.buttons["\(title) sekmesi"]
            XCTAssertTrue(tab.waitForExistence(timeout: 5))
            XCTAssertEqual(tab.label, "\(title) sekmesi")
        }
        XCTAssertEqual(app.buttons["Genel Bakış sekmesi"].textValue, "Seçili",
                       "Açılışta Genel Bakış seçili olmalı")

        app.buttons["İklimlendirme sekmesi"].tap()
        XCTAssertEqual(app.buttons["İklimlendirme sekmesi"].textValue, "Seçili")
        XCTAssertEqual(app.buttons["Genel Bakış sekmesi"].textValue, "")
    }

    func testDashboardSurvivesAccessibilityExtraExtraExtraLargeType() {
        let app = launchFixture([
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"
        ])
        app.waitForDashboard()

        for title in tabTitles {
            let tab = app.buttons["\(title) sekmesi"]
            XCTAssertTrue(tab.waitForExistence(timeout: 5),
                          "\(title) büyük yazıda kayboldu")
            XCTAssertTrue(tab.isHittable)
        }
        XCTAssertTrue(app.staticTexts["%79"].exists)
    }
}
