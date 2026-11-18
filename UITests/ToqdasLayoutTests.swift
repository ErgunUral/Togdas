// Pano iskeleti: durum → öncelik → hızlı kontroller sırası, "Tüm kontroller"
// derinliği ve şarj hesaplayıcı. Yoğunluk tercihi `-uiTestResetLook` ile her
// testte sıfırlanır; test sonunda Rahat'a dönülür.

import XCTest

final class ToqdasLayoutTests: ToqdasUITestCase {
    /// Yoğunluk seçer ve test bitiminde Rahat'a döner (hata olsa bile).
    private func selectDensity(_ title: String, app: XCUIApplication,
                               dashboard: DashboardScreen) {
        dashboard.openMenu().selectLayout(title)
        addTeardownBlock {
            guard app.state == .runningForeground else { return }
            DashboardScreen(app: app).openMenu().selectLayout("Rahat")
        }
    }

    /// Ana ekran sırası: hızlı kontroller, "Tüm kontroller" düğmesinden önce.
    /// (Ayrıntılı kartlar derinlikte; ilk ekran beş blokla sınırlı.)
    func testVehicleScreenPlacesQuickActionsAboveAllControls() {
        let app = launchFixture(["-uiTestResetLook"])
        let dashboard = DashboardScreen(app: app)
        dashboard.waitForLoad()

        selectDensity("Rahat", app: app, dashboard: dashboard)

        let quickActions = app.staticTexts["Hızlı kontroller"]
        XCTAssertTrue(quickActions.waitForExistence(timeout: 5), "Hızlı kontroller yok")

        let controls = dashboard.allControls
        XCTAssertTrue(controls.waitForExistence(timeout: 5), "Tüm kontroller düğmesi yok")
        if !controls.isHittable { controls.scrollIntoView(app) }
        XCTAssertLessThan(quickActions.frame.minY, controls.frame.minY,
                          "Hızlı kontroller 'Tüm kontroller'den önce gelmeli")
    }

    /// Derinlik gerçekten açılıp kapanıyor: cam/güvenlik ve yakınlık kartları
    /// yalnız "Tüm kontroller" açıkken görünür.
    func testAllControlsRevealsSecurityAndProximitySections() {
        let app = launchFixture(["-uiTestResetLook"])
        let dashboard = DashboardScreen(app: app)
        dashboard.waitForLoad()

        XCTAssertTrue(dashboard.openAllControls(), "Tüm kontroller açılmadı")
        XCTAssertTrue(app.staticTexts["Cam ve Güvenlik"].scrollIntoView(app),
                      "Cam ve güvenlik bölümü derinlikte yok")
        XCTAssertTrue(dashboard.proximityScenarios.scrollIntoView(app),
                      "Yakınlık kartı derinlikte yok")

        dashboard.allControls.scrollIntoView(app)
        dashboard.allControls.tap()
        XCTAssertTrue(dashboard.proximityScenarios.waitForNonExistence(timeout: 3),
                      "Tüm kontroller kapanınca kartlar gizlenmedi")
    }

    func testChargingCalculatorUpdatesEnergyAndCost() {
        // `-scrollChargingCalculator` hesaplayıcıyı ekranın üstüne kaydırır;
        // böylece test kaydırma hareketleriyle kaydırıcılara dokunmaz.
        let app = launchFixture(["-openChargingTab", "-scrollChargingCalculator"])
        let dashboard = DashboardScreen(app: app)
        dashboard.waitForLoad()

        let target = app.sliders["calculator.targetPercent"]
        XCTAssertTrue(target.waitForExistence(timeout: 5), "Hedef doluluk kaydırıcısı yok")
        XCTAssertTrue(waitForHittable(target), "Hedef doluluk kaydırıcısına ulaşılamadı")

        let energy = app.staticTexts["calculator.energy"]
        let cost = app.staticTexts["calculator.cost"]
        XCTAssertTrue(energy.waitForExistence(timeout: 5), "Tahmini enerji yok")
        XCTAssertTrue(cost.exists, "Tahmini ücret yok")

        // Varsayılanlar (başlangıç %20, hedef %80) sıfırdan farklı bir tahmin üretmeli.
        let initialEnergy = energy.label
        XCTAssertNotEqual(initialEnergy, "0 kWh", "Varsayılan tahmin sıfır olmamalı")

        // Önce düşük bir hedefe çek, sonra %100'e çıkar.
        target.adjust(toNormalizedSliderPosition: 0.2)
        XCTAssertTrue(waitForLabelChange(energy, from: initialEnergy),
                      "Hedef doluluk değişince tahmini enerji değişmedi")
        let lowEnergy = energy.label
        let lowCost = cost.label

        target.adjust(toNormalizedSliderPosition: 1.0)
        XCTAssertTrue(waitForLabelChange(energy, from: lowEnergy),
                      "Hedef %100 olunca tahmini enerji değişmedi")
        XCTAssertTrue(waitForLabelChange(cost, from: lowCost),
                      "Hedef %100 olunca tahmini ücret değişmedi")
        if let low = kilowattHours(lowEnergy), let high = kilowattHours(energy.label) {
            XCTAssertGreaterThan(high, low, "Enerji hedefle birlikte artmalı")
        } else {
            XCTFail("Enerji değeri çözümlenemedi: \(lowEnergy) / \(energy.label)")
        }
    }

    func testChargingCalculatorStatesAssumptionsWithoutStartingCharge() {
        let app = launchFixture(["-openChargingTab", "-scrollChargingCalculator"])
        let dashboard = DashboardScreen(app: app)
        dashboard.waitForLoad()

        XCTAssertTrue(app.staticTexts["Şarj Hesaplama"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Kapasite ve fiyat varsayımdır"].exists)

        let note = app.staticTexts[
            "Kapasite ve fiyat varsayımdır; şarj kayıpları hesaba katılmaz. Araçta şarj başlatmaz."
        ]
        XCTAssertTrue(note.waitForExistence(timeout: 5), "Varsayım/şarj başlatmama notu yok")
    }

    private func waitForLabelChange(_ element: XCUIElement, from old: String,
                                    timeout: TimeInterval = 3) -> Bool {
        let predicate = NSPredicate(format: "label != %@", old)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForHittable(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "isHittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// "70,8 kWh" → 70.8
    private func kilowattHours(_ label: String) -> Double? {
        Double(label.replacingOccurrences(of: "kWh", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: "."))
    }
}
