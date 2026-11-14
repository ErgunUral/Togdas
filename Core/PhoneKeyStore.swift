import Foundation
import Security

/// Araç başına P-256 dijital anahtar çifti (Keychain).
/// Özel anahtar cihazdan çıkmaz; yalnızca imza üretmek için kullanılır.
enum PhoneKeyStore {
    private static let tagPrefix = "com.toqdas.ios.ble.key."
    private static let legacyTag = "com.toqdas.ios.ble.phone.key"

    static func keyTag(for vin: String) -> String { tagPrefix + vin }

    /// Anahtarın okunabilirlik durumu. `unavailable` (ör. cihaz kilitli)
    /// ile `missing` (gerçekten yok) ayrılır; ikisi aynı sayılırsa kilitliyken
    /// yeni anahtar üretilip eşleştirme bozulur.
    enum FingerprintStatus: Equatable {
        case found(String)
        case missing
        case unavailable
    }

    static func publicKeyHex(for vin: String) -> String? {
        guard let key = load(tag: keyTag(for: vin)).key,
              let data = publicKeyData(key) else { return nil }
        return data.hexString
    }

    /// Dijital imza kimliğinin kısa parmak izi; anahtar yoksa `nil`.
    /// Tanı karşılaştırması içindir (tam anahtar loglanmaz).
    static func publicKeyFingerprint(for vin: String) -> String? {
        guard case .found(let fingerprint) = fingerprintStatus(for: vin) else { return nil }
        return fingerprint
    }

    static func fingerprintStatus(for vin: String) -> FingerprintStatus {
        let result = load(tag: keyTag(for: vin))
        if let key = result.key {
            // Eski sürümden kalan anahtar kilitliyken okunamıyorsa burada
            // erişilebilirliği yükseltilir; sonuç tanı için saklanır.
            migrateAccessibilityIfNeeded(tag: keyTag(for: vin))
            guard let data = publicKeyData(key) else { return .unavailable }
            return .found(KeyIdentity.fingerprint(data))
        }
        return result.status == errSecItemNotFound ? .missing : .unavailable
    }

    static func keyPair(for vin: String, generate: Bool = true) throws -> (key: SecKey, publicKey: Data) {
        guard vin.range(of: "^[A-HJ-NPR-Z0-9]{17}$", options: .regularExpression) != nil else {
            throw AppError.message("Geçersiz VIN.")
        }
        let loaded = load(tag: keyTag(for: vin))
        if let key = loaded.key {
            guard let data = publicKeyData(key) else {
                // Anahtar var ama açık anahtarı okunamıyor: silip yeniden
                // üretmek eşleşmeyi bozar, bu yüzden üretmiyoruz.
                throw AppError.message("Telefon anahtarı okundu ama açık anahtarı alınamadı. Kilidi açıp yeniden dene.")
            }
            migrateAccessibilityIfNeeded(tag: keyTag(for: vin))
            return (key, data)
        }
        guard generate, Self.canGenerate(for: loaded.status) else {
            throw AppError.message(Self.unavailableMessage(for: loaded.status))
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
                // AfterFirstUnlock: arka plan yakınlık otomasyonu telefon
                // kilitliyken de imza üretebilmeli. WhenUnlocked ile anahtar
                // okunamıyordu ve sessizce yeniden üretiliyordu.
                kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
        ]
        var error: Unmanaged<CFError>?
        KeyAudit.record("generated", detail: "status=\(loaded.status)")
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

    private static func load(tag: String) -> (key: SecKey?, status: OSStatus) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: Data(tag.utf8),
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let item else { return (nil, status) }
        return ((item as! SecKey), status)
    }

    /// Yeni anahtar yalnızca öğe **gerçekten yoksa** üretilir. Kilitli cihaz
    /// (`errSecInteractionNotAllowed`) veya geçici Keychain hatasında üretmek
    /// aracın eşleşmesini bozar.
    static func canGenerate(for status: OSStatus) -> Bool {
        status == errSecItemNotFound
    }

    static func unavailableMessage(for status: OSStatus) -> String {
        if status == errSecInteractionNotAllowed {
            return "Telefon kilitli; dijital anahtar şu an okunamıyor. Kilidi açıp yeniden dene."
        }
        return "Telefonun dijital anahtarı okunamadı (Keychain \(status)). Yeniden eşleştirme gerekebilir."
    }

    /// Eski sürümde `WhenUnlocked` ile üretilmiş anahtarı arka planda
    /// kullanılabilir hale getirmeyi dener; başarısız olursa yalnız günlüğe yazar.
    private static func migrateAccessibilityIfNeeded(tag: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: Data(tag.utf8),
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom
        ]
        let updates: [String: Any] = [
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, updates as CFDictionary)
        // Kalıcı tanı: cihazda kilitliyken anahtar okunabiliyor mu sorusunun
        // yanıtı plist'ten görülebilsin (status 0 = başarılı).
        UserDefaults.standard.set(
            ["status": Int(status), "at": Date().timeIntervalSince1970],
            forKey: "toqdas.key.accessibility.v1"
        )
        if status != errSecSuccess {
            print("[KEY] accessibility migration status=\(status)")
        }
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
