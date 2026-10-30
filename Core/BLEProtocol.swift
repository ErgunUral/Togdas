import Foundation
import CryptoKit
import Security

/// Wire-format checks ported from Garajm/BleProtocol.kt.
/// Bu katman anahtar güvenini kendi başına kurmaz; araç anahtarı ayrıca sabitlenmelidir.
enum BLEProtocol {
    static let certificateHeader = Data([0x21, 0x01, 0xef, 0x00, 0xf7, 0x00, 0x02, 0x00])
    static let certificateNext = Data([0x21, 0x02, 0x08, 0x00, 0xf7, 0x00, 0x02, 0x00])
    static let certificateAck = Data([0x10, 0x01, 0xef, 0x00, 0x02, 0x00, 0x00, 0x00])
    static let certificateFrame2Ack = Data([0x10, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    static let challengeRequest = Data([0x10, 0x02, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00])
    static let vehicleKeyRequest = Data([0x10, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00])
    static let challengeHeader = Data([0x27, 0x01, 0x0a, 0x00, 0x0a, 0x00, 0x01, 0x00])
    static let phoneProofHeader = Data([0x22, 0x01, 0x4a, 0x00, 0x4a, 0x00, 0x01, 0x00])
    static let phoneAck = Data([0x11, 0x02, 0x4a, 0x00, 0x01, 0x00, 0x00, 0x00])
    static let carProofRequest = Data([0x11, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    static let carProofHeader = Data([0x22, 0x01, 0x50, 0x00, 0x50, 0x00, 0x01, 0x00])
    static let ready = Data([0x11, 0x02, 0x50, 0x00, 0x00, 0x00, 0x00, 0x00])
    static let commandNonce = Data([0x13, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00])
    static let commandHeader = Data([0x23, 0x01, 0x52, 0x00, 0x52, 0x00, 0x01, 0x00])
    static let commandAck = Data([0x12, 0x02, 0x52, 0x00, 0x01, 0x00, 0x00, 0x00])

    enum Failure: Error, Equatable {
        case malformedPacket, invalidVIN, certificateMismatch, invalidKey, invalidSignature, challengeMismatch
    }

    /// Sertifika kaydını protokolün beklediği 247 + 8 byte'lık iki çerçeveye böler.
    static func certificateFrames(_ certificate: Data) throws -> [Data] {
        guard certificate.count == 247 else { throw Failure.malformedPacket }
        return [
            certificateHeader + certificate.prefix(239),
            certificateNext + certificate.suffix(8)
        ]
    }

    /// Telefon imzası: 8 byte başlık + 10 byte challenge + 64 byte ham imza.
    static func phoneProofPacket(challenge: Data, signature: Data) throws -> Data {
        guard challenge.count == 10, signature.count == 64 else { throw Failure.malformedPacket }
        return phoneProofHeader + challenge + signature
    }

    /// İmzalanacak komut gövdesi: kod + araç saati + tek kullanımlık 10 byte nonce.
    static func commandBody(code: UInt8, date: Date, challenge: Data) throws -> Data {
        guard challenge.count == 10 else { throw Failure.challengeMismatch }
        let parts = Calendar(identifier: .gregorian).dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: date
        )
        guard let year = parts.year, (1583...9999).contains(year),
              let month = parts.month, let day = parts.day,
              let hour = parts.hour, let minute = parts.minute, let second = parts.second else {
            throw Failure.malformedPacket
        }
        var body = Data([
            code,
            UInt8((year >> 8) & 0xff), UInt8(year & 0xff),
            UInt8(month), UInt8(day), UInt8(hour), UInt8(minute), UInt8(second)
        ])
        body += challenge
        return body
    }

    /// Yetkili komut: 8 byte başlık + 18 byte gövde + 64 byte P-256 imzası.
    static func commandPacket(code: UInt8, date: Date, challenge: Data, signature: Data) throws -> Data {
        guard signature.count == 64 else { throw Failure.malformedPacket }
        let body = try commandBody(code: code, date: date, challenge: challenge)
        return commandHeader + body + signature
    }

    static func commandCode(_ action: String) -> UInt8? {
        switch action {
        case "lock": return 1
        case "unlock": return 2
        case "trunkOpen": return 4
        case "trunkClose": return 5
        case "windowsOpen": return 6
        case "windowsClose": return 7
        case "driveAuthorize": return 14
        default: return nil
        }
    }

    /// Resmî uygulama 8 byte'tan uzun ve 0x21 ile başlayan paketi araç anahtarı
    /// yanıtı olarak kabul eder; gövde 64 veya 65 byte olmalıdır.
    static func isVehicleKeyFrame(_ packet: Data) -> Bool {
        packet.count > 8 && packet.first == 0x21
    }

    static func isChallenge(_ packet: Data) -> Bool {
        packet.count == 18 && packet.starts(with: challengeHeader)
    }

    static func isPhoneAck(_ packet: Data) -> Bool { packet.starts(with: phoneAck) }
    static func isCommandAck(_ packet: Data) -> Bool { packet.starts(with: commandAck) }
    static func isReady(_ packet: Data) -> Bool { packet.starts(with: ready) }

    /// Sertifika gövdesindeki bitiş zamanı (UTC). 247 byte'lık tam sertifika beklenir.
    static func certificateEndDate(_ certificate: Data) -> Date? {
        guard certificate.count >= 46 else { return nil }
        let b = [UInt8](certificate)
        let year = Int(b[44]) | (Int(b[45]) << 8)
        guard (1583...9999).contains(year) else { return nil }
        var parts = DateComponents()
        parts.year = year
        parts.month = Int(b[43])
        parts.day = Int(b[42])
        parts.hour = Int(b[41])
        parts.minute = Int(b[40])
        parts.timeZone = TimeZone(secondsFromGMT: 0)!
        return Calendar(identifier: .gregorian).date(from: parts)
    }

    /// Araç saati: 7 veya 10 byte. Yıl little-endian.
    static func carTime(_ packet: Data) -> Date? {
        guard packet.count == 7 || packet.count == 10 else { return nil }
        let bytes = [UInt8](packet)
        let year = Int(bytes[0]) | (Int(bytes[1]) << 8)
        guard (1583...9999).contains(year) else { return nil }
        var parts = DateComponents()
        parts.year = year
        parts.month = Int(bytes[2])
        parts.day = Int(bytes[3])
        parts.hour = Int(bytes[4])
        parts.minute = Int(bytes[5])
        parts.second = Int(bytes[6])
        parts.timeZone = TimeZone.current
        return Calendar(identifier: .gregorian).date(from: parts)
    }

    /// Sunucuya gönderilecek sahip sertifikası gövdesi (119 byte).
    static func ownerBody(vin: String, accountUUID: String, phonePublicKey: Data,
                          start: Date, end: Date) throws -> Data {
        guard vin.range(of: "^[A-HJ-NPR-Z0-9]{17}$", options: .regularExpression) != nil else {
            throw Failure.invalidVIN
        }
        guard accountUUID.range(of: "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", options: .regularExpression) != nil else {
            throw Failure.invalidVIN
        }
        let key = try publicKey(phonePublicKey)
        guard end > start else { throw Failure.malformedPacket }
        func stamp(_ date: Date) -> Data {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            return Data([
                UInt8(c.minute ?? 0), UInt8(c.hour ?? 0), UInt8(c.day ?? 0),
                UInt8(c.month ?? 0), UInt8((c.year ?? 0) & 0xff), UInt8(((c.year ?? 0) >> 8) & 0xff)
            ])
        }
        var body = Data([1])
        body += Data(hexBytes: accountUUID.replacingOccurrences(of: "-", with: "")) ?? Data()
        body += Data(vin.utf8)
        body += stamp(start)
        body += stamp(end)
        body += Data([1, 1, 1, 1, 1, 0, 0, 0])
        body += key.x963Representation
        guard body.count == 119 else { throw Failure.malformedPacket }
        return body
    }

    /// Validates structure and binding only, not issuer signature or certificate expiry.
    static func boundCertificate(_ packet: Data, vin: String, devicePublicKey: Data) throws -> Data {
        guard vin.range(of: "^[A-HJ-NPR-Z0-9]{17}$", options: .regularExpression) != nil else {
            throw Failure.invalidVIN
        }
        let certificate: Data
        if packet.count == 255, packet.starts(with: certificateHeader) {
            certificate = Data(packet.dropFirst(8))
        } else if packet.count == 247 {
            certificate = Data(packet)
        } else { throw Failure.malformedPacket }
        guard certificate.subdata(in: 17..<34) == Data(vin.utf8) else { throw Failure.certificateMismatch }
        guard devicePublicKey.count == 65 else { throw Failure.invalidKey }
        _ = try publicKey(devicePublicKey)
        guard certificate.subdata(in: 54..<119) == devicePublicKey else { throw Failure.certificateMismatch }
        return certificate
    }

    /// Returns a parsed key, not an authenticated or pinned identity.
    static func publicKey(_ bytes: Data) throws -> P256.Signing.PublicKey {
        let normalized: Data
        switch bytes.count {
        case 64: normalized = Data([0x04]) + bytes
        case 65:
            guard bytes.first == 0x04 else { throw Failure.invalidKey }
            normalized = Data(bytes)
        default: throw Failure.invalidKey
        }
        do { return try P256.Signing.PublicKey(x963Representation: normalized) }
        catch { throw Failure.invalidKey }
    }

    static func vehicleKeyFrame(_ packet: Data) throws -> P256.Signing.PublicKey {
        let bytes = [UInt8](packet)
        guard bytes.count == 72 || bytes.count == 73 else { throw Failure.malformedPacket }
        let length = UInt8(bytes.count - 8)
        guard Array(bytes.prefix(8)) == [0x21, 0x01, length, 0, length, 0, 1, 0] else {
            throw Failure.malformedPacket
        }
        return try publicKey(Data(bytes.dropFirst(8)))
    }

    static func challenge(_ packet: Data) throws -> Data {
        guard packet.count == 18, packet.starts(with: challengeHeader) else { throw Failure.malformedPacket }
        return Data(packet.dropFirst(8))
    }

    static func rawSignature(fromDER data: Data) throws -> Data {
        do {
            let signature = try P256.Signing.ECDSASignature(derRepresentation: data)
            // Reject trailing bytes and noncanonical DER encodings.
            guard signature.derRepresentation == data else { throw Failure.invalidSignature }
            try validateScalars(signature.rawRepresentation)
            return signature.rawRepresentation
        } catch { throw Failure.invalidSignature }
    }

    static func derSignature(fromRaw data: Data) throws -> Data {
        try validateScalars(data)
        do { return try P256.Signing.ECDSASignature(rawRepresentation: data).derRepresentation }
        catch { throw Failure.invalidSignature }
    }

    private static func validateScalars(_ data: Data) throws {
        let order: [UInt8] = [
            0xff,0xff,0xff,0xff,0x00,0x00,0x00,0x00,0xff,0xff,0xff,0xff,0xff,0xff,0xff,0xff,
            0xbc,0xe6,0xfa,0xad,0xa7,0x17,0x9e,0x84,0xf3,0xb9,0xca,0xc2,0xfc,0x63,0x25,0x51
        ]
        guard data.count == 64 else { throw Failure.invalidSignature }
        let bytes = [UInt8](data)
        for offset in [0, 32] {
            let scalar = Array(bytes[offset..<(offset + 32)])
            guard scalar.contains(where: { $0 != 0 }), scalar.lexicographicallyPrecedes(order) else {
                throw Failure.invalidSignature
            }
        }
    }

    static func verify(signature: Data, message: Data, trustedKey: P256.Signing.PublicKey) throws {
        try validateScalars(signature)
        let parsed = try P256.Signing.ECDSASignature(rawRepresentation: signature)
        guard trustedKey.isValidSignature(parsed, for: message) else { throw Failure.invalidSignature }
    }

    /// Caller supplies a fresh locally generated challenge and independently trusted vehicle key.
    static func verifyCarProof(_ packet: Data, expectedChallenge: Data, trustedKey: P256.Signing.PublicKey) throws {
        guard packet.count == 88, packet.starts(with: carProofHeader), expectedChallenge.count == 10 else {
            throw Failure.malformedPacket
        }
        let normalized = Data(packet)
        guard normalized.subdata(in: 8..<18) == expectedChallenge else { throw Failure.challengeMismatch }
        try verify(signature: normalized.subdata(in: 24..<88), message: normalized.subdata(in: 8..<24), trustedKey: trustedKey)
    }

    /// Authenticated bytes only. Freshness and field semantics belong to the session layer.
    static func verifiedTelemetryPayload(_ packet: Data, trustedKey: P256.Signing.PublicKey) throws -> Data {
        let bytes = [UInt8](packet)
        guard bytes.count == 93, bytes[0] == 0x26, bytes[2] == 85, bytes[3] == 0,
              bytes[4] == 85, bytes[5] == 0 else { throw Failure.malformedPacket }
        let payload = Data(bytes[8..<29])
        try verify(signature: Data(bytes[29..<93]), message: payload, trustedKey: trustedKey)
        return payload
    }
}

extension Data {
    init?(hexBytes string: String) {
        guard string.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(string.count / 2)
        var index = string.startIndex
        while index < string.endIndex {
            let next = string.index(index, offsetBy: 2)
            guard let value = UInt8(string[index..<next], radix: 16) else { return nil }
            bytes.append(value)
            index = next
        }
        self.init(bytes)
    }
}

/// Sunucudan alınan sertifikayı ve aracın açık anahtarını **Keychain**'de saklar.
///
/// Keychain seçildi çünkü `UserDefaults` uygulama silinince temizleniyordu; her
/// yeniden kurulumda araç anahtarı kayboluyor ve araç el sıkışmayı 7 sn sonra
/// kapatıyordu. Bu önbellek cihazda kalır, iCloud'a taşınmaz.
enum CertificateCache {
    private static let legacyPrefix = "com.toqdas.ios.certificate.v1."
    private static let service = "com.toqdas.ios.certificate.v2"


    static func loadCertificate(vin: String, phonePublicKeyHex: String) -> (certificateBase64: String, carPublicKey: String)? {
        guard let payload = readPayload(vin: vin) ?? migrateLegacy(vin: vin),
              let certificate = payload["certificate"] as? String, !certificate.isEmpty else {
            return nil
        }
        let carPublicKey = payload["carPublicKey"] as? String ?? ""
        guard isValid(certificateBase64: certificate, vin: vin, phonePublicKeyHex: phonePublicKeyHex) else {
            print("[CERT] cached certificate invalid; removing vin=…\(vin.suffix(4))")
            deletePayload(vin: vin)
            UserDefaults.standard.removeObject(forKey: legacyPrefix + vin)
            return nil
        }
        return (certificate, carPublicKey)
    }

    /// Önbellekteki sertifikanın yaşam döngüsünü döndürür. Süresi dolmuş
    /// sertifika da raporlanır; silme kararı `loadCertificate` içinde verilir.
    static func cachedLifecycle(vin: String, phonePublicKeyHex: String) -> CertificateLifecycle? {
        guard let payload = readPayload(vin: vin) ?? migrateLegacy(vin: vin),
              let certificate = payload["certificate"] as? String,
              let data = Data(base64Encoded: certificate),
              data.count == 247,
              let phoneKey = try? BLEProtocol.publicKey(Data(hexBytes: phonePublicKeyHex) ?? Data()),
              let bound = try? BLEProtocol.boundCertificate(
                data, vin: vin, devicePublicKey: phoneKey.x963Representation),
              let end = BLEProtocol.certificateEndDate(bound) else {
            return nil
        }
        return CertificateLifecycle(expiresAt: end)
    }

    static func save(certificateBase64: String, carPublicKey: String, vin: String, phonePublicKeyHex: String) {
        guard isValid(certificateBase64: certificateBase64, vin: vin, phonePublicKeyHex: phonePublicKeyHex) else { return }
        // Sunucu yanıtlarında araç anahtarı boş gelebiliyor. Boş değerle
        // yazmak daha önce araçtan alınmış geçerli anahtarı siliyordu; bu yüzden
        // boş anahtar geldiğinde mevcut anahtar korunur.
        var resolvedCarKey = carPublicKey
        if resolvedCarKey.isEmpty,
           let existing = readPayload(vin: vin),
           let previous = existing["carPublicKey"] as? String,
           !previous.isEmpty {
            resolvedCarKey = previous
            print("[CERT] empty vehicle key ignored; keeping cached key")
        }
        writePayload(["certificate": certificateBase64, "carPublicKey": resolvedCarKey], vin: vin)
        UserDefaults.standard.removeObject(forKey: legacyPrefix + vin)
        print("[CERT] certificate cached (keychain) vin=…\(vin.suffix(4)) carKeyPresent=\(!resolvedCarKey.isEmpty)")
    }

    static func updateCarKey(vin: String, phonePublicKeyHex: String, carKey: String) {
        guard !carKey.isEmpty,
              let existing = loadCertificate(vin: vin, phonePublicKeyHex: phonePublicKeyHex) else { return }
        save(
            certificateBase64: existing.certificateBase64,
            carPublicKey: carKey,
            vin: vin,
            phonePublicKeyHex: phonePublicKeyHex
        )
    }

    // MARK: - Keychain

    private static func readPayload(vin: String) -> [String: Any]? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: vin,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return payload
    }

    private static func writePayload(_ payload: [String: Any], vin: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        deletePayload(vin: vin)
        let attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: vin,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            print("[CERT] keychain save failed: \(status)")
        }
    }

    private static func deletePayload(vin: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: vin
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Eski sürümün `UserDefaults` önbelleğini Keychain'e taşır.
    private static func migrateLegacy(vin: String) -> [String: Any]? {
        guard let dictionary = UserDefaults.standard.dictionary(forKey: legacyPrefix + vin),
              let certificate = dictionary["certificate"] as? String, !certificate.isEmpty else {
            return nil
        }
        let payload: [String: Any] = [
            "certificate": certificate,
            "carPublicKey": dictionary["carPublicKey"] as? String ?? ""
        ]
        writePayload(payload, vin: vin)
        UserDefaults.standard.removeObject(forKey: legacyPrefix + vin)
        print("[CERT] legacy cache migrated to keychain vin=…\(vin.suffix(4))")
        return payload
    }

    /// Hata ayıklama: `-seedCertificate <base64>` ile cihazdaki mevcut
    /// sertifikayı önbelleğe alır. VIN ve telefon anahtarı sertifikadan doğrulanır.
    static func seed(base64: String) {
        guard let data = Data(base64Encoded: base64), data.count == 247,
              let vin = String(data: data[17..<34], encoding: .utf8),
              let phonePublicKeyHex = PhoneKeyStore.publicKeyHex(for: vin) else {
            print("[CERT] seed failed: malformed certificate")
            return
        }
        guard isValid(certificateBase64: base64, vin: vin, phonePublicKeyHex: phonePublicKeyHex) else {
            print("[CERT] seed failed: certificate does not match phone key or is expired")
            return
        }
        save(certificateBase64: base64, carPublicKey: "", vin: vin, phonePublicKeyHex: phonePublicKeyHex)
        print("[CERT] seeded certificate for vin=…\(vin.suffix(4))")
    }

    private static func isValid(certificateBase64: String, vin: String, phonePublicKeyHex: String) -> Bool {
        guard let data = Data(base64Encoded: certificateBase64),
              data.count == 247,
              let phoneKey = try? BLEProtocol.publicKey(Data(hexBytes: phonePublicKeyHex) ?? Data()),
              let certificate = try? BLEProtocol.boundCertificate(
                data, vin: vin, devicePublicKey: phoneKey.x963Representation),
              let end = BLEProtocol.certificateEndDate(certificate) else {
            return false
        }
        // 24 saatten az kalan sertifika da kullanılabilir; yenileme kararı
        // `CertificateLifecycle` tarafından verilir.
        return CertificateLifecycle(expiresAt: end).isUsable
    }
}
