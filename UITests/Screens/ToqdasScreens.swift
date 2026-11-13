// Ekran nesneleri (Page Object Model): seçiciler tek yerde, testler yalnızca
// davranış ve iddia taşır. Ekranlar assertion içermez; iddialar testte kalır.
// Kural: sabit `sleep` yok — koşula bağlı bekleme ve kaydırma kullanılır.

import XCTest

// MARK: - Pano

struct DashboardScreen {
    let app: XCUIApplication

    static let tabs = ["Genel Bakış", "İklimlendirme", "Trugo Şarj", "Araç Durumu"]

    var title: XCUIElement { app.staticTexts["TRUMORE"] }
    var menuButton: XCUIElement { app.element(identifiedBy: "header.menu") }

    var vehicleName: XCUIElement { app.staticTexts["UI Test Aracı • UI 0001"] }
    var batteryPercent: XCUIElement { app.staticTexts["%79"] }
    var range: XCUIElement { app.staticTexts["365"] }
    var healthHeading: XCUIElement { app.staticTexts["Araç Sağlığı & Lastik Basınçları"] }

    var proximityScenarios: XCUIElement { app.buttons["proximity.scenarios"] }
    var proximityCalibration: XCUIElement { app.buttons["proximity.calibration"] }
    var voiceAssistant: XCUIElement { app.buttons["Sesli komut"] }
    var bleSetupGuide: XCUIElement { app.buttons["Kurulumu adım adım dinle"] }
    var keyDiscovery: XCUIElement { app.buttons["Cihaz ortamında aday seç"] }

    func tab(_ title: String) -> XCUIElement { app.buttons["\(title) sekmesi"] }

    func waitForLoad(timeout: TimeInterval = 10) {
        XCTAssertTrue(title.waitForExistence(timeout: timeout), "Pano başlığı görünmedi")
    }

    func selectTab(_ title: String) {
        tab(title).tap()
    }

    @discardableResult
    func openMenu() -> MenuSheet {
        menuButton.tap()
        return MenuSheet(app: app)
    }
}

// MARK: - Başlık menüsü

struct MenuSheet {
    let app: XCUIApplication

    enum Item: String {
        case vehicleDetail = "Araç detayı"
        case scenarioGuide = "Senaryolar rehberi"
        case serviceCard = "Servis kartı"
        case driveExperience = "Seyahatname"
        case accountCenter = "Bildirimler & destek"
        case bluetoothCommands = "Bluetooth komutları"
        case bluetoothScan = "Bluetooth taraması"
        case logout = "Çıkış yap"
    }

    static let themeTitles = ["Togg Gece", "Okyanus", "Grafit / Amber"]
    static let layoutTitles = [
        "Klasik · Tüm kartlar",
        "Minimal · Özet ve hızlı erişim",
        "Sportif · Kontroller önde",
        "Teknik · Tanı ve telemetri önde"
    ]

    func item(_ item: Item) -> XCUIElement { app.buttons[item.rawValue] }
    func theme(_ title: String) -> XCUIElement { app.buttons[title] }
    func layout(_ title: String) -> XCUIElement { app.buttons[title] }

    func tap(_ item: Item) {
        tap(app.buttons[item.rawValue])
    }

    func selectTheme(_ title: String) {
        tap(theme(title))
    }

    func selectLayout(_ title: String) {
        tap(layout(title))
    }

    @discardableResult
    func openScenarioGuide() -> ScenarioGuideSheet {
        tap(.scenarioGuide)
        let guide = ScenarioGuideSheet(app: app)
        guide.waitForOpen()
        return guide
    }

    @discardableResult
    func openCommands() -> CommandSheet {
        tap(.bluetoothCommands)
        let commands = CommandSheet(app: app)
        commands.waitForOpen()
        return commands
    }

    /// Menü uzun: ekran dışındaki öğeyi kaydırarak seçer.
    private func tap(_ element: XCUIElement) {
        if !element.waitForExistence(timeout: 3) {
            app.swipeUp()
        }
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Menü öğesi görünmedi")
        if !element.isHittable {
            app.swipeUp()
        }
        element.tap()
    }
}

// MARK: - Komut sheet'i

struct CommandSheet {
    let app: XCUIApplication

    static let identifiers = [
        "commands.unlock",
        "commands.lock",
        "commands.trunkOpen",
        "commands.trunkClose",
        "commands.driveAuthorize"
    ]

    var navigationBar: XCUIElement { app.navigationBars["Araç komutları"] }
    var gateMessage: XCUIElement { app.staticTexts["commands.gateMessage"] }
    var unlock: XCUIElement { button("commands.unlock") }
    var lock: XCUIElement { button("commands.lock") }
    var closeButton: XCUIElement { app.buttons["Kapat"].firstMatch }

    func button(_ identifier: String) -> XCUIElement { app.buttons[identifier] }

    func waitForOpen(timeout: TimeInterval = 10) {
        XCTAssertTrue(navigationBar.waitForExistence(timeout: timeout),
                      "Komut sheet'i açılmadı")
    }
}

// MARK: - Senaryolar rehberi

struct ScenarioGuideSheet {
    let app: XCUIApplication

    var navigationBar: XCUIElement { app.navigationBars["Senaryolar"] }
    var liveStatus: XCUIElement { app.staticTexts["Anlık durum"] }
    var closeButton: XCUIElement { app.buttons["guide.close"] }

    func section(_ title: String) -> XCUIElement { app.element(labelled: title) }

    func waitForOpen(timeout: TimeInterval = 5) {
        XCTAssertTrue(liveStatus.waitForExistence(timeout: timeout),
                      "Rehber sheet'i açılmadı")
    }
}

// MARK: - Yakınlık kalibrasyonu

struct CalibrationSheet {
    let app: XCUIApplication

    var navigationBar: XCUIElement { app.navigationBars["Yakınlık Kalibrasyonu"] }
    var liveSignal: XCUIElement { app.staticTexts["Canlı sinyal"] }
    var doneButton: XCUIElement { app.buttons["Bitti"] }
}

// MARK: - Giriş

struct LoginScreen {
    let app: XCUIApplication

    var title: XCUIElement { app.staticTexts["TRUMORE"] }
    var toggButton: XCUIElement { app.buttons["login.toggButton"] }
    var signInCopy: XCUIElement { app.staticTexts["Togg ID ile giriş yap"] }
    var subtitle: XCUIElement { app.staticTexts["Togg dijital anahtar ve araç kontrolü"] }
}
