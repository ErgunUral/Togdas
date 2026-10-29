import XCTest
@testable import ToqdasCore

final class VoiceCommandParserTests: XCTestCase {
    private let parser = VoiceCommandParser()

    // MARK: Salt okunur

    func testBatteryAndRange() {
        XCTAssertEqual(parser.parse("Şarjım ne kadar?"), .status(.battery))
        XCTAssertEqual(parser.parse("Batarya yüzde kaç?"), .status(.battery))
        XCTAssertEqual(parser.parse("Pil yüzde kaç?"), .status(.battery))
        XCTAssertEqual(parser.parse("Menzil kaç km?"), .status(.range))
        XCTAssertEqual(parser.parse("Kaç kilometre giderim?"), .status(.range))
    }

    func testLockStatus() {
        XCTAssertEqual(parser.parse("Kapılar kilitli mi?"), .status(.locks))
        XCTAssertEqual(parser.parse("Kilit açık mı?"), .status(.locks))
        XCTAssertEqual(parser.parse("Kapılar açık"), .status(.locks))
    }

    func testTrunkAndWindowStatus() {
        XCTAssertEqual(parser.parse("Bagaj açık mı?"), .status(.trunk))
        XCTAssertEqual(parser.parse("Bagaj kapalı mı?"), .status(.trunk))
        XCTAssertEqual(parser.parse("Camlar açık mı?"), .status(.windows))
        XCTAssertEqual(parser.parse("Cam kapalı mı?"), .status(.windows))
    }

    func testChargingClimateAndHealthStatus() {
        XCTAssertEqual(parser.parse("Şarjda mı?"), .status(.charging))
        XCTAssertEqual(parser.parse("Şarj oluyor mu?"), .status(.charging))
        XCTAssertEqual(parser.parse("Şarz oluyor mu?"), .status(.charging))
        XCTAssertEqual(parser.parse("Klima açık mı?"), .status(.climate))
        XCTAssertEqual(parser.parse("Lastik basınçları?"), .status(.tirePressure))
        XCTAssertEqual(parser.parse("Lastiğin basıncı ne?"), .status(.tirePressure))
        XCTAssertEqual(parser.parse("Dış sıcaklık kaç derece?"), .status(.outsideTemperature))
        XCTAssertEqual(parser.parse("Hava kaç derece?"), .status(.outsideTemperature))
        XCTAssertEqual(parser.parse("Toplam kilometre?"), .status(.odometer))
        XCTAssertEqual(parser.parse("Odometre kaç?"), .status(.odometer))
        XCTAssertEqual(parser.parse("12 V akü?"), .status(.auxiliaryBattery))
        XCTAssertEqual(parser.parse("12 V akü ne durumda?"), .status(.auxiliaryBattery))
    }

    // MARK: Eylemler

    func testLockActions() {
        XCTAssertEqual(parser.parse("Kilitleri aç"), .unlock)
        XCTAssertEqual(parser.parse("Kapıları aç"), .unlock)
        XCTAssertEqual(parser.parse("Kapıyı kilitle"), .lock)
        XCTAssertEqual(parser.parse("Kapıları kapat"), .lock)
        XCTAssertEqual(parser.parse("Kilitleri kapat"), .lock)
        XCTAssertEqual(parser.parse("Kilitle"), .lock)
        XCTAssertEqual(parser.parse("KAPILARI AÇ!"), .unlock)
    }

    func testTrunkAndWindowActions() {
        XCTAssertEqual(parser.parse("Bagajı aç"), .trunk(open: true))
        XCTAssertEqual(parser.parse("Bagajı kapat"), .trunk(open: false))
        XCTAssertEqual(parser.parse("Bagajı açmak istiyorum"), .trunk(open: true))
        XCTAssertEqual(parser.parse("Camları aç"), .windows(open: true))
        XCTAssertEqual(parser.parse("Camları kapat"), .windows(open: false))
        XCTAssertEqual(parser.parse("Camı kapat"), .windows(open: false))
    }

