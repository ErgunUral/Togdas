import Foundation
import Security

/// Araç başına P-256 dijital anahtar çifti (Keychain).
/// Özel anahtar cihazdan çıkmaz; yalnızca imza üretmek için kullanılır.
enum PhoneKeyStore {
    private static let tagPrefix = "com.toqdas.ios.ble.key."
    private static let legacyTag = "com.toqdas.ios.ble.phone.key"

    static func keyTag(for vin: String) -> String { tagPrefix + vin }

    static func publicKeyHex(for vin: String) -> String? {
        guard let key = load(tag: keyTag(for: vin)), let data = publicKeyData(key) else { return nil }
        return data.hexString
    }

    static func keyPair(for vin: String, generate: Bool = true) throws -> (key: SecKey, publicKey: Data) {
        guard vin.range(of: "^[A-HJ-NPR-Z0-9]{17}$", options: .regularExpression) != nil else {
            throw AppError.message("Geçersiz VIN.")
        }
        if let key = load(tag: keyTag(for: vin)), let data = publicKeyData(key) {
            return (key, data)
        }
        guard generate else {
            throw AppError.message("Bu araç için dijital anahtar henüz oluşturulmadı.")
        }
        try delete(tag: keyTag(for: vin))
        // Eski sürümden kalan tek anahtarı da temizle.
        try? delete(tag: legacyTag)

        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256,
            kSecPrivateKeyAttrs: [
                kSecAttrIsPermanent: true,
                kSecAttrApplicationTag: Data(keyTag(for: vin).utf8),
                kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw AppError.message("Telefon anahtarı oluşturulamadı: \(error?.takeRetainedValue().localizedDescription ?? "bilinmiyor")")
        }
        guard let data = publicKeyData(key) else {
            throw AppError.message("Telefon açık anahtarı okunamadı.")
        }
        return (key, data)
    }

    /// SHA-256 + ECDSA imzası; protokolün beklediği 64 byte R||S biçiminde döner.
    static func sign(_ message: Data, with key: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let der = SecKeyCreateSignature(key, .ecdsaSignatureMessageX962SHA256,
                                              message as CFData, &error) as Data? else {
            throw AppError.message("İmza üretilemedi: \(error?.takeRetainedValue().localizedDescription ?? "bilinmiyor")")
        }
        return try BLEProtocol.rawSignature(fromDER: der)
    }

    static func normalizedPublicKey(_ raw: Data) -> Data? {
        switch raw.count {
        case 65: return raw.first == 0x04 ? raw : nil
        case 64: return Data([0x04]) + raw
        default: return nil
        }
    }

    // MARK: - Keychain

    private static func publicKeyData(_ key: SecKey) -> Data? {
        guard let pub = SecKeyCopyPublicKey(key) else { return nil }
        var error: Unmanaged<CFError>?
        guard let raw = SecKeyCopyExternalRepresentation(pub, &error) as Data? else { return nil }
        return normalizedPublicKey(raw)
    }

    private static func load(tag: String) -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: Data(tag.utf8),
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let key = item else { return nil }
        return (key as! SecKey)
    }

    private static func delete(tag: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: Data(tag.utf8),
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError.message("Eski anahtar silinemedi (\(status)).")
        }
    }
}

extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}

extension String {
    var withoutDashes: String { replacingOccurrences(of: "-", with: "") }
}
