import XCTest
@testable import ToqdasCore

/// `KeyDiscoverySession`: aday kataloğu, tarama penceresi ve seçim
/// durumunun Android `.57.18` parite testleri.
final class KeyDiscoverySessionTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Istanbul")!
        return calendar
    }
    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: hour, minute: minute))!
    }
    private let vin = "LGWFCFS77RM100185"

    func testObserveMergesAndKeepsStableID() {
        var session = KeyDiscoverySession(vin: vin)
        session.observe(
            identifier: "11111111-1111-1111-1111-111111111111",
            name: "Cihaz-X", rssi: -70,
            advertisesSupportedService: true,
            at: date(10)
        )
        XCTAssertEqual(session.validCount, 1)
        // Aynı tanımlayıcı yeni aday oluşturmaz; bayraklar birikir.
        session.observe(
            identifier: "11111111-1111-1111-1111-111111111111",
            name: "MY T-SAS RM100185", rssi: -68,
            advertisesSupportedService: true,
            at: date(10, 1)
        )
        XCTAssertEqual(session.candidates.count, 1)
        let candidate = session.sortedValidCandidates[0]
        XCTAssertTrue(candidate.nameMatchesVIN)
        XCTAssertTrue(candidate.advertisesSupportedService)
        XCTAssertEqual(candidate.reason, "VIN ile cihaz adı uyumlu; kimlik doğrulama henüz yapılmadı")
        XCTAssertEqual(session.rawSightingCount, 2)
    }

    func testRawAndValidLimitsMatchAndroid() {
        var session = KeyDiscoverySession(vin: vin)
        session.requestScan()
        session.beginScan(at: date(10))
        for index in 0..<(KeyDiscoveryPolicy.maxRawCandidates + 5) {
            session.observe(
                identifier: String(format: "%040d", index),
                name: "Yabancı-\(index)", rssi: -80,
                advertisesSupportedService: false,
                at: date(10)
            )
        }
        XCTAssertEqual(session.candidates.count, KeyDiscoveryPolicy.maxRawCandidates)
        XCTAssertEqual(session.validCount, 0)
        // Reklam gözlendi ama geçerli aday yok: K03 (Android birebir).
        XCTAssertEqual(session.statusCode(now: date(10)), "K03_NO_CANDIDATE")
    }

    func testValidCandidateCap() {
        var session = KeyDiscoverySession(vin: vin)
        for index in 0..<(KeyDiscoveryPolicy.maxValidCandidates + 3) {
            session.observe(
                identifier: String(format: "%040d", index),
                name: "My T-SAS", rssi: -60,
                advertisesSupportedService: false,
                at: date(10)
            )
        }
        XCTAssertEqual(session.validCount, KeyDiscoveryPolicy.maxValidCandidates)
    }

    func testSelectionRequiresFreshScan() {
        var session = KeyDiscoverySession(vin: vin)
        let id = "22222222-2222-2222-2222-222222222222"
        session.observe(identifier: id, name: "My T-SAS", rssi: -55, advertisesSupportedService: false, at: date(10))
        // Tarama hiç koşmadı: seçim reddedilir.
        XCTAssertNil(session.select(id, now: date(10, 5)))

        session.beginScan(at: date(10, 10))
        session.endScan(at: date(10, 10))
        // 120 sn içinde: seçilir.
        let selected = session.select(id, now: date(10, 10).addingTimeInterval(60))
        XCTAssertEqual(selected?.name, "My T-SAS")
    }

    func testSelectionStaleAfterWindow() {
        var session = KeyDiscoverySession(vin: vin)
        let id = "22222222-2222-2222-2222-222222222222"
        session.observe(identifier: id, name: "My T-SAS", rssi: -55, advertisesSupportedService: false, at: date(10))
        session.beginScan(at: date(10))
        session.endScan(at: date(10))
        XCTAssertNil(session.select(id, now: date(10).addingTimeInterval(121)))
        // Tarama etkinken pencere geçermez.
        session.beginScan(at: date(10))
        let selected = session.select(id, now: date(10).addingTimeInterval(121))
        XCTAssertNotNil(selected)
    }

    func testSelectionRejectsInvalidCandidate() {
        var session = KeyDiscoverySession(vin: vin)
        let id = "33333333-3333-3333-3333-333333333333"
        session.observe(identifier: id, name: "JBL Hoparlör", rssi: -60, advertisesSupportedService: false, at: date(10))
        session.beginScan(at: date(10))
        session.endScan(at: date(10))
        XCTAssertNil(session.select(id, now: date(10, 1)))
        XCTAssertNil(session.selectedID)
    }

    func testSortedValidCandidatesOrdersByRSSI() {
        var session = KeyDiscoverySession(vin: vin)
        session.observe(identifier: "a", name: "My T-SAS", rssi: -70, advertisesSupportedService: false, at: date(10))
        session.observe(identifier: "b", name: "My T-SAS", rssi: -55, advertisesSupportedService: false, at: date(10))
        session.observe(identifier: "c", name: "My T-SAS", rssi: nil, advertisesSupportedService: false, at: date(10))
        let order = session.sortedValidCandidates.map(\.rssi)
        XCTAssertEqual(order[0], -55)
        XCTAssertEqual(order[1], -70)
        XCTAssertNil(order[2]) // bilinmeyen RSSI listenin sonunda, asla 0 değil
    }

    func testScanFailureAndStatusCodes() {
        var session = KeyDiscoverySession(vin: vin)
        XCTAssertEqual(session.statusCode(now: date(10)), "K00_NOT_REQUESTED")
        session.requestScan()
        XCTAssertEqual(session.statusCode(now: date(10)), "K01_NOT_STARTED")
        session.beginScan(at: date(10))
        XCTAssertEqual(session.statusCode(now: date(10)), "K02_NO_RAW")
        session.observe(identifier: "a", name: "My T-SAS", rssi: -60, advertisesSupportedService: false, at: date(10))
        XCTAssertEqual(session.statusCode(now: date(10)), "K04_CANDIDATE")
        session.failScan("Android kodu=2")
        XCTAssertEqual(session.statusCode(now: date(10)), "K01_SCAN_FAILED")
    }

    func testRegisteredAddressEvidence() {
        var session = KeyDiscoverySession(vin: vin)
        session.observe(
            identifier: "44444444-4444-4444-4444-444444444444",
            name: "BilinmeyenAd", rssi: -65,
            advertisesSupportedService: false,
            matchesRegisteredAddress: true,
            at: date(10)
        )
        let candidate = session.sortedValidCandidates[0]
        XCTAssertTrue(candidate.isValid)
        XCTAssertEqual(candidate.reason, "Kayıtlı adres eşleşti; bond ve imzalı kimlik ayrıca doğrulanmalı")
    }
}
