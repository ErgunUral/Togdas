// Pano düzeni varyantları (Sportif/Teknik) ve şarj hesaplayıcı.
// Düzen seçimi `-uiTestResetLook` ile her testte sıfırlanır; test sonunda
// varsayılana dönülür ki sonraki sınıflar etkilenmesin.

import XCTest

final class ToqdasLayoutTests: ToqdasUITestCase {
    /// Düzeni seçer ve test bitiminde Klasik'e döner (hata olsa bile).
    private func selectLayout(_ title: String, app: XCUIApplication,
                              dashboard: DashboardScreen) {
        dashboard.openMenu().selectLayout(title)
        addTeardownBlock {
            guard app.state == .runningForeground else { return }
            DashboardScreen(app: app).openMenu().selectLayout("Klasik · Tüm kartlar")
        }
    }

    func testSportLayoutPlacesQuickActionsAboveBLECard() {
        let app = launchFixture(["-uiTestResetLook"])
        let dashboard = DashboardScreen(app: app)
        dashboard.waitForLoad()

        selectLayout("Sportif · Kontroller önde", app: app, dashboard: dashboard)

        let quickActions = app.staticTexts["Hızlı Araç Kontrolleri"]
        XCTAssertTrue(quickActions.waitForExistence(timeout: 5), "Hızlı kontroller yok")
        let bleCard = app.staticTexts["Bluetooth Dijital Anahtar"]
        XCTAssertTrue(bleCard.waitForExistence(timeout: 5), "BLE kartı yok")
        XCTAssertLessThan(quickActions.frame.minY, bleCard.frame.minY,
                          "Sportif düzende hızlı kontroller BLE kartından önce gelmeli")

        // Sportif düzen cam/güvenlik bölümünü gizlemez.
        XCTAssertTrue(app.staticTexts["Cam ve Güvenlik"].scrollIntoView(app),
                      "Cam ve güvenlik bölümü sportif düzende yok")
    }

    func testTechnicalLayoutShowsDiagnosticsAboveProximityCard() {
        let app = launchFixture(["-uiTestResetLook"])
        let dashboard = DashboardScreen(app: app)
        dashboard.waitForLoad()

        selectLayout("Teknik · Tanı ve telemetri önde", app: app, dashboard: dashboard)

        let diagnostics = app.staticTexts["Canlı BLE Tanısı"]
        XCTAssertTrue(diagnostics.scrollIntoView(app), "Tanı bloğu görünmedi")

        let proximity = app.buttons["proximity.scenarios"]
        XCTAssertTrue(proximity.scrollIntoView(app), "Yakınlık kartı yok")
        XCTAssertTrue(diagnostics.exists, "Tanı bloğu kaydırma sonrası kayboldu")
        XCTAssertLessThan(diagnostics.frame.minY, proximity.frame.minY,
                          "Teknik düzende tanı bloğu yakınlık kartından önce gelmeli")
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
