import CryptoKit
import Foundation

struct KeySharingInvitation: Equatable {
    let sessionID: String
    let nonce: String

    enum ParseError: LocalizedError, Equatable {
        case invalidURL
        case invalidSession
        case invalidAccount
        case invalidPhoneKey

        var errorDescription: String? {
            switch self {
            case .invalidURL: "Geçerli bir Togg KeySharing davet bağlantısı girin."
            case .invalidSession: "Davet bağlantısının oturum bilgisi geçersiz."
            case .invalidAccount: "Togg ID hesap kimliği okunamadı."
            case .invalidPhoneKey: "Telefon açık anahtarı geçersiz."
            }
        }
    }

    static func parse(_ rawURL: String) throws -> KeySharingInvitation {
        let input = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: input),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              isAllowedHost(host),
              components.path == "/KeySharing",
              components.user == nil, components.password == nil,
              components.port == nil, components.fragment == nil else {
            throw ParseError.invalidURL
        }

        let items = components.queryItems ?? []
        let sessionValues = items.filter { $0.name == "seId" }.compactMap(\.value)
        let nonceValues = items.filter { $0.name == "no" }.compactMap(\.value)
        guard sessionValues.count == 1, nonceValues.count == 1,
              items.filter({ $0.name == "seId" }).count == 1,
              items.filter({ $0.name == "no" }).count == 1,
              isEightByteBase64URL(sessionValues[0]), isEightByteBase64URL(nonceValues[0]) else {
            throw ParseError.invalidSession
        }
        return KeySharingInvitation(sessionID: sessionValues[0], nonce: nonceValues[0])
    }

    /// Android'in imzaladığı bayt dizisi: seId + UUID(16B) + X9.63 P-256 anahtar + no.
    func signatureMessage(accountUUID: String, phonePublicKey: Data) throws -> Data {
        guard let accountBytes = Self.uuidBytes(accountUUID) else { throw ParseError.invalidAccount }
        guard phonePublicKey.count == 65, phonePublicKey.first == 0x04,
              (try? BLEProtocol.publicKey(phonePublicKey)) != nil else { throw ParseError.invalidPhoneKey }
        guard let sessionBytes = Self.decodeBase64URL(sessionID),
              let nonceBytes = Self.decodeBase64URL(nonce),
              sessionBytes.count == 6, nonceBytes.count == 6 else { throw ParseError.invalidSession }
        return sessionBytes + accountBytes + phonePublicKey + nonceBytes
    }

    var replayFingerprint: String {
        let digest = SHA256.hash(data: Data(sessionID.utf8))
        return Data(digest).map { String(format: "%02x", $0) }.joined()
    }

    private static func isAllowedHost(_ host: String) -> Bool {
        ["togg.cloud", "togg.com.tr", "trumore.com.tr"].contains { domain in
            host == domain || host.hasSuffix(".\(domain)")
        }
    }

    private static func isEightByteBase64URL(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9_-]{8}$", options: .regularExpression) != nil
            && decodeBase64URL(value)?.count == 6
    }

    private static func decodeBase64URL(_ value: String) -> Data? {
        var base64 = value.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        return Data(base64Encoded: base64)
    }

    private static func uuidBytes(_ value: String) -> Data? {
        guard value.range(
            of: "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$",
            options: .regularExpression
        ) != nil else { return nil }
        let hex = value.replacingOccurrences(of: "-", with: "")
        var bytes = Data()
        bytes.reserveCapacity(16)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }
}

/// Davet yeniden oynatımını engeller. Ham seId/no değerleri kalıcı saklanmaz;
/// yalnızca seId SHA-256 parmak izi ve istek zamanı tutulur.
enum SharedKeyRequestStore {
    private static let prefix = "toqdas.keyshare.request.v1."

    static func wasRequested(vin: String, fingerprint: String) -> Bool {
        guard let value = UserDefaults.standard.dictionary(forKey: prefix + vin) else { return false }
        let fingerprints = value["fingerprints"] as? [String] ?? []
        return fingerprints.contains(fingerprint) || value["fingerprint"] as? String == fingerprint
    }

