// Senaryolar rehberi ve yakınlık kalibrasyon sheet'i.

import XCTest

final class ToqdasGuideTests: ToqdasUITestCase {
    private func openScenarioGuideFromMenu(_ app: XCUIApplication) {
        app.descendants(matching: .any)["header.menu"].tap()
        let item = app.buttons["Senaryolar rehberi"]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Menüde senaryolar rehberi yok")
        item.tap()
        XCTAssertTrue(app.staticTexts["Anlık durum"].waitForExistence(timeout: 5),
                      "Rehber sheet'i açılmadı")
    }

    func testScenarioGuideOpensFromHeaderMenuAndCloses() {
        let app = launchFixture()
        app.waitForDashboard()

        openScenarioGuideFromMenu(app)
        XCTAssertTrue(app.navigationBars["Senaryolar"].exists)
        XCTAssertTrue(app.element(labelled: "Kurulum").exists, "Kurulum bölümü yok")

        let close = app.buttons["guide.close"]
        XCTAssertTrue(close.exists)
        close.tap()

        XCTAssertFalse(app.staticTexts["Anlık durum"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["TRUMORE"].exists)
    }

    func testScenarioGuideShowsLiveStatusBadges() {
        let app = launchFixture()
        app.waitForDashboard()
        openScenarioGuideFromMenu(app)

        XCTAssertTrue(app.element(labelled: "Anlık durum").exists)
        // Canlı durum şeridi en az bir rozet içerir ("Başlık: değer" biçiminde).
        let badges = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", ": "))
            .count
        XCTAssertGreaterThan(badges, 0, "Canlı durum rozeti yok")
    }

    func testProximityCardBookOpensGuideAtProximitySection() {
        let app = launchFixture()
        app.waitForDashboard()

        let book = app.buttons["proximity.scenarios"]
        XCTAssertTrue(book.scrollIntoView(app), "Yakınlık senaryoları düğmesi bulunamadı")
        book.tap()
        XCTAssertTrue(app.staticTexts["Anlık durum"].waitForExistence(timeout: 5))

        let heading = app.element(labelled: "Yakınlık Otomasyonu")
        if !heading.waitForExistence(timeout: 3) { app.swipeUp() }
        XCTAssertTrue(heading.waitForExistence(timeout: 3),
                      "Rehber yakınlık bölümüne odaklanmadı")
        XCTAssertTrue(app.element(labelBeginningWith: "Önce kalibrasyon").exists)
    }

    func testProximityCalibrationSheetOpensAndCloses() {
        let app = launchFixture()
        app.waitForDashboard()

        let calibration = app.buttons["proximity.calibration"]
        XCTAssertTrue(calibration.scrollIntoView(app), "Kalibrasyon düğmesi bulunamadı")
        calibration.tap()

        XCTAssertTrue(app.staticTexts["Canlı sinyal"].waitForExistence(timeout: 5),
                      "Kalibrasyon sheet'i açılmadı")
        XCTAssertTrue(app.navigationBars["Yakınlık Kalibrasyonu"].exists)

        let done = app.buttons["Bitti"]
        XCTAssertTrue(done.exists)
        done.tap()
        XCTAssertFalse(app.staticTexts["Canlı sinyal"].waitForExistence(timeout: 2))
    }
}
