import Foundation

/// Siri Shortcuts / URL şemasından gelen komutlar.
///
/// URL ayrıştırma ve komut eşlemesi tek yerde tutulur; böylece `onOpenURL`
/// içindeki kırılgan string kontrolü test edilebilir hale gelir.
/// Buradaki eşleme yalnızca hangi BLE komutunun çağrılacağını söyler; asıl
/// güvenlik kapısı `BLECommandPolicy` ve `BleConnection.sendCommand` içindedir.
enum ShortcutAction: String, CaseIterable, Equatable {
    case lock
    case unlock
    case trunkOpen
    case trunkClose

    var title: String {
        switch self {
        case .lock: return "Kilitle"
        case .unlock: return "Kilidi aç"
        case .trunkOpen: return "Bagajı aç"
        case .trunkClose: return "Bagajı kapat"
        }
    }

    /// BLE protokolündeki komut kodu (yalnızca teşhis ve politika için).
    var bleCode: UInt8 {
        switch self {
        case .lock: return 7
        case .unlock: return 2
        case .trunkOpen: return 4
        case .trunkClose: return 5
        }
    }
}

enum ShortcutLink {
    static let scheme = "toqdas"
    static let host = "command"

    /// `toqdas://command?action=lock` biçimindeki URL'i komuta çevirir.
    /// Şema, host ve bilinmeyen eylem reddedilir; sessizce yanlış komut çalışmaz.
    static func action(from url: URL) -> ShortcutAction? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        guard url.host?.lowercased() == host else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        guard let raw = components.queryItems?.first(where: { $0.name == "action" })?.value else { return nil }
        return ShortcutAction(rawValue: raw)
    }

    static func url(for action: ShortcutAction) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [URLQueryItem(name: "action", value: action.rawValue)]
        return components.url
    }
}
