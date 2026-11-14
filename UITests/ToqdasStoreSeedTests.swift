// Bütçe ve bakım kartları: boş/dolu durumlar.
// `-uiTestSeedStores` her açılışta store'ları temizleyip sabit değerler yazar
// (limit 5.000 ₺, harcama 4.250 ₺; bakım 1.500 km ve 900 km).
// `-uiTestResetStores` yalnız temizler (boş durum testi).

import XCTest

final class ToqdasStoreSeedTests: ToqdasUITestCase {
    func testChargingBudgetCardShowsEmptyState() {
        let app = launchFixture(["-uiTestResetStores"])
        app.waitForDashboard()

        XCTAssertTrue(app.staticTexts["Şarj Bütçesi"].waitForExistence(timeout: 5),
                      "Şarj bütçesi kartı yok")
        XCTAssertTrue(app.staticTexts["Kapalı"].exists,
                      "Limit belirlenmemişken 'Kapalı' görünmeli")
        XCTAssertTrue(app.staticTexts[
            "Bu ay harcama verisi yok. Seyahatname → Şarj → Bu ay görünümü açıldığında sunucudan gelen gerçek tutar buraya işlenir."
        ].exists, "Boş harcama açıklaması yok")
    }

    func testChargingBudgetCardShowsSeededSpend() {
        let app = launchFixture(["-uiTestSeedStores"])
        app.waitForDashboard()

        XCTAssertTrue(app.staticTexts["Şarj Bütçesi"].waitForExistence(timeout: 5),
                      "Şarj bütçesi kartı yok")
        XCTAssertTrue(app.staticTexts["4.250 ₺"].exists, "Harcama tutarı görünmüyor")
        XCTAssertTrue(app.staticTexts["/ 5.000 ₺"].exists, "Limit görünmüyor")
        XCTAssertTrue(app.staticTexts["85%"].exists, "Kullanım yüzdesi görünmüyor")
        XCTAssertTrue(app.staticTexts["Bütçenin 85%'i kullanıldı; 750 ₺ kaldı."].exists,
                      "Kalan bütçe mesajı yok")
    }

    func testMaintenanceCardShowsApproachingItem() {
        let app = launchFixture(["-uiTestSeedStores"])
        app.waitForDashboard()

        XCTAssertTrue(app.staticTexts["Bakım Hatırlatıcıları"].waitForExistence(timeout: 5),
                      "Bakım kartı yok")
        XCTAssertTrue(app.staticTexts["Lastik rotasyonu"].exists, "Yaklaşan bakım kalemi yok")
        XCTAssertTrue(app.staticTexts["Bakım: 1500 km · 266 km kaldı"].exists,
                      "Kalan km metni beklenen değerde değil")
    }

    func testMaintenanceCardShowsOverdueItem() {
        let app = launchFixture(["-uiTestSeedStores"])
        app.waitForDashboard()

        XCTAssertTrue(app.staticTexts["Bakım Hatırlatıcıları"].waitForExistence(timeout: 5),
                      "Bakım kartı yok")
        XCTAssertTrue(app.staticTexts["Fren bakımı"].exists, "Gecikmiş bakım kalemi yok")
        XCTAssertTrue(app.staticTexts["Gecikti · 335 km geçti"].exists,
                      "Gecikme metni beklenen değerde değil")
    }
}
