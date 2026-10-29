import XCTest
@testable import ToqdasCore

final class GeofencePolicyTests: XCTestCase {
    func testAlwaysPermissionWithHomeIsReady() {
        let readiness = GeofencePolicy.readiness(hasHomeLocation: true, permission: .always)
        XCTAssertTrue(readiness.canEnable)
        XCTAssertNil(readiness.blocker)
    }

    func testMissingHomeLocationBlocks() {
        let readiness = GeofencePolicy.readiness(hasHomeLocation: false, permission: .always)
        XCTAssertFalse(readiness.canEnable)
        XCTAssertEqual(readiness.blocker, .missingHomeLocation)
        XCTAssertTrue(readiness.message.contains("ev konumu"))
    }

    func testWhenInUseIsNotEnoughForBackgroundGeofence() {
        let readiness = GeofencePolicy.readiness(hasHomeLocation: true, permission: .whenInUse)
        XCTAssertFalse(readiness.canEnable)
        XCTAssertEqual(readiness.blocker, .backgroundPermissionMissing)
    }

    func testDeniedAndRestrictedAreDistinct() {
        XCTAssertEqual(GeofencePolicy.readiness(hasHomeLocation: true, permission: .denied).blocker,
                       .permissionDenied)
        XCTAssertEqual(GeofencePolicy.readiness(hasHomeLocation: true, permission: .restricted).blocker,
                       .permissionRestricted)
    }

    func testNotDeterminedAsksForPermission() {
        let readiness = GeofencePolicy.readiness(hasHomeLocation: true, permission: .notDetermined)
        XCTAssertEqual(readiness.blocker, .permissionNotDetermined)
    }

    func testEveryBlockerHasMessage() {
        let cases: [(Bool, GeofencePermission)] = [
            (false, .always), (true, .notDetermined), (true, .denied),
            (true, .restricted), (true, .whenInUse)
        ]
        for (hasHome, permission) in cases {
            let readiness = GeofencePolicy.readiness(hasHomeLocation: hasHome, permission: permission)
            XCTAssertFalse(readiness.canEnable)
            XCTAssertFalse(readiness.message.isEmpty, "\(String(describing: readiness.blocker)) mesajsız")
        }
    }

    func testRadiusClamping() {
        XCTAssertEqual(GeofencePolicy.clampedRadius(10), GeofencePolicy.minimumRadiusMeters)
        XCTAssertEqual(GeofencePolicy.clampedRadius(10_000), GeofencePolicy.maximumRadiusMeters)
        XCTAssertEqual(GeofencePolicy.clampedRadius(120), 120)
        XCTAssertEqual(GeofencePolicy.clampedRadius(.nan), GeofencePolicy.radiusMeters)
    }

    func testNeedsRestartWhenCoordinateOrRadiusChanges() {
        let home = (latitude: 41.0, longitude: 29.0)
        XCTAssertTrue(GeofencePolicy.needsRestart(
            previousCoordinate: nil, previousRadius: 100,
            newCoordinate: home, newRadius: 100))
        XCTAssertFalse(GeofencePolicy.needsRestart(
            previousCoordinate: home, previousRadius: 100,
            newCoordinate: home, newRadius: 100.2))
        XCTAssertTrue(GeofencePolicy.needsRestart(
            previousCoordinate: home, previousRadius: 100,
            newCoordinate: (41.001, 29.0), newRadius: 100))
        XCTAssertTrue(GeofencePolicy.needsRestart(
            previousCoordinate: home, previousRadius: 100,
            newCoordinate: home, newRadius: 150))
    }
}
