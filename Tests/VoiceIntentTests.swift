import XCTest
@testable import ToqdasCore

final class VoiceIntentTests: XCTestCase {
    private let parser = VoiceIntentParser()

    func testBatteryAndRangeQueries() {
        XCTAssertEqual(parser.parse("Şarjım ne kadar?"), .batteryStatus)
        XCTAssertEqual(parser.parse("Batarya yüzde kaç?"), .batteryStatus)
        XCTAssertEqual(parser.parse("Menzil kaç km?"), .rangeStatus)
        XCTAssertEqual(parser.parse("Kaç kilometre giderim?"), .rangeStatus)
    }

    func testLockStatusAndActions() {
        XCTAssertEqual(parser.parse("Kapılar kilitli mi?"), .lockStatus)
        XCTAssertEqual(parser.parse("Kilit açık mı?"), .lockStatus)
        XCTAssertEqual(parser.parse("Kilitleri aç"), .unlock)
        XCTAssertEqual(parser.parse("Kapıyı kilitle"), .lock)
        XCTAssertEqual(parser.parse("Kapıları kapat"), .lock)
    }

    func testTrunkAndWindowActionsAndStatus() {
        XCTAssertEqual(parser.parse("Bagajı aç"), .trunkOpen)
        XCTAssertEqual(parser.parse("Bagajı kapat"), .trunkClose)
        XCTAssertEqual(parser.parse("Bagaj açık mı?"), .trunkStatus)
        XCTAssertEqual(parser.parse("Camları kapat"), .windowsClose)
        XCTAssertEqual(parser.parse("Camlar açık mı?"), .windowsStatus)
    }

    func testClimateActionsWithTemperature() {
        XCTAssertEqual(parser.parse("Klimayı 22 derece yap"), .climateOn(temperature: 22))
        XCTAssertEqual(parser.parse("Klimayı aç"), .climateOn(temperature: nil))
        XCTAssertEqual(parser.parse("Klima kapat"), .climateOff)
    }

    func testReadOnlyVehicleData() {
        XCTAssertEqual(parser.parse("Dış sıcaklık kaç derece?"), .outsideTemperatureStatus)
        XCTAssertEqual(parser.parse("Lastik basınçları?"), .tirePressureStatus)
        XCTAssertEqual(parser.parse("Lastiğin basıncı ne?"), .tirePressureStatus)
        XCTAssertEqual(parser.parse("12 V akü ne durumda?"), .auxiliaryBatteryStatus)
        XCTAssertEqual(parser.parse("Odometre kaç?"), .odometerStatus)
        XCTAssertEqual(parser.parse("Şarj oluyor mu?"), .chargingStatus)
        XCTAssertEqual(parser.parse("Şarzım ne kadar?"), .batteryStatus)
        XCTAssertEqual(parser.parse("Şarz oluyor mu?"), .chargingStatus)
        XCTAssertEqual(parser.parse("Şarz kapağını aç"), .unknown)
    }

    func testFindVehicleAndHelp() {
        XCTAssertEqual(parser.parse("Aracı bul"), .findVehicle)
        XCTAssertEqual(parser.parse("Farları yak"), .findVehicle)
        XCTAssertEqual(parser.parse("Yardım"), .help)
        XCTAssertEqual(parser.parse("Neler yapabilirsin?"), .help)
    }

    func testNegativePhrasesAreRejected() {
        XCTAssertEqual(parser.parse("Kapıyı açma"), .unknown)
        XCTAssertEqual(parser.parse("Camları kapatma"), .unknown)
        XCTAssertEqual(parser.parse("Bagajı açma sakın"), .unknown)
    }

    func testAmbiguousOrUnsupportedPhrasesAreUnknown() {
        XCTAssertEqual(parser.parse("Şarj kapağını aç"), .unknown)
        XCTAssertEqual(parser.parse("Bugün hava nasıl?"), .unknown)
        XCTAssertEqual(parser.parse(""), .unknown)
        XCTAssertEqual(parser.parse("Farları kapat"), .unknown)
    }

    func testNormalizationHandlesTurkishCharactersAndPunctuation() {
        XCTAssertEqual(VoiceIntentParser.normalize("  Kapıları AÇ!  "), "kapilari ac")
        XCTAssertEqual(parser.parse("KİLİTLERİ AÇ"), .unlock)
    }

    func testRiskClassification() {
        XCTAssertTrue(VoiceIntent.unlock.isAction)
        XCTAssertTrue(VoiceIntent.unlock.requiresDeviceUnlock)
        XCTAssertTrue(VoiceIntent.trunkOpen.isAction)
        XCTAssertFalse(VoiceIntent.batteryStatus.isAction)
        XCTAssertFalse(VoiceIntent.lock.requiresDeviceUnlock)
    }
}
