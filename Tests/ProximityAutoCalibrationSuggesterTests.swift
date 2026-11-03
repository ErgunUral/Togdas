import XCTest
@testable import ToqdasCore

/// `ProximityAutoCalibrationSuggester`: GATT örneklerinden uygun aralık
/// önerisi; invariantlar — öneri tek sefer, kalibrasyon yazma yok.
final class ProximityAutoCalibrationSuggesterTests: XCTestCase {
    func testNoSuggestionFromFewScatteredSamples() {
        var suggester = ProximityAutoCalibrationSuggester()
        for value in [-60, -85, -61, -84, -59] {
            XCTAssertNil(suggester.feed(value))
        }
        XCTAssertNil(suggester.strongCandidate)
        XCTAssertNil(suggester.weakCandidate)
    }

    func testStableStrongClusterAloneDoesNotSuggest() {
        var suggester = ProximityAutoCalibrationSuggester()
        for value in [-60, -60, -61, -60, -59, -60, -61] {
            XCTAssertNil(suggester.feed(value))
        }
        XCTAssertNotNil(suggester.strongCandidate)
        XCTAssertNil(suggester.weakCandidate)
    }

    func testStableNearThenFarYieldsSuggestion() {
        var suggester = ProximityAutoCalibrationSuggester()
        var suggestion: ProximityAutoCalibrationSuggester.Suggestion?
        for value in [-60, -60, -61, -60, -59, -60] {
            suggestion = suggester.feed(value) ?? suggestion
        }
        // Uzak tarafa geçiş: karşılıklı kararlı zayıf küme.
        for value in [-86, -86, -87, -85, -86, -86] {
            suggestion = suggester.feed(value) ?? suggestion
        }
        XCTAssertEqual(suggestion?.nearSample, -60)
        XCTAssertEqual(suggestion?.farSample, -86)
        XCTAssertTrue(suggestion?.isValid == true)
        XCTAssertGreaterThanOrEqual(suggestion?.separation ?? 0, ProximityCalibration.minimumSeparation)
    }

    func testSuggestionIssuedOnceUntilReset() {
        var suggester = ProximityAutoCalibrationSuggester()
        var count = 0
        for value in [-60, -60, -61, -60, -59, -60, -86, -86, -87, -85, -86, -86] {
            if suggester.feed(value) != nil { count += 1 }
        }
        XCTAssertEqual(count, 1)
        // Öneri tamamlandıktan sonra aynı kümede tekrar öneri üretilmez.
        XCTAssertNil(suggester.feed(-86))
        suggester.reset()
        XCTAssertNil(suggester.strongCandidate)
        XCTAssertNil(suggester.weakCandidate)
    }

    func testResetThenImprovedStrongClusterIsAdopted() {
        var suggester = ProximityAutoCalibrationSuggester()
        var suggestion: ProximityAutoCalibrationSuggester.Suggestion?
        for value in [-70, -70, -71, -70, -70, -70, -90, -90, -91, -90, -90, -90] {
            suggestion = suggester.feed(value) ?? suggestion
        }
        XCTAssertEqual(suggestion?.nearSample, -70)
        suggester.reset()
        suggestion = nil
        for value in [-58, -58, -59, -58, -58, -58, -86, -86, -87, -86, -86, -86] {
            suggestion = suggester.feed(value) ?? suggestion
        }
        XCTAssertEqual(suggestion?.nearSample, -58)
        XCTAssertEqual(suggestion?.farSample, -86)
    }

    func testInvalidSeparationClustersDoNotSuggest() {
        var suggester = ProximityAutoCalibrationSuggester()
        // Küçük ayrım (6 dBm) öneri üretmez: minimum 14 dBm kuralı geçerli.
        for value in [-60, -60, -61, -60, -59, -60, -66, -66, -67, -65, -66, -66] {
            XCTAssertNil(suggester.feed(value))
        }
    }
}
