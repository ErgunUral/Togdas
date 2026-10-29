import Foundation

/// Sesli komutların salt okunur konuları.
public enum VoiceStatusTopic: String, CaseIterable, Equatable, Sendable {
    case battery
    case range
    case locks
    case trunk
    case windows
    case climate
    case charging
    case tirePressure
    case outsideTemperature
    case odometer
    case auxiliaryBattery

    public var title: String {
        switch self {
        case .battery: return "Batarya"
        case .range: return "Menzil"
        case .locks: return "Kilit"
        case .trunk: return "Bagaj"
        case .windows: return "Cam"
        case .climate: return "Klima"
        case .charging: return "Şarj"
        case .tirePressure: return "Lastik basıncı"
        case .outsideTemperature: return "Dış sıcaklık"
        case .odometer: return "Odometre"
        case .auxiliaryBattery: return "12 V akü"
        }
    }
}

/// Sesli komutların kapalı kümesi. Serbest metin doğrudan yürütülmez;
/// önce bu tipli komuta dönüşür, sonra politikadan geçer.
public enum VoiceCommand: Equatable, Sendable {
    case status(VoiceStatusTopic)
    case lock
    case unlock
    case trunk(open: Bool)
    case windows(open: Bool)
    case climate(on: Bool, temperature: Int?)
    case findVehicle
    case help
    case cancel
    case affirm
    case deny
    case ambiguous
    case unknown
}

public extension VoiceCommand {
    /// Araçta bir şey değiştiren komutlar.
    var isAction: Bool {
        switch self {
        case .lock, .unlock, .trunk, .windows, .climate:
            return true
        default:
            return false
        }
    }

    /// Yüksek riskli, cihaz kilidinin açık olmasını gerektiren komut.
    var requiresDeviceUnlock: Bool {
        if case .unlock = self { return true }
        return false
    }

    /// Araçta henüz doğrulanmamış, önizleme olarak işaretlenen komutlar.
    var isPreview: Bool {
        switch self {
        case .trunk, .windows:
            return true
        default:
            return false
        }
    }

    /// Kullanıcıya gösterilecek eylem adı.
    var actionLabel: String? {
        switch self {
        case .lock: return "Kilitleme"
        case .unlock: return "Kilit açma"
        case .trunk(let open): return open ? "Bagaj açma" : "Bagaj kapatma"
        case .windows(let open): return open ? "Cam açma" : "Cam kapatma"
        case .climate(let on, _): return on ? "Klima açma" : "Klima kapatma"
        default: return nil
        }
    }
}

/// Ayrıştırıcının sonucu. `confidence` yalnızca teşhis ve ileride eşik
/// politikası için tutulur; komut yürütme kararı `VoiceCommandPolicy` verir.
public struct VoiceParseResult: Equatable, Sendable {
    public let command: VoiceCommand
    public let confidence: Double
    public let normalizedText: String

    public init(command: VoiceCommand, confidence: Double, normalizedText: String) {
        self.command = command
        self.confidence = confidence
        self.normalizedText = normalizedText
    }
}
