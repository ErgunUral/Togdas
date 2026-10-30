import XCTest
import CryptoKit
@testable import ToqdasCore

final class BLEProtocolTests: XCTestCase {
    private func hex(_ text: String) -> Data {
        let chars = Array(text)
        return Data(stride(from: 0, to: chars.count, by: 2).map { UInt8(String(chars[$0...($0 + 1)]), radix: 16)! })
    }

    func testRFC6979P256SHA256SampleAndTampering() throws {
        // RFC 6979 A.2.5, SHA-256, message "sample".
        let key = try BLEProtocol.publicKey(hex("0460FED4BA255A9D31C961EB74C6356D68C049B8923B61FA6CE669622E60F29FB67903FE1008B8BC99A41AE9E95628BC64F2F1B20C2D7E9F5177A3C294D4462299"))
        let signature = hex("EFD48B2AACB6A8FD1140DD9CD45E81D69D2C877B56AAF991C34D0EA84EAF3716F7CB1C942D657C41D436C7A1B6E29F65F3E900DBB9AFF4064DC4AB2F843ACDA8")
        try BLEProtocol.verify(signature: signature, message: Data("sample".utf8), trustedKey: key)
        XCTAssertThrowsError(try BLEProtocol.verify(signature: signature, message: Data("tampered".utf8), trustedKey: key))
        let der = try BLEProtocol.derSignature(fromRaw: signature)
        XCTAssertEqual(try BLEProtocol.rawSignature(fromDER: der), signature)
        XCTAssertThrowsError(try BLEProtocol.rawSignature(fromDER: der + Data([0])))
        XCTAssertThrowsError(try BLEProtocol.derSignature(fromRaw: Data(repeating: 0, count: 64)))
        XCTAssertThrowsError(try BLEProtocol.derSignature(fromRaw: Data(repeating: 255, count: 64)))
    }

    func testCertificateBindsBothVINAndDeviceKey() throws {
        let key = P256.Signing.PrivateKey().publicKey.x963Representation
        let vin = "ABC12345678901234"
        var cert = Data(repeating: 0, count: 247)
        cert.replaceSubrange(17..<34, with: Data(vin.utf8))
        cert.replaceSubrange(54..<119, with: key)
        XCTAssertEqual(try BLEProtocol.boundCertificate(cert, vin: vin, devicePublicKey: key), cert)
        XCTAssertEqual(try BLEProtocol.boundCertificate(BLEProtocol.certificateHeader + cert, vin: vin, devicePublicKey: key), cert)
        XCTAssertThrowsError(try BLEProtocol.boundCertificate(cert, vin: "DEF12345678901234", devicePublicKey: key))
        XCTAssertThrowsError(try BLEProtocol.boundCertificate(cert, vin: vin, devicePublicKey: P256.Signing.PrivateKey().publicKey.x963Representation))
        XCTAssertThrowsError(try BLEProtocol.boundCertificate(cert.dropLast(), vin: vin, devicePublicKey: key))
        XCTAssertThrowsError(try BLEProtocol.boundCertificate(Data(repeating: 0, count: 8) + cert, vin: vin, devicePublicKey: key))
    }

    func testProofRejectsDifferentChallengeKeyAndModifiedPayload() throws {
        let key = P256.Signing.PrivateKey()
        let challenge = Data(0..<10)
        let body = challenge + Data(repeating: 0, count: 6)
        let packet = BLEProtocol.carProofHeader + body + (try key.signature(for: body)).rawRepresentation
        try BLEProtocol.verifyCarProof(packet, expectedChallenge: challenge, trustedKey: key.publicKey)
        XCTAssertThrowsError(try BLEProtocol.verifyCarProof(packet, expectedChallenge: Data(repeating: 9, count: 10), trustedKey: key.publicKey))
        XCTAssertThrowsError(try BLEProtocol.verifyCarProof(packet, expectedChallenge: challenge, trustedKey: P256.Signing.PrivateKey().publicKey))
        var modified = packet
        modified[20] ^= 1
        XCTAssertThrowsError(try BLEProtocol.verifyCarProof(modified, expectedChallenge: challenge, trustedKey: key.publicKey))
        XCTAssertThrowsError(try BLEProtocol.verifyCarProof(packet + Data([0]), expectedChallenge: challenge, trustedKey: key.publicKey))
    }

