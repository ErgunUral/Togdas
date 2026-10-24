import Foundation
import Security

struct SessionTokens: Codable {
    let access: String
    let refresh: String?
    let expiresAt: Date
}

struct SessionStore {
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.toqdas.ios.session",
         kSecAttrAccount as String: "togg-id"]
    }

    func load() throws -> SessionTokens? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw AppError.message("Keychain oturumu okunamadı (\(status)).")
        }
        return try JSONDecoder().decode(SessionTokens.self, from: data)
    }

    func save(_ tokens: SessionTokens) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: try JSONEncoder().encode(tokens),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw AppError.message("Oturum kaydedilemedi (\(status)).") }
    }

    func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AppError.message("Oturum silinemedi (\(status)).")
        }
    }
}
