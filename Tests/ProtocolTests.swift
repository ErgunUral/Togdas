import XCTest
@testable import ToqdasCore

final class ProtocolTests: XCTestCase {
    func testRFC7636PKCEVector() {
        let attempt = OAuthAttempt(state: "s", verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", createdAt: Date())
        XCTAssertEqual(attempt.challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testCallbackRejectsWrongOriginStateDuplicatesAndExpiry() throws {
        let now = Date()
        let attempt = OAuthAttempt(state: "expected", verifier: "v", createdAt: now)
        XCTAssertEqual(try attempt.code(from: URL(string: "superapp://prod/callback?state=expected&code=ok")!, now: now), "ok")
        for value in [
            "superapp://other/callback?state=expected&code=ok",
            "https://prod/callback?state=expected&code=ok",
            "superapp://prod/callback?state=wrong&code=ok",
            "superapp://prod/callback?state=expected&state=expected&code=ok",
            "superapp://prod/callback?state=expected&code=ok&code=other",
            "superapp://prod/callback?state=expected&code=ok&error=denied"
        ] { XCTAssertThrowsError(try attempt.code(from: URL(string: value)!, now: now)) }
        let url = URL(string: "superapp://prod/callback?state=expected&code=ok")!
        XCTAssertThrowsError(try attempt.code(from: url, now: now.addingTimeInterval(601)))
        XCTAssertThrowsError(try attempt.code(from: url, now: now.addingTimeInterval(-1)))
    }

    func testVehiclesDeduplicateAndAcceptBothResponseForms() throws {
        let data = Data(#"{"ownedVins":[{"vin":"ABC12345678901234","name":"Aracım"},"DEF12345678901234"],"friendVins":[{"vinNumber":"ABC12345678901234"},{"vin":"GHJ12345678901234","name":"Paylaşılan"},"invalid"]}"#.utf8)
        let vehicles = try Vehicle.parse(data)
        XCTAssertEqual(vehicles.count, 3)
        XCTAssertEqual(vehicles.first?.title, "Aracım")
        XCTAssertEqual(vehicles[0].access, .owner)
        XCTAssertFalse(vehicles[0].isShared)
        XCTAssertTrue(vehicles[2].isShared)
        XCTAssertThrowsError(try Vehicle.parse(Data("{}".utf8)))
    }

    func testFormEncodingProtectsReservedCharacters() {
        let encoded = String(decoding: FormEncoding.data(["code": "a+b&c=d /?"]), as: UTF8.self)
        XCTAssertEqual(encoded, "code=a%2Bb%26c%3Dd%20%2F%3F")
    }

    func testTelemetryMapsKnownFieldsAndKeepsMissingValuesUnknown() throws {
        let data = Data(#"{"telemetry":{"battery":{"content":{"batteryStateOfCharge":{"batteryStateOfChargeValue":78.5}}},"vehicleRange":{"content":{"estRange":{"range":365}}},"batteryPowerStatus":{"batteryPowerStatusContent":{"lowVoltageStateOfChargeValue":{"lowVoltageStateOfChargeValue":90}}},"obcState":{"content":{"chargeMode":{"chargeModeEnumValue":"Charging"}}},"breakWarning":false,"engineWarning":false,"driveMode":{"content":{"driveModeState":{"driveMode":"DRIVEMODE_COMFORT"}}},"odometerStatus":{"odometerStatusContent":{"odometer":{"odometerValue":12840000},"outsideTemp":{"outsideTempValue":24},"insideTemp":{"insideTempValue":21.5}}},"tirePressure":{"content":{"frontLeft":{"frontLeftValue":250},"frontRight":{"frontRightValue":252},"rearLeft":{"rearLeftValue":248},"rearRight":{"rearRightValue":251}}},"tireTemperature":{"tireTemperatureContent":{"frontLeftTireTemp":{"frontLeftTireTempValue":32},"frontRightTireTemp":{"frontRightTireTempValue":33},"rearLeftTireTemp":{"rearLeftTireTempValue":31},"rearRightTireTemp":{"rearRightTireTempValue":34}}},"location":{"content":{"longitude":{"longitudeValue":32.585423},"latitude":{"latitudeValue":39.98705}}},"updatedOn":"2026-10-23T08:15:00Z"}}"#.utf8)
        let telemetry = try VehicleTelemetry(data: data)
        XCTAssertEqual(telemetry.batteryPercent, 78.5)
        XCTAssertEqual(telemetry.rangeKM, 365)
        XCTAssertEqual(telemetry.auxiliaryBatteryPercent, 90)
        XCTAssertEqual(telemetry.chargingState, "Charging")
        XCTAssertEqual(telemetry.odometerKM, 12_840)
        XCTAssertEqual(telemetry.outsideTemperatureC, 24)
        XCTAssertEqual(telemetry.insideTemperatureC, 21.5)
        XCTAssertEqual(telemetry.brakeWarning, false)
        XCTAssertEqual(telemetry.engineWarning, false)
        XCTAssertEqual(telemetry.driveMode, "DRIVEMODE_COMFORT")
        XCTAssertEqual(telemetry.driveModeText, "Konfor")
        XCTAssertEqual(telemetry.latitude, 39.98705)
        XCTAssertEqual(telemetry.longitude, 32.585423)
        XCTAssertEqual(telemetry.coordinateText, "39.98705, 32.58542")
        XCTAssertTrue(telemetry.tirePressureAvailable)
        XCTAssertEqual(telemetry.tires.count, 4)
        XCTAssertEqual(telemetry.tires[0].position, .frontLeft)
        XCTAssertEqual(telemetry.tires[0].pressurePSI ?? 0, 36.26, accuracy: 0.01)
        XCTAssertEqual(telemetry.tires[0].temperatureC, 32)
        XCTAssertNotNil(telemetry.vehicleUpdatedAt)
        let missing = try VehicleTelemetry(data: Data(#"{"telemetry":{}}"#.utf8))
        XCTAssertNil(missing.batteryPercent)
        XCTAssertNil(missing.rangeKM)
        XCTAssertNil(missing.chargingState)
        XCTAssertNil(missing.vehicleUpdatedAt)
        XCTAssertNil(missing.odometerKM)
        XCTAssertNil(missing.insideTemperatureC)
        XCTAssertNil(missing.brakeWarning)
        XCTAssertNil(missing.engineWarning)
        XCTAssertNil(missing.driveMode)
        XCTAssertNil(missing.driveModeText)
        XCTAssertNil(missing.latitude)
        XCTAssertNil(missing.longitude)
        XCTAssertNil(missing.coordinateText)
        XCTAssertFalse(missing.tirePressureAvailable)
        let invalid = try VehicleTelemetry(data: Data(#"{"telemetry":{"battery":{"content":{"batteryStateOfCharge":{"batteryStateOfChargeValue":true}}},"vehicleRange":{"content":{"estRange":{"range":-1}}},"batteryPowerStatus":{"batteryPowerStatusContent":{"lowVoltageStateOfChargeValue":101}},"breakWarning":1,"engineWarning":"unknown","driveMode":{"content":{"driveModeState":{"driveMode":""}}},"location":{"content":{"latitude":{"latitudeValue":100},"longitude":{"longitudeValue":32.5}}},"odometerStatus":{"odometerStatusContent":{"insideTemp":{"insideTempValue":999}}}}}"#.utf8))
        XCTAssertNil(invalid.batteryPercent)
        XCTAssertNil(invalid.rangeKM)
        XCTAssertNil(invalid.auxiliaryBatteryPercent)
        XCTAssertNil(invalid.brakeWarning)
        XCTAssertNil(invalid.engineWarning)
        XCTAssertNil(invalid.insideTemperatureC)
        XCTAssertNil(invalid.driveMode)
        XCTAssertNil(invalid.latitude)
        XCTAssertEqual(invalid.longitude, 32.5)
        XCTAssertNil(invalid.coordinateText)
        XCTAssertThrowsError(try VehicleTelemetry(data: Data("{}".utf8)))
    }
}