    func testFramingAndInvalidCurvePoint() throws {
        let key = P256.Signing.PrivateKey().publicKey
        for bytes in [key.x963Representation, Data(key.x963Representation.dropFirst())] {
            let frame = Data([0x21, 1, UInt8(bytes.count), 0, UInt8(bytes.count), 0, 1, 0]) + bytes
            XCTAssertEqual(try BLEProtocol.vehicleKeyFrame(frame).x963Representation, key.x963Representation)
            XCTAssertThrowsError(try BLEProtocol.vehicleKeyFrame(frame.dropLast()))
        }
        XCTAssertThrowsError(try BLEProtocol.publicKey(Data(repeating: 0, count: 64)))
        let challenge = Data(0..<10)
        XCTAssertEqual(try BLEProtocol.challenge(BLEProtocol.challengeHeader + challenge), challenge)
        XCTAssertThrowsError(try BLEProtocol.challenge(BLEProtocol.challengeHeader + challenge + Data([0])))
        for count in 0..<8 { XCTAssertThrowsError(try BLEProtocol.vehicleKeyFrame(Data(repeating: 0, count: count))) }
    }

    func testTelemetryMapsLockDoorsAndPowerState() {
        let base = BleTelemetry(
            locked: 1,
            doors: [0, 1, 0, 1],
            trunkAjar: 0,
            powerState: 4,
            counter: 3,
            receivedAt: Date()
        )
        XCTAssertEqual(base.isLocked, true)
        XCTAssertEqual(base.lockText, "Kilitli")
        XCTAssertTrue(base.hasDoorReadings)
        XCTAssertEqual(base.openDoorCount, 2)
        XCTAssertEqual(base.doorsText, "Kapı 2, Kapı 4 açık")
        XCTAssertEqual(base.isDoorOpen(0), false)
        XCTAssertEqual(base.isDoorOpen(1), true)
        XCTAssertNil(base.isDoorOpen(4))
        XCTAssertEqual(base.powerStateText, "Hazır")

        let unlocked = BleTelemetry(locked: 2, doors: [0, 0, 0, 0], trunkAjar: 0,
                                    powerState: 3, counter: 4, receivedAt: Date())
        XCTAssertEqual(unlocked.isLocked, false)
        XCTAssertEqual(unlocked.lockText, "Kilit açık")
        XCTAssertEqual(unlocked.doorsText, "Tüm kapılar kapalı")
        XCTAssertEqual(unlocked.powerStateText, "Aksesuar")

        let unknown = BleTelemetry(locked: 0, doors: [0, 0], trunkAjar: 0,
                                   powerState: 2, counter: 5, receivedAt: Date())
        XCTAssertNil(unknown.isLocked)
        XCTAssertEqual(unknown.lockText, "Kilit durumu doğrulanıyor")
        XCTAssertFalse(unknown.hasDoorReadings)
        XCTAssertEqual(unknown.doorsText, "Kapı durumu doğrulanıyor")
        XCTAssertEqual(unknown.powerStateText, "Bekleme")

        let unverified = BleTelemetry(locked: 0, doors: [0, 0, 0, 0], trunkAjar: 0,
                                      powerState: 9, counter: 6, receivedAt: Date())
        XCTAssertEqual(unverified.powerStateText, "Durum doğrulanıyor")
    }

    func testSecurityWarningOnlyReportsKnownOpenStateAndParkedUnlockedVehicle() {
        let openDoor = BleTelemetry(
            locked: 1, doors: [0, 1, 0, 0], trunkAjar: 0,
            powerState: 2, counter: 1, receivedAt: Date()
        )
        XCTAssertEqual(openDoor.securityWarning, "Kapı 2 açık")

        let openTrunk = BleTelemetry(
            locked: 1, doors: [0, 0, 0, 0], trunkAjar: 1,
            powerState: 2, counter: 2, receivedAt: Date()
        )
        XCTAssertEqual(openTrunk.securityWarning, "Bagaj açık")

        let parkedUnlocked = BleTelemetry(
            locked: 2, doors: [0, 0, 0, 0], trunkAjar: 0,
            powerState: 2, counter: 3, receivedAt: Date()
        )
        XCTAssertEqual(parkedUnlocked.securityWarning, "Araç beklemede ve kilit açık")

        let accessoryUnlocked = BleTelemetry(
            locked: 2, doors: [0, 0, 0, 0], trunkAjar: 0,
            powerState: 3, counter: 4, receivedAt: Date()
        )
        XCTAssertNil(accessoryUnlocked.securityWarning)

        let unknownLock = BleTelemetry(
            locked: 0, doors: [0, 0, 0, 0], trunkAjar: 0,
            powerState: 2, counter: 5, receivedAt: Date()
        )
        XCTAssertNil(unknownLock.securityWarning)
    }

