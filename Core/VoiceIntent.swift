import Foundation

/// Sesli komutların kapalı niyet kümesi.
/// LLM veya konuşma tanıma yalnızca bu kümeden bir sonuç üretebilir; serbest metin
/// doğrudan komuta dönüşmez.
public enum VoiceIntent: Equatable {
    // Salt okunur
    case batteryStatus
    case rangeStatus
    case lockStatus
    case trunkStatus
    case windowsStatus
    case chargingStatus
    case tirePressureStatus
    case outsideTemperatureStatus
    case odometerStatus
    case auxiliaryBatteryStatus

    // Eylemler
    case lock
    case unlock
    case trunkOpen
    case trunkClose
    case windowsOpen
    case windowsClose
    case climateOn(temperature: Int?)
    case climateOff
    case findVehicle

    // Diğer
    case help
    case unknown
}

public extension VoiceIntent {
    /// Araçta bir şey değiştiren niyetler; politika kapısı ve onay gerektirir.
    var isAction: Bool {
        switch self {
        case .lock, .unlock, .trunkOpen, .trunkClose, .windowsOpen, .windowsClose,
             .climateOn, .climateOff, .findVehicle:
            return true
        default:
            return false
        }
    }

    /// Yüksek riskli, cihaz kilidinin açık olmasını gerektiren niyet.
    var requiresDeviceUnlock: Bool { self == .unlock }
}

/// Türkçe sesli komutları deterministik olarak ayrıştırır.
///
/// Kural tabanlıdır: çevrimdışı çalışır, test edilebilir ve halüsinasyon üretmez.
/// Anlaşılamayan cümlelerde `unknown` döner; bu durumda istenirse cihaz üstü
/// Foundation Models yedek ayrıştırıcı olarak kullanılabilir (bkz. Docs/SesliKomutlar.md).
public struct VoiceIntentParser {
    public init() {}

    public func parse(_ raw: String) -> VoiceIntent {
        let text = Self.normalize(raw)
        guard !text.isEmpty else { return .unknown }

        let tokens = Set(text.split(separator: " ").map(String.init))
        let hasOpenVerb = !tokens.isDisjoint(with: [
            "ac", "acar", "acarmisin", "acabilir", "acabilirsin", "acsin", "acsana", "acalim", "aciver"
        ])
        let hasCloseVerb = !tokens.isDisjoint(with: [
            "kapat", "kapatir", "kapatirmisin", "kapatabilir", "kapatabilirsin", "kapatsin", "kapatsana", "kapatalim"
        ])
        let isQuestion = !tokens.isDisjoint(with: ["mi", "mu", "midir", "mudur", "miydi", "muydu"])
            || text.contains("ne kadar")
            || text.contains("kac")

        // "açma" / "kapatma" gibi olumsuzlamalar güvenli tarafta reddedilir.
        if tokens.contains(where: { $0.hasPrefix("acma") || $0.hasPrefix("kapatma") }) {
            return .unknown
        }

        if text.contains("yardim") || text.contains("neler yapabilirsin") || tokens.contains("komutlar") {
            return .help
        }

        if text.contains("korna") || text.contains("araci bul")
            || (text.contains("arac") && text.contains("nerede"))
            || (tokens.contains("far") || tokens.contains("farlar") || tokens.contains("farlari"))
                && (hasOpenVerb || text.contains("yak")) {
            return .findVehicle
        }

        // Bagaj / cam / kilit: durum soruları eylemlerden önce ayrılır.
        if text.contains("bagaj") {
            if (text.contains("acik") || text.contains("kapali")) && isQuestion { return .trunkStatus }
            if hasOpenVerb { return .trunkOpen }
            if hasCloseVerb { return .trunkClose }
        }

        if text.contains("cam") || text.contains("pencere") {
            if (text.contains("acik") || text.contains("kapali")) && isQuestion { return .windowsStatus }
            if hasOpenVerb { return .windowsOpen }
            if hasCloseVerb { return .windowsClose }
        }

        if text.contains("kilit") || text.contains("kapi") {
            if hasOpenVerb { return .unlock }
            if text.contains("kilitle") || hasCloseVerb { return .lock }
            if text.contains("kilitli") || text.contains("acik") { return .lockStatus }
        }

        if text.contains("klima") || text.contains("isitma") || text.contains("sogutma") {
            if hasCloseVerb { return .climateOff }
            if hasOpenVerb { return .climateOn(temperature: Self.temperature(in: tokens)) }
            if let value = Self.temperature(in: tokens) { return .climateOn(temperature: value) }
        }

        if text.contains("sarj") || text.contains("sarz") {
            if text.contains("kapak") || text.contains("kapag") || text.contains("istasyon") { return .unknown }
            if text.contains("oluyor") || text.contains("sarjda") || text.contains("sarzda") || text.contains("dolduruluyor") {
                return .chargingStatus
            }
            return .batteryStatus
        }

        if text.contains("batarya") || text.contains("pil") || text.contains("yuzde") {
            return .batteryStatus
        }

        if text.contains("menzil") || (text.contains("kac") && (tokens.contains("km") || tokens.contains("kilometre"))) {
            return .rangeStatus
        }

        if text.contains("lastik") || text.contains("lastig") || text.contains("basinc") {
            return .tirePressureStatus
        }

        if text.contains("aku") || (tokens.contains("12") && (tokens.contains("v") || text.contains("volt"))) {
            return .auxiliaryBatteryStatus
        }

        if text.contains("odometre") || text.contains("kilometre sayaci") || text.contains("toplam kilometre") {
            return .odometerStatus
        }

        if text.contains("sicaklik") && (text.contains("dis") || text.contains("hava") || text.contains("disari")) {
            return .outsideTemperatureStatus
        }

        if text.contains("hava") && text.contains("kac") && text.contains("derece") {
            return .outsideTemperatureStatus
        }

        return .unknown
    }

    // MARK: - Yardımcılar

    /// Küçük harfe indirir, Türkçe karakterleri sadeleştirir ve noktalama işaretlerini atar.
    /// "Kapıları Aç!" → "kapilari ac"
    static func normalize(_ text: String) -> String {
        let lowered = text.lowercased(with: Locale(identifier: "tr_TR"))
        let mapped: [Character: Character] = [
            "ı": "i", "ş": "s", "ğ": "g", "ü": "u", "ö": "o", "ç": "c",
            "â": "a", "î": "i", "û": "u"
        ]
        let cleaned = lowered.map { character -> Character in
            if let replacement = mapped[character] { return replacement }
            return (character.isLetter || character.isNumber) ? character : " "
        }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }

    /// 16–30 aralığındaki sıcaklık değerini bulur ("klimayı 22 derece yap").
    static func temperature(in tokens: Set<String>) -> Int? {
        tokens.compactMap(Int.init).first { (16...30).contains($0) }
    }
}
