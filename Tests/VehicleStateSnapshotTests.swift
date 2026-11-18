import XCTest
@testable import ToqdasCore

/// Son bilinen imzalı araç durumu: yaş etiketi, süre sınırı ve disk round-trip.
final class VehicleStateSnapshotTests: XCTestCase {
    private let reference = Date(timeIntervalSince1970: 1_700_000_000)

    private func snapshot(locked: Int? = 1, trunk: Int? = 0, power: Int? = 3,
                          age: TimeInterval = 0) -> VehicleStateSnapshot {
        VehicleStateSnapshot(locked: locked, trunkAjar: trunk, powerState: power,
                             observedAt: reference.addingTimeInterval(-age))
    }

    func testFreshSnapshotOmitsAge() {
        XCTAssertEqual(snapshot(age: 30).lockText(now: reference), "Kilitli")
    }

    func testStaleSnapshotCarriesAge() {
        XCTAssertEqual(snapshot(age: 2 * 3600).lockText(now: reference),
                       "Kilitli · 2 saat önce")
    }

    func testExpiredSnapshotReturnsNilAndStoreDropsIt() {
        let expired = snapshot(age: 25 * 3600)
        XCTAssertTrue(expired.isExpired(now: reference))
        XCTAssertNil(expired.lockText(now: reference), "24 saatten eski kayıt gösterilmemeli")

        let defaults = UserDefaults(suiteName: "toqdas.snapshot.tests.expired")!
        defaults.removePersistentDomain(forName: "toqdas.snapshot.tests.expired")
        let data = try! JSONEncoder().encode(expired)
        defaults.set(data, forKey: VehicleStateSnapshotStore.key(vin: "VIN1"))
        XCTAssertNil(VehicleStateSnapshotStore.load(vin: "VIN1", defaults: defaults, now: reference))
        XCTAssertNil(defaults.data(forKey: VehicleStateSnapshotStore.key(vin: "VIN1")),
                     "Süresi geçmiş kayıt diskte kalmamalı")
    }

    func testUnknownValuesStayUnknown() {
        let unknown = VehicleStateSnapshot(locked: 0, trunkAjar: nil, powerState: nil,
                                           observedAt: reference)
        XCTAssertNil(unknown.isLocked, "0/3 gibi tanımsız değer kilit iddiasına dönüşmemeli")
        XCTAssertNil(unknown.lockText(now: reference))
        XCTAssertNil(unknown.trunkText(now: reference))
        XCTAssertNil(unknown.driveText(now: reference))
    }

    func testDriveReadyOnlyFromPowerStateFour() {
        XCTAssertEqual(snapshot(power: 3).driveText(now: reference), "Hazır değil")
        XCTAssertEqual(snapshot(power: 4).driveText(now: reference), "Hazır")
    }

    func testStoreRoundTripKeepsValuesAndAge() {
        let defaults = UserDefaults(suiteName: "toqdas.snapshot.tests.roundtrip")!
        defaults.removePersistentDomain(forName: "toqdas.snapshot.tests.roundtrip")

        let telemetry = BleTelemetry(locked: 2, doors: [0, 0, 0, 0], trunkAjar: 1,
                                     powerState: 4, counter: 7,
                                     receivedAt: reference.addingTimeInterval(-600))
        VehicleStateSnapshotStore.save(telemetry, vin: "VIN2", defaults: defaults)

        let loaded = VehicleStateSnapshotStore.load(vin: "VIN2", defaults: defaults, now: reference)
        XCTAssertEqual(loaded?.isLocked, false)
        XCTAssertEqual(loaded?.isTrunkAjar, true)
        XCTAssertEqual(loaded?.driveText(now: reference), "Hazır · 10 dakika önce")
        XCTAssertEqual(loaded?.lockText(now: reference), "Kilit açık · 10 dakika önce")

        VehicleStateSnapshotStore.clear(vin: "VIN2", defaults: defaults)
        XCTAssertNil(VehicleStateSnapshotStore.load(vin: "VIN2", defaults: defaults, now: reference))
    }
}
