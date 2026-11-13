import XCTest
@testable import ToqdasCore

/// `WatchComplicationStore`: complication veri köprüsü (app group
/// JSON deposu). Invariant: yalnız gösterim verisi; anahtar/token yok.
final class WatchComplicationStoreTests: XCTestCase {
    override func setUp() {
        super.setUp()
        WatchComplicationStore.clear()
    }

    func testSaveAndLoadRoundTrip() {
        // Sözleşme: aynı Data gelir, aynı Data döner. Kodlama/çözme
        // WatchSnapshot tarafındadır (Shared); depo içeriği yorumlamaz.
        let payload = Data("{\"vin\":\"TEST\"}".utf8)
        WatchComplicationStore.saveSnapshotData(payload)
        XCTAssertEqual(WatchComplicationStore.snapshotData(), payload)
    }

    func testMissingSnapshotIsNil() {
        XCTAssertNil(WatchComplicationStore.snapshotData())
    }

    func testOverwriteKeepsLatest() {
        WatchComplicationStore.saveSnapshotData(Data("birinci".utf8))
        WatchComplicationStore.saveSnapshotData(Data("ikinci".utf8))
        XCTAssertEqual(WatchComplicationStore.snapshotData(), Data("ikinci".utf8))
    }

    func testClearRemovesSnapshot() {
        WatchComplicationStore.saveSnapshotData(Data("veri".utf8))
        WatchComplicationStore.clear()
        XCTAssertNil(WatchComplicationStore.snapshotData())
    }

    func testKeyFormatStable() {
        // Widget extension aynı anahtarla okur; biçim değişirse eski
        // complication verisi kaybolur.
        XCTAssertEqual(WatchComplicationStore.snapshotKey, "toqdas.watch.complication.snapshot.v1")
        XCTAssertEqual(WatchComplicationStore.appGroup, "group.com.toqdas.ios")
    }

    // MARK: - VIN'siz kopya (complication köprüsü invariant'ı)

    func testComplicationCopyIsVinLess() {
        // İlke: iPhone widget deposuyla aynı — complication verisinde
        // VIN taşınmaz; gösterim alanları eksiksiz korunur.
        let snapshot = WatchSnapshot(vin: "NL1CSU0P60G064536", vehicleName: "FFR T10X",
                                     locked: true, doorCount: 4, openDoors: 0,
                                     trunkAjar: false, powerState: 1, ready: true,
                                     bleState: "Komut hazır", updatedAt: 123.0,
                                     telemetryAge: 12.0, batteryPercent: 86.0,
                                     rangeKM: 359.3, outsideTemperatureC: 13.5,
                                     auxiliaryBatteryPercent: 71.0, odometerKM: 26_279.5,
                                     chargingState: "CHRGMODE_STANDBY",
                                     proximityEnabled: true, recovering: false,
                                     lastCommandText: "Kilitleme · 19:37")
        let copy = snapshot.complicationCopy
        XCTAssertEqual(copy.vin, "")
        XCTAssertEqual(copy.vehicleName, snapshot.vehicleName)
        XCTAssertEqual(copy.locked, snapshot.locked)
        XCTAssertEqual(copy.doorCount, snapshot.doorCount)
        XCTAssertEqual(copy.openDoors, snapshot.openDoors)
        XCTAssertEqual(copy.trunkAjar, snapshot.trunkAjar)
        XCTAssertEqual(copy.powerState, snapshot.powerState)
        XCTAssertEqual(copy.ready, snapshot.ready)
        XCTAssertEqual(copy.bleState, snapshot.bleState)
        XCTAssertEqual(copy.updatedAt, snapshot.updatedAt)
        XCTAssertEqual(copy.telemetryAge, snapshot.telemetryAge)
        XCTAssertEqual(copy.batteryPercent, snapshot.batteryPercent)
        XCTAssertEqual(copy.rangeKM, snapshot.rangeKM)
        XCTAssertEqual(copy.outsideTemperatureC, snapshot.outsideTemperatureC)
        XCTAssertEqual(copy.auxiliaryBatteryPercent, snapshot.auxiliaryBatteryPercent)
        XCTAssertEqual(copy.odometerKM, snapshot.odometerKM)
        XCTAssertEqual(copy.chargingState, snapshot.chargingState)
        XCTAssertEqual(copy.proximityEnabled, snapshot.proximityEnabled)
        XCTAssertEqual(copy.recovering, snapshot.recovering)
        XCTAssertEqual(copy.lastCommandText, snapshot.lastCommandText)
    }

    func testComplicationCopyRoundTripsThroughDecode() {
        // Widget extension VIN anahtarını bekler; boş string ile çözülür.
        let snapshot = WatchSnapshot(vin: "TESTVIN0000000009", vehicleName: "X",
                                     locked: nil, doorCount: 2, openDoors: 0,
                                     trunkAjar: nil, powerState: nil, ready: false,
                                     bleState: "", updatedAt: 0, telemetryAge: nil,
                                     batteryPercent: nil, rangeKM: nil,
                                     outsideTemperatureC: nil)
        let data = try? JSONEncoder().encode(snapshot.complicationCopy)
        XCTAssertNotNil(data)
        let decoded = data.flatMap { try? JSONDecoder().decode(WatchSnapshot.self, from: $0) }
        XCTAssertEqual(decoded?.vin, "")
        XCTAssertEqual(decoded?.vehicleName, "X")
        XCTAssertEqual(decoded?.locked, nil)
        // Kaynak snapshot gerçek VIN'i korur (saat komut isteği için).
        XCTAssertEqual(snapshot.vin, "TESTVIN0000000009")
    }
}
