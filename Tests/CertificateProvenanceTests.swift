import XCTest
@testable import ToqdasCore

/// Sertifika kaynağı: "tekrar alınmadı" iddiasının kanıtı.
final class CertificateProvenanceTests: XCTestCase {
    func testReusedSummary() {
        let text = CertificateProvenance.summary(
            CertificateProvenance(source: .reused, at: 0), daysRemaining: 340)
        XCTAssertEqual(text, "Dijital anahtar yeniden kullanılıyor · 340 gün geçerli")
    }

    func testIssuedSummary() {
        let text = CertificateProvenance.summary(
            CertificateProvenance(source: .issued, at: 0), daysRemaining: 365)
        XCTAssertEqual(text, "Dijital anahtar alındı · 365 gün geçerli")
    }

    func testRefreshedSummary() {
        let text = CertificateProvenance.summary(
            CertificateProvenance(source: .refreshed, at: 0), daysRemaining: nil)
        XCTAssertEqual(text, "Sertifika süresi dolmadan yenilendi")
    }

    func testRoundTrip() {
        let suite = "test.certProvenance"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = CertificateProvenanceStore(defaults: defaults)

        XCTAssertNil(store.load(vin: "V"))
        store.save(CertificateProvenance(source: .reused, at: 42), vin: "V")
        XCTAssertEqual(store.load(vin: "V"), CertificateProvenance(source: .reused, at: 42))
        store.clear(vin: "V")
        XCTAssertNil(store.load(vin: "V"))
        defaults.removePersistentDomain(forName: suite)
    }
}