    static func markRequested(vin: String, fingerprint: String, at date: Date = Date()) {
        var value = UserDefaults.standard.dictionary(forKey: prefix + vin) ?? [:]
        var fingerprints = value["fingerprints"] as? [String] ?? []
        if !fingerprints.contains(fingerprint) { fingerprints.append(fingerprint) }
        if fingerprints.count > 50 { fingerprints.removeFirst(fingerprints.count - 50) }
        value["fingerprints"] = fingerprints
        value["fingerprint"] = fingerprint // Eski sürümle uyumluluk.
        value["requestedAt"] = date
        value["status"] = "awaitingOwner"
        UserDefaults.standard.set(value, forKey: prefix + vin)
    }

    /// Yalnızca gerçekten paylaşılan anahtar akışı başlatılmışsa true döner.
    /// Sertifika kontrolü veya parmak izi kontrolü için oluşturulan geçici
    /// kayıtlar bu koşulu sağlamaz; aksi halde sahip araçları paylaşılmış
    /// gibi ele alınır ve sertifika akışı başarısız olur.
    static func isSharedOrPending(vin: String) -> Bool {
        guard let value = UserDefaults.standard.dictionary(forKey: prefix + vin) else { return false }
        // Eski sürümler sertifika kontrolü sırasında geçici kayıt oluşturabiliyordu.
        // Böyle kayıtlar sahiplik paylaşımı değildir; temizle.
        if value["fingerprints"] == nil && value["fingerprint"] == nil
            && value["status"] != nil && value["status"] as? String != "awaitingOwner"
            && value["status"] as? String != "certificateAvailable" {
            UserDefaults.standard.removeObject(forKey: prefix + vin)
            return false
        }
        if value["fingerprints"] != nil || value["fingerprint"] != nil { return true }
        return value["status"] as? String == "awaitingOwner"
            || value["status"] as? String == "certificateAvailable"
    }

    /// Test veya hata ayıklama için paylaşılan anahtar durumunu temizler.
    static func clearSharingState(vin: String) {
        UserDefaults.standard.removeObject(forKey: prefix + vin)
    }

    /// Eski sürümlerden kalan geçici paylaşılan anahtar kayıtlarını temizler.
    /// Paylaşım daveti hiç kabul edilmemişse (parmak izi yok) kayıt silinir.
    static func cleanupStaleState(vin: String) {
        guard let value = UserDefaults.standard.dictionary(forKey: prefix + vin) else { return }
        let hasFingerprint = value["fingerprints"] != nil || value["fingerprint"] != nil
        let status = value["status"] as? String
        let isRealSharing = hasFingerprint || status == "awaitingOwner" || status == "certificateAvailable"
        if !isRealSharing {
            UserDefaults.standard.removeObject(forKey: prefix + vin)
        }
    }

    static func canCheckCertificate(vin: String, now: Date = Date()) -> Bool {
        guard let last = UserDefaults.standard.dictionary(forKey: prefix + vin)?["certificateCheckAt"] as? Date else {
            return true
        }
        return now.timeIntervalSince(last) >= 60
    }

    static func markCertificateCheck(vin: String, at date: Date = Date()) {
        // Yalnızca paylaşılan anahtar akışı zaten başlatılmışsa güncelle;
        // aksi halde sahip araçlar paylaşılmış sayılır.
        guard let value = UserDefaults.standard.dictionary(forKey: prefix + vin) else { return }
        var updated = value
        updated["certificateCheckAt"] = date
        UserDefaults.standard.set(updated, forKey: prefix + vin)
    }

    static func hasCertificate(vin: String) -> Bool {
        UserDefaults.standard.dictionary(forKey: prefix + vin)?["status"] as? String == "certificateAvailable"
    }

    static func markCertificateAvailable(vin: String) {
        var value = UserDefaults.standard.dictionary(forKey: prefix + vin) ?? [:]
        value["status"] = "certificateAvailable"
        value["certificateReadAt"] = Date()
        UserDefaults.standard.set(value, forKey: prefix + vin)
    }
}
