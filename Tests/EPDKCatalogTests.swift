import XCTest
@testable import ToqdasCore

final class EPDKCatalogTests: XCTestCase {
    private let sample = #"""
    {
      "statusCode": 200,
      "numRows": 2,
      "errors": null,
      "data": [
        {
          "sarjIstasyonuNo": "ŞRJ/7918",
          "sarjIstasyonuAdi": "TÜED - KOCATEPE",
          "sarjAgiIsletmecisiUnvan": "FULL ŞARJ",
          "marka": "MULTI FORCE",
          "adres": "Kültür Mahallesi, Ankara",
          "hizmetSekli": "HALKA_ACIK",
          "enlem": 39.9197,
          "boylam": 32.8605,
          "soketler": [
            {"soketNo":"SKT/18029", "soketTipi":"AC", "soketTuru":"AC_TYPE2", "soketGucu":"22"},
            {"soketNo":"SKT/18030", "soketTipi":"DC", "soketTuru":"DC_CCS", "soketGucu":120}
          ]
        },
        {
          "sarjIstasyonuNo": "ŞRJ/7919",
          "sarjIstasyonuAdi": "ÖZEL TESİS",
          "sarjAgiIsletmecisiUnvan": "ÖZEL",
          "marka": "TEST",
          "adres": "Ankara",
          "hizmetSekli": "ÖZEL",
          "enlem": "39.92",
          "boylam": "32.86",
          "soketler": null
        }
      ]
    }
    """#

    func testParsesEPDKFieldsAndStringOrNumberCoordinates() throws {
        let catalog = try EPDKCatalogParser.parse(Data(sample.utf8), fetchedAt: Date(timeIntervalSince1970: 1_000))
        XCTAssertEqual(catalog.stations.count, 2)
        let station = try XCTUnwrap(catalog.stations.first)
        XCTAssertEqual(station.id, "ŞRJ/7918")
        XCTAssertEqual(station.address, "Kültür Mahallesi, Ankara")
        XCTAssertTrue(station.isPublic)
        XCTAssertEqual(station.latitude ?? 0, 39.9197, accuracy: 0.0001)
        XCTAssertEqual(station.connectors.count, 2)
        XCTAssertEqual(station.connectors[0].powerKW, 22)
        XCTAssertEqual(station.connectors[1].powerKW, 120)
        XCTAssertNil(catalog.stations[1].connectors.first)
    }

    func testRejectsWrongStatusAndIncompleteRowCount() {
        let wrongStatus = sample.replacingOccurrences(of: "\"statusCode\": 200", with: "\"statusCode\": 500")
        XCTAssertThrowsError(try EPDKCatalogParser.parse(Data(wrongStatus.utf8)))

        let wrongCount = sample.replacingOccurrences(of: "\"numRows\": 2", with: "\"numRows\": 3")
        XCTAssertThrowsError(try EPDKCatalogParser.parse(Data(wrongCount.utf8)))
    }

    func testRejectsDuplicateOrMissingStationIDs() {
        let duplicate = sample.replacingOccurrences(of: "ŞRJ/7919", with: "ŞRJ/7918")
        XCTAssertThrowsError(try EPDKCatalogParser.parse(Data(duplicate.utf8)))

        let missing = sample.replacingOccurrences(of: "\"ŞRJ/7919\"", with: "\"\"")
        XCTAssertThrowsError(try EPDKCatalogParser.parse(Data(missing.utf8)))
    }

    func testOutOfTurkeyCoordinatesAreNotUsedForMapping() throws {
        let invalidCoordinates = sample
            .replacingOccurrences(of: "39.9197", with: "10.0")
            .replacingOccurrences(of: "32.8605", with: "10.0")
        let catalog = try EPDKCatalogParser.parse(Data(invalidCoordinates.utf8))
        XCTAssertNil(catalog.stations.first?.latitude)
        XCTAssertNil(catalog.stations.first?.longitude)
    }

    func testFiltersPublicStationsByTextConnectorAndDistance() throws {
        let catalog = try EPDKCatalogParser.parse(Data(sample.utf8))
        let results = catalog.filtered(
            query: "kocatepe",
            connectorType: "DC",
            origin: (latitude: 39.92, longitude: 32.86),
            radiusKM: 5
        )
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.station.id, "ŞRJ/7918")
        XCTAssertLessThan(results.first?.distanceKM ?? 999, 1)

        let privateResults = catalog.filtered(
            query: "özel",
            connectorType: "ALL",
            origin: nil,
            radiusKM: 0
        )
        XCTAssertTrue(privateResults.isEmpty)
    }

    func testMissingCoordinateDoesNotAppearInNearbyResults() throws {
        let catalog = try EPDKCatalogParser.parse(Data(sample.utf8))
        let results = catalog.filtered(
            query: "özel tesis",
            connectorType: "ALL",
            origin: (latitude: 39.9, longitude: 32.8),
            radiusKM: 40
        )
        XCTAssertTrue(results.isEmpty)
    }
}