    func testTelemetryRequiresSignatureOverEntirePayload() throws {
        let key = P256.Signing.PrivateKey()
        let body = Data(0..<21)
        let header = Data([0x26, 1, 85, 0, 85, 0, 1, 0])
        let packet = header + body + (try key.signature(for: body)).rawRepresentation
        XCTAssertEqual(try BLEProtocol.verifiedTelemetryPayload(packet, trustedKey: key.publicKey), body)
        var modified = packet
        modified[28] ^= 1
        XCTAssertThrowsError(try BLEProtocol.verifiedTelemetryPayload(modified, trustedKey: key.publicKey))
        XCTAssertThrowsError(try BLEProtocol.verifiedTelemetryPayload(Data(), trustedKey: key.publicKey))
    }
}

extension BLEProtocolTests {
    /// Android `BleProtocol.kt` ile aynı sabit baytlar. Bu değerler değişirse
    /// araç eski/yeni yazılım uyumluluğu ayrıca doğrulanmalıdır.
    func testWireConstantsMatchAndroid() {
        XCTAssertEqual(BLEProtocol.certificateHeader, Data([0x21, 0x01, 0xef, 0x00, 0xf7, 0x00, 0x02, 0x00]))
        XCTAssertEqual(BLEProtocol.certificateNext, Data([0x21, 0x02, 0x08, 0x00, 0xf7, 0x00, 0x02, 0x00]))
        XCTAssertEqual(BLEProtocol.certificateAck, Data([0x10, 0x01, 0xef, 0x00, 0x02, 0x00, 0x00, 0x00]))
        XCTAssertEqual(BLEProtocol.certificateFrame2Ack, Data([0x10, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]))
        XCTAssertEqual(BLEProtocol.challengeRequest, Data([0x10, 0x02, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00]))
        XCTAssertEqual(BLEProtocol.vehicleKeyRequest, Data([0x10, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00]))
        XCTAssertEqual(BLEProtocol.challengeHeader, Data([0x27, 0x01, 0x0a, 0x00, 0x0a, 0x00, 0x01, 0x00]))
        XCTAssertEqual(BLEProtocol.phoneProofHeader, Data([0x22, 0x01, 0x4a, 0x00, 0x4a, 0x00, 0x01, 0x00]))
        XCTAssertEqual(BLEProtocol.phoneAck, Data([0x11, 0x02, 0x4a, 0x00, 0x01, 0x00, 0x00, 0x00]))
        XCTAssertEqual(BLEProtocol.carProofRequest, Data([0x11, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]))
        XCTAssertEqual(BLEProtocol.carProofHeader, Data([0x22, 0x01, 0x50, 0x00, 0x50, 0x00, 0x01, 0x00]))
        XCTAssertEqual(BLEProtocol.ready, Data([0x11, 0x02, 0x50, 0x00, 0x00, 0x00, 0x00, 0x00]))
        XCTAssertEqual(BLEProtocol.commandNonce, Data([0x13, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00]))
        XCTAssertEqual(BLEProtocol.commandHeader, Data([0x23, 0x01, 0x52, 0x00, 0x52, 0x00, 0x01, 0x00]))
        XCTAssertEqual(BLEProtocol.commandAck, Data([0x12, 0x02, 0x52, 0x00, 0x01, 0x00, 0x00, 0x00]))
    }

