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
}
