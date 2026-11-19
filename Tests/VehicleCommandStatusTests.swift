import XCTest
@testable import ToqdasCore

/// `VehicleCommandStatus`: Widget'a yazılan son komut sonucu; dürüstlük
/// kuralları ve doğrulama bildirim mantığı testleri.
final class VehicleCommandStatusTests: XCTestCase {
    private var storeDefaults: UserDefaults {
        UserDefaults(suiteName: "test.toqdas.commandstatus.\(UUID().uuidString)")!
    }

    func testSaveNotifiesSurfacesOncePerActualChange() {
        let defaults = storeDefaults
        var count = 0
        let observer = NotificationCenter.default.addObserver(
            forName: .vehicleCommandStatusDidChange, object: defaults, queue: nil
        ) { _ in count += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        let status = VehicleCommandStatus(
            actionLabel: "Kilitleme", sentAt: Date(timeIntervalSince1970: 1_800_000_000), verified: nil
        )
        VehicleCommandStatusStore.save(status, defaults: defaults)
        XCTAssertEqual(count, 1)

        // Aynı içerik: yayın yok (widget/saat boşuna yenilenmez).
        VehicleCommandStatusStore.save(status, defaults: defaults)
        XCTAssertEqual(count, 1)

        VehicleCommandStatusStore.markVerified(false, ifLabelMatches: { _ in true }, defaults: defaults)
        XCTAssertEqual(count, 2)

        // `verified` zaten dolu: markVerified yazmaz, yayın da yok.
        VehicleCommandStatusStore.markVerified(true, ifLabelMatches: { _ in true }, defaults: defaults)
        XCTAssertEqual(count, 2)
    }

    func testDisplayTextVariants() {
        var status = VehicleCommandStatus(
            actionLabel: "Kilit açma",
            sentAt: Date(),
            verified: nil
        )
        XCTAssertEqual(status.displayText, "Son komut: Kilit açma · doğrulama yok")
        XCTAssertEqual(status.verificationText, "doğrulama yok")

        status = VehicleCommandStatus(actionLabel: "Kilitleme", sentAt: Date(), verified: true)
        XCTAssertEqual(status.displayText, "Son komut: Kilitleme · doğrulandı")

        status = VehicleCommandStatus(actionLabel: "Kilitleme", sentAt: Date(), verified: false)
        XCTAssertEqual(status.displayText, "Son komut: Kilitleme · doğrulanamadı")
    }

    func testNoteIsShownOnlyWhenStateWasAlreadyInTarget() {
        var status = VehicleCommandStatus(
            actionLabel: "Kilitleme", sentAt: Date(), verified: true, note: "araç zaten kilitliydi"
        )
        XCTAssertEqual(status.displayText, "Son komut: Kilitleme · doğrulandı · araç zaten kilitliydi")

        status = VehicleCommandStatus(actionLabel: "Kilitleme", sentAt: Date(), verified: true)
        XCTAssertEqual(status.displayText, "Son komut: Kilitleme · doğrulandı")
    }

    func testMarkVerifiedCarriesNoteAndKeepsFirstResult() {
        let defaults = storeDefaults
        VehicleCommandStatusStore.save(
            VehicleCommandStatus(actionLabel: "Kilitleme", sentAt: Date(), verified: nil),
            defaults: defaults
        )
        VehicleCommandStatusStore.markVerified(
            true, ifLabelMatches: { _ in true }, note: "araç zaten kilitliydi", defaults: defaults
        )
        XCTAssertEqual(VehicleCommandStatusStore.load(defaults: defaults)?.note, "araç zaten kilitliydi")

        // İlk kesin sonuç değişmez: sonraki "doğrulanamadı" yazımı yok sayılır.
        VehicleCommandStatusStore.markVerified(false, ifLabelMatches: { _ in true }, defaults: defaults)
        XCTAssertEqual(VehicleCommandStatusStore.load(defaults: defaults)?.verified, true)
    }

    func testEmptyLabelYieldsNilNotFakeText() {
        let status = VehicleCommandStatus(actionLabel: "   ", sentAt: Date(), verified: nil)
        XCTAssertNil(status.displayText)
    }

    func testStaleAfterTwentyFourHoursOnly() {
        let recent = VehicleCommandStatus(actionLabel: "Bagaj açma", sentAt: Date(), verified: nil)
        XCTAssertFalse(recent.isStale)

        let old = VehicleCommandStatus(
            actionLabel: "Bagaj açma",
            sentAt: Date().addingTimeInterval(-24 * 3600 - 1),
            verified: nil
        )
        XCTAssertTrue(old.isStale)

        let almost = VehicleCommandStatus(
            actionLabel: "Bagaj açma",
            sentAt: Date().addingTimeInterval(-23 * 3600),
            verified: nil
        )
        XCTAssertFalse(almost.isStale)
    }

    func testSaveAndLoadRoundTrip() {
        let defaults = storeDefaults
        let status = VehicleCommandStatus(actionLabel: "Kilitleme", sentAt: Date(), verified: nil)
        VehicleCommandStatusStore.save(status, defaults: defaults)
        XCTAssertEqual(VehicleCommandStatusStore.load(defaults: defaults), status)
    }

    func testMarkVerifiedOnlyForMatchingPendingLabel() {
        let defaults = storeDefaults
        VehicleCommandStatusStore.save(
            VehicleCommandStatus(actionLabel: "Kilitleme", sentAt: Date(), verified: nil),
            defaults: defaults
        )
        VehicleCommandStatusStore.markVerified(true, ifLabelMatches: { $0.lowercased().contains("kilit") }, defaults: defaults)
        XCTAssertTrue(VehicleCommandStatusStore.load(defaults: defaults)?.verified == true)

        // Zaten doğrulanmış kayıt tekrar doğrulama çağrısıyla değişmez.
        VehicleCommandStatusStore.markVerified(false, ifLabelMatches: { _ in true }, defaults: defaults)
        XCTAssertTrue(VehicleCommandStatusStore.load(defaults: defaults)?.verified == true)
    }

    func testMarkVerifiedIgnoresNonMatchingLabel() {
        let defaults = storeDefaults
        VehicleCommandStatusStore.save(
            VehicleCommandStatus(actionLabel: "Klima açma", sentAt: Date(), verified: nil),
            defaults: defaults
        )
        VehicleCommandStatusStore.markVerified(true, ifLabelMatches: { $0.lowercased().contains("kilit") }, defaults: defaults)
        XCTAssertNil(VehicleCommandStatusStore.load(defaults: defaults)?.verified)
    }

    func testLoadWithoutDataReturnsNil() {
        XCTAssertNil(VehicleCommandStatusStore.load(defaults: storeDefaults))
    }
}