    func testClimateActions() {
        XCTAssertEqual(parser.parse("Klimayı aç"), .climate(on: true, temperature: nil))
        XCTAssertEqual(parser.parse("Klimayı kapat"), .climate(on: false, temperature: nil))
        XCTAssertEqual(parser.parse("Klimayı 22 derece yap"), .climate(on: true, temperature: 22))
        XCTAssertEqual(parser.parse("Klimayı 22 dereceye ayarla"), .climate(on: true, temperature: 22))
        XCTAssertEqual(parser.parse("Klima 22 derece"), .climate(on: true, temperature: 22))
    }

    func testSpecialCommands() {
        XCTAssertEqual(parser.parse("Aracı bul"), .findVehicle)
        XCTAssertEqual(parser.parse("Araç nerede?"), .findVehicle)
        XCTAssertEqual(parser.parse("Farları aç"), .findVehicle)
        XCTAssertEqual(parser.parse("Yardım"), .help)
        XCTAssertEqual(parser.parse("Neler yapabilirsin?"), .help)
        XCTAssertEqual(parser.parse("İptal"), .cancel)
        XCTAssertEqual(parser.parse("Vazgeç"), .cancel)
    }

    func testShortConfirmationsAreNotCommands() {
        XCTAssertEqual(parser.parse("Evet"), .affirm)
        XCTAssertEqual(parser.parse("Tamam"), .affirm)
        XCTAssertEqual(parser.parse("Peki"), .affirm)
        XCTAssertEqual(parser.parse("Evet tamam"), .affirm)
        XCTAssertEqual(parser.parse("Hayır"), .deny)
        XCTAssertEqual(parser.parse("Olmaz"), .deny)
    }

    func testFillerDoesNotOverrideCommand() {
        XCTAssertEqual(parser.parse("Tamam şarjım ne kadar?"), .status(.battery))
        XCTAssertEqual(parser.parse("Peki kapılar kilitli mi?"), .status(.locks))
    }

    // MARK: Belirsizlik ve güvenlik

    func testAmbiguousCommands() {
        XCTAssertEqual(parser.parse("Kilit"), .ambiguous)
        XCTAssertEqual(parser.parse("Kapı"), .ambiguous)
        XCTAssertEqual(parser.parse("Bagaj"), .ambiguous)
        XCTAssertEqual(parser.parse("Cam"), .ambiguous)
        XCTAssertEqual(parser.parse("Klima"), .ambiguous)
        XCTAssertEqual(parser.parse("Aç"), .ambiguous)
        XCTAssertEqual(parser.parse("Kapat"), .ambiguous)
        XCTAssertEqual(parser.parse("Şarj ve menzil"), .ambiguous)
    }

    func testNegationsAreRejected() {
        XCTAssertEqual(parser.parse("Kapıları açma"), .unknown)
        XCTAssertEqual(parser.parse("Bagajı kapatma"), .unknown)
        XCTAssertEqual(parser.parse("Kilitleri kilitleme"), .unknown)
        XCTAssertEqual(parser.parse("Camları açmayın"), .unknown)
        XCTAssertEqual(parser.parse("Dokunma"), .unknown)
    }

    func testUnsupportedOrUnknown() {
        XCTAssertEqual(parser.parse("Şarj kapısı açık mı?"), .unknown)
        XCTAssertEqual(parser.parse("Şarj istasyonu"), .unknown)
        XCTAssertEqual(parser.parse("İç sıcaklık"), .unknown)
        XCTAssertEqual(parser.parse("Sıcaklığı 22 derece yap"), .unknown)
        XCTAssertEqual(parser.parse(""), .unknown)
    }

    func testConfidenceAndNormalizedText() {
        let result = parser.parseDetailed("KAPILARI AÇ!")
        XCTAssertEqual(result.command, .unlock)
        XCTAssertEqual(result.normalizedText, "kapilari ac")
        XCTAssertGreaterThan(result.confidence, 0.9)

        let unknown = parser.parseDetailed("bilinmeyen bir cümle")
        XCTAssertEqual(unknown.command, .unknown)
        XCTAssertEqual(unknown.confidence, 0)
    }
}