    /// Sertifika çerçevelerinin başlık + gövde yerleşimi bayt düzeyinde sabit.
    func testCertificateFramesExactLayout() throws {
        let certificate = Data((0..<247).map { UInt8($0) })
        let frames = try BLEProtocol.certificateFrames(certificate)
        XCTAssertEqual(frames[0].prefix(8), BLEProtocol.certificateHeader)
        XCTAssertEqual(Array(frames[0][8..<12]), [0, 1, 2, 3])
        XCTAssertEqual(frames[0].last, 238)
        XCTAssertEqual(frames[1].prefix(8), BLEProtocol.certificateNext)
        XCTAssertEqual(Array(frames[1].dropFirst(8)), Array(239..<247))
    }

    func testCertificateFramesReassembleExactly() throws {
        let certificate = Data((0..<247).map { UInt8($0 & 0xff) })
        let frames = try BLEProtocol.certificateFrames(certificate)
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0].count, 247)
        XCTAssertEqual(frames[1].count, 16)
        XCTAssertTrue(frames[0].starts(with: BLEProtocol.certificateHeader))
        XCTAssertTrue(frames[1].starts(with: BLEProtocol.certificateNext))
        XCTAssertEqual(Data(frames[0].dropFirst(8)) + Data(frames[1].dropFirst(8)), certificate)
    }

    func testPhoneProofAndCommandFraming() throws {
        let challenge = Data(0..<10)
        XCTAssertEqual(BLEProtocol.commandCode("windowsOpen"), 6)
        XCTAssertEqual(BLEProtocol.commandCode("windowsClose"), 7)
        let signature = Data(repeating: 7, count: 64)
        let proof = try BLEProtocol.phoneProofPacket(challenge: challenge, signature: signature)
        XCTAssertEqual(proof.count, 82)
        XCTAssertTrue(proof.starts(with: BLEProtocol.phoneProofHeader))
        XCTAssertEqual(Data(proof[8..<18]), challenge)

        var parts = DateComponents()
        parts.year = 2026; parts.month = 10; parts.day = 23
        parts.hour = 12; parts.minute = 34; parts.second = 56
        let date = Calendar(identifier: .gregorian).date(from: parts)!
        let key = P256.Signing.PrivateKey()
        let body = try BLEProtocol.commandBody(code: 1, date: date, challenge: challenge)
        let commandSignature = try key.signature(for: body).rawRepresentation
        let command = try BLEProtocol.commandPacket(code: 1, date: date, challenge: challenge, signature: commandSignature)
        XCTAssertEqual(command.count, 90)
        XCTAssertTrue(command.starts(with: BLEProtocol.commandHeader))
        XCTAssertEqual(Array(command[8..<16]), [1, 0x07, 0xea, 10, 23, 12, 34, 56])
        XCTAssertEqual(Data(command[16..<26]), challenge)
        XCTAssertEqual(Data(command[26..<90]), commandSignature)
        try BLEProtocol.verify(signature: commandSignature, message: body, trustedKey: key.publicKey)
        XCTAssertThrowsError(try BLEProtocol.commandPacket(code: 1, date: date, challenge: challenge, signature: Data(repeating: 0, count: 63)))
    }

    func testCarTimeAndOwnerBody() throws {
        let packet = Data([0xea, 0x07, 10, 23, 12, 34, 56])
        let date = BLEProtocol.carTime(packet)
        XCTAssertNotNil(date)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        XCTAssertEqual(calendar.component(.year, from: date!), 2026)

        let key = try BLEProtocol.publicKey(hex("0460FED4BA255A9D31C961EB74C6356D68C049B8923B61FA6CE669622E60F29FB67903FE1008B8BC99A41AE9E95628BC64F2F1B20C2D7E9F5177A3C294D4462299"))
        let body = try BLEProtocol.ownerBody(
            vin: "YH4TESTVN12345678",
            accountUUID: "123e4567-e89b-12d3-a456-426614174000",
            phonePublicKey: key.x963Representation,
            start: Date(),
            end: Date().addingTimeInterval(86_400)
        )
        XCTAssertEqual(body.count, 119)
        XCTAssertEqual(Data(body[1..<17]).hexString, "123e4567e89b12d3a456426614174000")
        XCTAssertEqual(Data(body[17..<34]), Data("YH4TESTVN12345678".utf8))
    }
}
