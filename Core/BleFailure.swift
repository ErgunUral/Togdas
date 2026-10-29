import Foundation
import CoreBluetooth

/// BLE hata sınıflandırması.
///
/// Android 1.0.24.42'deki GATT tanı gruplarının iOS karşılığı: kullanıcıya tek
/// satır özet, teşhis ekranına ayrıntı. Amaç, aynı hatanın farklı CBError
/// kodlarıyla tekrar tekrar farklı metinler üretmesini engellemek.
enum BleFailureKind: String, CaseIterable {
    /// Sinyal zayıf / bağlantı zaman aşımı.
    case signal
    /// Araç oturumu kendisi kapattı (60 sn kuralı vb.).
    case peerClosed
    /// Eşleşme bilgisi geçersiz: yeniden eşleştirme gerekir.
    case pairingLost
    /// Bluetooth kapalı veya izin yok.
    case radioOff
    /// Servis/karakteristik keşfi başarısız.
    case serviceDiscovery
    /// Veri kanalı kurulamadı (GATT).
    case gatt
    /// Araç başka bir bağlantıyla meşgul.
    case busy
    case unknown

    /// Panoda gösterilen tek satır.
    var summary: String {
        switch self {
        case .signal: "Sinyal zayıf · bağlantı koptu"
        case .peerClosed: "Araç bağlantıyı kapattı"
        case .pairingLost: "Eşleşme geçersiz · yeniden eşleştirme gerekli"
        case .radioOff: "Bluetooth kapalı"
        case .serviceDiscovery: "Araç servisleri bulunamadı"
        case .gatt: "Araçla veri kanalı kurulamadı"
        case .busy: "Araç başka bağlantıyla meşgul"
        case .unknown: "Bağlantı kesildi"
        }
    }

    /// Teşhis kaydındaki ayrıntı.
    var detail: String {
        switch self {
        case .signal: "connection_timeout · sinyal zayıf veya araç yanıt vermiyor"
        case .peerClosed: "peripheral_disconnected · araç oturumu kapattı"
        case .pairingLost: "pairing_lost · eşleşme bilgisi geçersiz"
        case .radioOff: "radio_off · Bluetooth kapalı veya izin yok"
        case .serviceDiscovery: "service_discovery · servis/karakteristik bulunamadı"
        case .gatt: "gatt_error · veri kanalı hatası"
        case .busy: "connection_limit · araç meşgul"
        case .unknown: "unknown · sınıflandırılamayan hata"
        }
    }

    /// Kullanıcının sistem ayarlarına gitmesini gerektiren tek durum.
    var requiresRepair: Bool { self == .pairingLost }
}

enum BleFailureClassifier {
    static func classify(_ error: Error?) -> BleFailureKind {
        guard let error = error as NSError? else { return .peerClosed }
        return classify(domain: error.domain, code: error.code)
    }

    static func classify(domain: String, code: Int) -> BleFailureKind {
        switch domain {
        case CBErrorDomain:
            guard let code = CBError.Code(rawValue: code) else { return .unknown }
            switch code {
            case .connectionTimeout, .connectionFailed:
                return .signal
            case .peripheralDisconnected:
                return .peerClosed
            case .connectionLimitReached:
                return .busy
            case .peerRemovedPairingInformation, .encryptionTimedOut:
                return .pairingLost
            default:
                return .unknown
            }
        case CBATTErrorDomain:
            guard let code = CBATTError.Code(rawValue: code) else { return .gatt }
            switch code {
            case .insufficientAuthentication, .insufficientEncryption,
                 .insufficientAuthorization, .insufficientResources:
                return .pairingLost
            default:
                return .gatt
            }
        default:
            return .unknown
        }
    }
}

/// Aynı tür hatanın kısa sürede tekrarını sayar.
///
/// Android 1.0.24.42'nin "son 60 dk" sayaç raporunun iOS karşılığı; burada
/// amaç rapor değil, panoda tekrar eden kopmaları tek satırda özetlemek.
struct BleFailureCounter {
    let window: TimeInterval
    private(set) var entries: [(kind: BleFailureKind, at: Date)] = []

    init(window: TimeInterval = 60) {
        self.window = window
    }

    /// Kaydı ekler ve pencere içindeki toplam sayıyı döndürür.
    @discardableResult
    mutating func record(_ kind: BleFailureKind, at date: Date = Date()) -> Int {
        entries.append((kind, date))
        prune(at: date)
        return count(kind, at: date)
    }

    /// Pencere içindeki belirli türün sayısı.
    func count(_ kind: BleFailureKind, at date: Date = Date()) -> Int {
        entries.filter { $0.kind == kind && date.timeIntervalSince($0.at) <= window }.count
    }

    /// Pencere içindeki toplam kopma sayısı.
    func total(at date: Date = Date()) -> Int {
        entries.filter { date.timeIntervalSince($0.at) <= window }.count
    }

    mutating func reset() { entries.removeAll() }

    private mutating func prune(at date: Date) {
        entries.removeAll { date.timeIntervalSince($0.at) > window }
        if entries.count > 50 { entries.removeFirst(entries.count - 50) }
    }
}

/// Tarama evreleri.
///
/// Android 1.0.24.42 "PI → normal devir" davranışının iOS karşılığı: iOS'ta
/// PendingIntent yok, ama tek seferlik tarama reklamı kaçırdığında ikinci bir
/// ısrarlı tarama evresi kopma boşluğunu kısaltıyor.
struct BleScanPolicy {
    struct Phase {
        let seconds: TimeInterval
        let allowDuplicates: Bool
        let name: String
    }

    static let phases: [Phase] = [
        .init(seconds: 12, allowDuplicates: false, name: "hızlı"),
        .init(seconds: 12, allowDuplicates: true, name: "ısrarlı")
    ]

    static var totalWindow: TimeInterval {
        phases.reduce(0) { $0 + $1.seconds }
    }
}
