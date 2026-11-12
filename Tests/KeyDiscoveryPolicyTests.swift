import XCTest
@testable import ToqdasCore

/// `KeyDiscoveryPolicy`/`KeyDiscoveryCandidate`: Android `.57.18`
/// `Q4.java` kurallarının iOS karşılığı — VIN-ad eşleşmesi, aday
/// geçerliliği/önceliği, seçim tazeliği ve durum kodu.
final class KeyDiscoveryPolicyTests: XCTestCase {
    private let vin = "LGWFCFS77RM100185" // 17 karakter, geçerli alfabe
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Istanbul")!
        return calendar
    }
    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: hour, minute: minute))!
    }

    // MARK: VIN-ad eşleşmesi (Android j1)

    func testDeviceNameMatchesVariants() {
        XCTAssertTrue(KeyDiscoveryPolicy.deviceNameMatches(vin: vin, name: "MY T-SAS \(vin)"))
        XCTAssertTrue(KeyDiscoveryPolicy.deviceNameMatches(vin: vin, name: "MY T-SAS \(vin.suffix(8))"))
        XCTAssertTrue(KeyDiscoveryPolicy.deviceNameMatches(vin: vin, name: "MY T-SAS \(vin.suffix(6))"))
        // Küçük harf + fazladan boşluk: trim + upper ile yakalanır.
        XCTAssertTrue(KeyDiscoveryPolicy.deviceNameMatches(vin: vin, name: "  my t-sas \(vin.suffix(8)) "))
        XCTAssertFalse(KeyDiscoveryPolicy.deviceNameMatches(vin: vin, name: "My T-SAS"))
        XCTAssertFalse(KeyDiscoveryPolicy.deviceNameMatches(vin: vin, name: "MY T-SAS 0185")) // son 4
        XCTAssertFalse(KeyDiscoveryPolicy.deviceNameMatches(vin: vin, name: nil))
    }

    func testVINAlphabetExcludesIOQ() {
        XCTAssertFalse(KeyDiscoveryPolicy.deviceNameMatches(vin: "LGWFCFS7IRM100185", name: "MY T-SAS RM100185")) // I geçersiz
        XCTAssertTrue(KeyDiscoveryPolicy.isValidVIN(vin))
        XCTAssertFalse(KeyDiscoveryPolicy.isValidVIN("KISA"))
        XCTAssertFalse(KeyDiscoveryPolicy.isValidVIN("LGWFCFS77RM100185I")) // I yok ama 18 karakter
    }

    func testNameIsGenericTSAS() {
        XCTAssertTrue(KeyDiscoveryPolicy.nameIsGenericTSAS("My T-SAS"))
        XCTAssertTrue(KeyDiscoveryPolicy.nameIsGenericTSAS("  my t-sas  "))
        XCTAssertFalse(KeyDiscoveryPolicy.nameIsGenericTSAS("My T-SAS RM100185"))
        XCTAssertFalse(KeyDiscoveryPolicy.nameIsGenericTSAS(nil))
    }

    // MARK: Aday geçerliliği ve öncelik (Android f305e + metinler)

    func testCandidateValidityPriorityAndReasons() {
        // Sadece genel ad: en düşük kanıt.
        let generic = KeyDiscoveryCandidate.fromSighting(
            name: "My T-SAS", rssi: -60, vin: vin, advertisesSupportedService: false,
            at: date(10)
        )
        XCTAssertTrue(generic.isValid)
        XCTAssertEqual(generic.reason, "My T-SAS adı var; VIN ve araç kimliği henüz doğrulanmadı")

        // VIN-ad kanıtı önceliği genel adın üstündedir.
        var vinNamed = generic
        vinNamed.observe(
            name: "MY T-SAS \(vin.suffix(8))", rssi: nil,
            nameMatchesVIN: true, advertisesSupportedService: false,
            at: date(10)
        )
        XCTAssertTrue(vinNamed.isValid)
        XCTAssertEqual(vinNamed.reason, "VIN ile cihaz adı uyumlu; kimlik doğrulama henüz yapılmadı")

        // Kayıtlı adres ikinci öncelik.
        var addressMatch = generic
        addressMatch.observe(
            name: "BaşkaAd", rssi: nil,
            nameMatchesVIN: false, matchesRegisteredAddress: true,
            advertisesSupportedService: false,
            at: date(10)
        )
        XCTAssertTrue(addressMatch.isValid)
        XCTAssertEqual(addressMatch.reason, "Kayıtlı adres eşleşti; bond ve imzalı kimlik ayrıca doğrulanmalı")

        // Servis kanıtı üçüncü öncelik.
        let serviceOnly = KeyDiscoveryCandidate.fromSighting(
            name: "Cihaz-X", rssi: -70, vin: vin, advertisesSupportedService: true,
            at: date(10)
        )
        XCTAssertTrue(serviceOnly.isValid)
        XCTAssertEqual(serviceOnly.reason, "My T-SAS servis adayı; VIN/araç kimliği henüz doğrulanmadı")

        // Hiç kanıt yok: elendi.
        let rejected = KeyDiscoveryCandidate.fromSighting(
            name: "JBL Flip", rssi: -80, vin: vin, advertisesSupportedService: false,
            at: date(10)
        )
        XCTAssertFalse(rejected.isValid)
        XCTAssertEqual(rejected.reason, "Elendi: VIN-ad, kayıtlı adres veya desteklenen servis kanıtı yok")
    }

    func testCandidateFlagsOnlyAccumulate() {
        var candidate = KeyDiscoveryCandidate.fromSighting(
            name: "Cihaz-X", rssi: -70, vin: vin, advertisesSupportedService: true,
            at: date(10)
        )
        XCTAssertTrue(candidate.advertisesSupportedService)
        // Sonraki gözlem kanıt vermezse bayrak korunur (|= semantiği).
        candidate.observe(
            name: "Cihaz-X", rssi: -75,
            nameMatchesVIN: false, advertisesSupportedService: false,
            at: date(10, 1)
        )
        XCTAssertTrue(candidate.advertisesSupportedService)
        XCTAssertEqual(candidate.lastSeen, date(10, 1))
        // RSSI yalnız dolu değerle güncellenir; nil yazmaz.
        XCTAssertEqual(candidate.rssi, -75)
        candidate.observe(
            name: nil, rssi: nil,
            nameMatchesVIN: false, advertisesSupportedService: false,
            at: date(10, 2)
        )
        XCTAssertEqual(candidate.rssi, -75)
        XCTAssertEqual(candidate.name, "Cihaz-X")
    }

    // MARK: Seçim tazeliği (Android Q4.x)

    func testSelectionRequiresScanRun() {
        let now = date(11)
        XCTAssertFalse(KeyDiscoveryPolicy.isSelectionAllowed(
            hasScanRun: false, scanActive: false, lastCandidateUpdate: now, now: now
        ))
    }

    func testSelectionAllowedWhileScanActive() {
        let now = date(11)
        XCTAssertTrue(KeyDiscoveryPolicy.isSelectionAllowed(
            hasScanRun: true, scanActive: true, lastCandidateUpdate: nil, now: now
        ))
    }

    func testSelectionFreshnessWindow() {
        XCTAssertTrue(KeyDiscoveryPolicy.isSelectionAllowed(
            hasScanRun: true, scanActive: false,
            lastCandidateUpdate: date(10, 59), now: date(11)
        )) // 60 sn
        XCTAssertFalse(KeyDiscoveryPolicy.isSelectionAllowed(
            hasScanRun: true, scanActive: false,
            lastCandidateUpdate: date(10, 58), now: date(11).addingTimeInterval(61)
        )) // > 120 sn
        XCTAssertFalse(KeyDiscoveryPolicy.isSelectionAllowed(
            hasScanRun: true, scanActive: false, lastCandidateUpdate: nil, now: date(11)
        ))
    }

    // MARK: Durum kodu (Android Q4.j)

    func testStatusCodeDerivation() {
        XCTAssertEqual(
            KeyDiscoveryPolicy.statusCode(identityVerified: true, rawSightingCount: 3, validCandidateCount: 1),
            "K07_READY"
        )
        XCTAssertEqual(
            KeyDiscoveryPolicy.statusCode(authenticationFailed: true, rawSightingCount: 3, validCandidateCount: 1),
            "K06_AUTH_FAILED"
        )
        XCTAssertEqual(
            KeyDiscoveryPolicy.statusCode(scanRequested: false, rawSightingCount: 0, validCandidateCount: 0),
            "K00_NOT_REQUESTED"
        )
        XCTAssertEqual(
            KeyDiscoveryPolicy.statusCode(scanRequested: true, scanStarted: false, rawSightingCount: 0, validCandidateCount: 0),
            "K01_NOT_STARTED"
        )
        XCTAssertEqual(
            KeyDiscoveryPolicy.statusCode(scanRequested: true, scanStarted: true, rawSightingCount: 0, validCandidateCount: 0),
            "K02_NO_RAW"
        )
        XCTAssertEqual(
            KeyDiscoveryPolicy.statusCode(scanRequested: true, scanStarted: true, rawSightingCount: 5, validCandidateCount: 0),
            "K03_NO_CANDIDATE"
        )
        XCTAssertEqual(
            KeyDiscoveryPolicy.statusCode(scanRequested: true, scanStarted: true, rawSightingCount: 5, validCandidateCount: 2),
            "K04_CANDIDATE"
        )
    }

    // MARK: Sabitler (Android paritesi)

    func testConstantsMatchAndroid() {
        XCTAssertEqual(KeyDiscoveryPolicy.scanWindow, 12)
        XCTAssertEqual(KeyDiscoveryPolicy.selectionFreshness, 120)
        XCTAssertEqual(KeyDiscoveryPolicy.maxRawCandidates, 128)
        XCTAssertEqual(KeyDiscoveryPolicy.maxValidCandidates, 32)
        XCTAssertEqual(
            KeyDiscoveryPolicy.selectionStaleMessage,
            "Cihazları Tara ile güncel aday seçin."
        )
    }
}
