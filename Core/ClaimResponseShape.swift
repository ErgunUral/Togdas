import Foundation

/// "Araç başka bir telefon anahtarına bağlı" yanıtının **şekil** kaydı.
///
/// Neden gerekli: sunucunun sahiplik çakışması yanıtından yalnız `resultEnum`
/// okunuyor; başka bir telefonun kimliği gelip gelmediği bilinmiyordu.
/// Bu tip yanıtın anahtar adlarını, tiplerini ve uzunluklarını kaydeder —
/// **değerleri asla**. Böylece bir sonraki saha olayında hangi alanın
/// (ör. maskeli e-posta, cihaz adı, tarih) mevcut olduğu plist'ten görülür.
///
/// Kasıtlı sınırlar:
/// - Değer yazılmaz; e-posta/telefon/cihaz adı gibi kişisel veri sızmaz.
/// - Derinlik ve alan sayısı sınırlı; büyük yanıtlar kırpılır.
/// - Yalnız tanı amaçlıdır; uyarı metnini veya akışı değiştirmez.
enum ClaimResponseShape {
    struct Entry: Codable, Equatable {
        let at: TimeInterval
        let shape: String
    }

    static let storageKey = "toqdas.claim.shape.v1"
    static let maxFields = 24
    static let maxDepth = 3

    /// `{"ownerEmail":"a@b.com","relations":[{"device":"iPhone"}]}`
    /// → `ownerEmail:string(7); relations:array(1)`
    static func describe(_ data: Data) -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data,
                                                           options: [.fragmentsAllowed]) else {
            return "geçersiz"
        }
        guard let object = root as? [String: Any] else {
            if let array = root as? [Any] { return "root:array(\(array.count))" }
            return "root:\(typeName(root))"
        }
        var parts: [String] = []
        collect(object, prefix: nil, depth: 0, into: &parts)
        return parts.isEmpty ? "boş" : parts.joined(separator: "; ")
    }

    static func save(_ shape: String, at: Date = Date(), defaults: UserDefaults = .standard) {
        let entry = Entry(at: at.timeIntervalSince1970, shape: String(shape.prefix(400)))
        guard let data = try? JSONEncoder().encode(entry) else { return }
        defaults.set(data, forKey: storageKey)
    }

    static func load(defaults: UserDefaults = .standard) -> Entry? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(Entry.self, from: data)
    }

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
    }

    private static func collect(_ object: [String: Any], prefix: String?,
                                depth: Int, into parts: inout [String]) {
        for key in object.keys.sorted() {
            guard parts.count < maxFields else { return }
            let value = object[key]!
            let name = prefix.map { "\($0).\(key)" } ?? key
            if let nested = value as? [String: Any], depth < maxDepth {
                collect(nested, prefix: name, depth: depth + 1, into: &parts)
            } else if let array = value as? [Any] {
                parts.append("\(name):array(\(array.count))")
                if depth < maxDepth, let first = array.first as? [String: Any] {
                    collect(first, prefix: "\(name)[]", depth: depth + 1, into: &parts)
                }
            } else {
                parts.append("\(name):\(typeName(value))")
            }
        }
    }

    /// Değerin kendisi değil, tipi ve (metinse) uzunluğu yazılır.
    private static func typeName(_ value: Any) -> String {
        switch value {
        case is String: return "string(\((value as? String)?.count ?? 0))"
        case is Bool: return "bool"
        case is NSNumber: return "number"
        case is NSNull: return "null"
        case is [String: Any]: return "object"
        case is [Any]: return "array"
        default: return "bilinmiyor"
        }
    }
}
