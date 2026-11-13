// UI testleri için ortak altyapı.
// Kural: sabit `sleep` yok — yalnızca koşula bağlı bekleme ve kaydırma.
// `-uiTestSignedOut` her açılışta oturumu kapatır; `-uiTestFixture` panoyu
// uçtan uca ağ/BLE kurulumu olmadan yerel fixture verisiyle açar.

import XCTest

class ToqdasUITestCase: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Oturum kapalı başlatır; ek argümanlar sırayla eklenir.
    func launch(_ arguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestSignedOut"] + arguments
        app.launch()
        return app
    }

    /// Yerel fixture verisiyle pano.
    func launchFixture(_ arguments: [String] = []) -> XCUIApplication {
        launch(["-uiTestFixture"] + arguments)
    }
}

extension XCUIApplication {
    /// Erişilebilirlik kimliğiyle ilk öğe (türden bağımsız).
    func element(identifiedBy identifier: String) -> XCUIElement {
        descendants(matching: .any)[identifier]
    }

    /// Verilen erişilebilirlik etiketine sahip ilk öğe (türden bağımsız).
    func element(labelled label: String) -> XCUIElement {
        descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", label))
            .firstMatch
    }

    /// Etiketi verilen metinle başlayan ilk öğe.
    func element(labelBeginningWith prefix: String) -> XCUIElement {
        descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", prefix))
            .firstMatch
    }

    /// Panonun yüklendiğini doğrular (başlık "TRUMORE" görünür).
    func waitForDashboard(timeout: TimeInterval = 10) {
        XCTAssertTrue(staticTexts["TRUMORE"].waitForExistence(timeout: timeout),
                      "Pano başlığı görünmedi")
    }
}

extension XCUIElement {
    var textValue: String { (value as? String) ?? "" }

    /// Öğe görünmüyorsa kaydırarak arar; bulunamazsa `false` döner.
    @discardableResult
    func scrollIntoView(_ app: XCUIApplication, maxSwipes: Int = 8) -> Bool {
        if exists { return true }
        for _ in 0..<maxSwipes {
            app.swipeUp()
            if waitForExistence(timeout: 1) { return true }
        }
        return exists
    }
}
