// Senaryolar rehberi ve yakınlık kalibrasyon sheet'i.

import XCTest

final class ToqdasGuideTests: ToqdasUITestCase {
    func testScenarioGuideOpensFromHeaderMenuAndCloses() {
        let app = launchFixture()
        let dashboard = DashboardScreen(app: app)
        dashboard.waitForLoad()

        let guide = dashboard.openMenu().openScenarioGuide()
        XCTAssertTrue(guide.navigationBar.exists)
        XCTAssertTrue(guide.section("Kurulum").exists, "Kurulum bölümü yok")

        XCTAssertTrue(guide.closeButton.exists)
        guide.closeButton.tap()

        XCTAssertFalse(guide.liveStatus.waitForExistence(timeout: 2))
        XCTAssertTrue(dashboard.title.exists)
    }

    func testScenarioGuideShowsLiveStatusBadges() {
        let app = launchFixture()
        let dashboard = DashboardScreen(app: app)
        dashboard.waitForLoad()
        let guide = dashboard.openMenu().openScenarioGuide()

        XCTAssertTrue(guide.liveStatus.exists)
        // Canlı durum şeridi en az bir rozet içerir ("Başlık: değer" biçiminde).
        let badges = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", ": "))
            .count
        XCTAssertGreaterThan(badges, 0, "Canlı durum rozeti yok")
    }

    func testProximityCardBookOpensGuideAtProximitySection() {
        let app = launchFixture()
        let dashboard = DashboardScreen(app: app)
        dashboard.waitForLoad()

        XCTAssertTrue(dashboard.proximityScenarios.scrollIntoView(app),
                      "Yakınlık senaryoları düğmesi bulunamadı")
        dashboard.proximityScenarios.tap()

        let guide = ScenarioGuideSheet(app: app)
        guide.waitForOpen()

        let heading = guide.section("Yakınlık Otomasyonu")
        if !heading.waitForExistence(timeout: 3) { app.swipeUp() }
        XCTAssertTrue(heading.waitForExistence(timeout: 3),
                      "Rehber yakınlık bölümüne odaklanmadı")
        XCTAssertTrue(app.element(labelBeginningWith: "Önce kalibrasyon").exists)
    }

    func testProximityCalibrationSheetOpensAndCloses() {
        let app = launchFixture()
        let dashboard = DashboardScreen(app: app)
        dashboard.waitForLoad()

        XCTAssertTrue(dashboard.proximityCalibration.scrollIntoView(app),
                      "Kalibrasyon düğmesi bulunamadı")
        dashboard.proximityCalibration.tap()

        let calibration = CalibrationSheet(app: app)
        XCTAssertTrue(calibration.liveSignal.waitForExistence(timeout: 5),
                      "Kalibrasyon sheet'i açılmadı")
        XCTAssertTrue(calibration.navigationBar.exists)

        XCTAssertTrue(calibration.doneButton.exists)
        calibration.doneButton.tap()
        XCTAssertFalse(calibration.liveSignal.waitForExistence(timeout: 2))
    }
}
