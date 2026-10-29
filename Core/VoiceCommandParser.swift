import Foundation

/// Türkçe sesli komutları deterministik olarak tipli komutlara çevirir.
///
/// Kurallar çevrimdışıdır; LLM kullanmaz. Anlaşılmayan veya birden fazla
/// konuya değinen cümlelerde eylem üretmez, `ambiguous`/`unknown` döner.
public struct VoiceCommandParser: Sendable {
    public init() {}

    public func parse(_ raw: String) -> VoiceCommand {
        parseDetailed(raw).command
    }

    public func parseDetailed(_ raw: String) -> VoiceParseResult {
        let text = Self.normalize(raw)
        guard !text.isEmpty else {
            return VoiceParseResult(command: .unknown, confidence: 0, normalizedText: text)
        }

        let tokens = text.split(separator: " ").map(String.init)
        let tokenSet = Set(tokens)

        // Kısa onay/ret/iptal ifadeleri tek başına komut değildir.
        if !tokens.isEmpty, tokens.allSatisfy({ Self.affirmations.contains($0) }) {
            return result(.affirm, 1, text)
        }
        if !tokens.isEmpty, tokens.allSatisfy({ Self.denials.contains($0) }) {
            return result(.deny, 1, text)
        }
        if !tokens.isEmpty, tokens.allSatisfy({ Self.cancellations.contains($0) }) {
            return result(.cancel, 1, text)
        }

        // "açma", "kapatma", "kilitleme" gibi olumsuzlamalar güvenli tarafta
        // reddedilir; hiçbir eylem üretilmez.
        if !tokenSet.isDisjoint(with: Self.negativeTokens) {
            return result(.unknown, 0.2, text)
        }

        if Self.containsAny(text, ["yardim", "neler yapabilirsin", "ne yapabilirsin", "komutlar"]) {
            return result(.help, 1, text)
        }

        if text.contains("korna")
            || text.contains("araci bul")
            || (text.contains("arac") && text.contains("nerede"))
            || ((tokenSet.contains("far") || tokenSet.contains("farlar") || tokenSet.contains("farlari"))
                && (Self.hasOpenVerb(tokenSet) || text.contains("yak"))) {
            return result(.findVehicle, 0.9, text)
        }

        let openVerb = Self.hasOpenVerb(tokenSet)
        let closeVerb = Self.hasCloseVerb(tokenSet)
        let lockVerb = Self.hasLockVerb(tokenSet)
        let unlockVerb = (text.contains("kilit") || text.contains("kapi")) && openVerb
        let question = Self.isQuestion(tokenSet, text)
        let temperature = Self.temperature(in: tokenSet)

        var topics = Set<VoiceStatusTopic>()
        var action: VoiceCommand?

        if text.contains("bagaj") {
            topics.insert(.trunk)
            if openVerb { action = .trunk(open: true) }
            if closeVerb { action = .trunk(open: false) }
        }

        if text.contains("cam") || text.contains("pencere") {
            topics.insert(.windows)
            if openVerb { action = .windows(open: true) }
            if closeVerb { action = .windows(open: false) }
        }

        if text.contains("kilit") || text.contains("kapi") {
            topics.insert(.locks)
            if unlockVerb {
                action = .unlock
            } else if lockVerb || closeVerb {
                action = .lock
            }
        }

        if text.contains("klima") || text.contains("isitma") || text.contains("sogutma") {
            topics.insert(.climate)
            if closeVerb {
                action = .climate(on: false, temperature: nil)
            } else if openVerb || temperature != nil {
                action = .climate(on: true, temperature: temperature)
            }
        }

        if text.contains("sarj") || text.contains("sarz") {
            if text.contains("kapak") || text.contains("kapag") || text.contains("kapisi") || text.contains("istasyon") {
                return result(.unknown, 0.2, text)
            }
            if text.contains("sarjda") || text.contains("sarzda")
                || text.contains("oluyor")
                || text.contains("dolduruluyor")
                || text.contains("sarj durumu") || text.contains("sarz durumu") {
                topics.insert(.charging)
            } else {
                topics.insert(.battery)
            }
        }

        if text.contains("batarya") || text.contains("yuzde")
            || tokenSet.contains(where: { $0 == "pil" || $0.hasPrefix("pil") }) {
            topics.insert(.battery)
        }

        if text.contains("menzil")
            || (text.contains("kac") && (tokenSet.contains("km") || tokenSet.contains("kilometre"))) {
            topics.insert(.range)
        }

        if text.contains("lastik") || text.contains("lastig") || text.contains("basinc") {
            topics.insert(.tirePressure)
        }

        if text.contains("aku") || (tokenSet.contains("12") && (tokenSet.contains("v") || text.contains("volt"))) {
            topics.insert(.auxiliaryBattery)
        }

        if text.contains("odometre") || text.contains("kilometre sayaci") || text.contains("toplam kilometre") {
            topics.insert(.odometer)
        }

        if (text.contains("sicaklik") && (text.contains("dis") || text.contains("hava") || text.contains("disari")))
            || (text.contains("hava") && text.contains("kac") && text.contains("derece")) {
            topics.insert(.outsideTemperature)
        }

        // Birden fazla konuya değinen cümle tek komuta indirgenmez.
        if topics.count > 1 {
            return result(.ambiguous, 0.3, text)
        }

        if let action {
            return result(action, 0.95, text)
        }

        if let topic = topics.first {
            let isPositionTopic = topic == .locks || topic == .trunk || topic == .windows || topic == .climate
            let hasPositionWord = text.contains("acik") || text.contains("kapali") || text.contains("kilitli")
            if isPositionTopic && !question && !hasPositionWord {
                return result(.ambiguous, 0.4, text)
            }
            return result(.status(topic), 0.9, text)
        }

        if openVerb || closeVerb || lockVerb {
            return result(.ambiguous, 0.3, text)
        }

        return result(.unknown, 0, text)
    }

    // MARK: - Yardımcılar

    private func result(_ command: VoiceCommand, _ confidence: Double, _ text: String) -> VoiceParseResult {
        VoiceParseResult(command: command, confidence: confidence, normalizedText: text)
    }

    private static let openVerbs: Set<String> = [
        "ac", "acar", "acarmisin", "acarmisiniz", "acabilir", "acabilirsin", "acabilirsiniz",
        "acsin", "acsana", "acalim", "aciver", "acin", "acmak", "acmayi"
    ]

    private static let closeVerbs: Set<String> = [
        "kapat", "kapatir", "kapatirmisin", "kapatirmisiniz", "kapatabilir",
        "kapatabilirsin", "kapatabilirsiniz", "kapatsin", "kapatsana", "kapatalim", "kapatin",
        "kapatmak", "kapatmayi"
    ]

    private static let lockVerbs: Set<String> = [
        "kilitle", "kilitla", "kilitlesin", "kilitlermisin", "kilitlermisiniz", "kilitleyin",
        "kilitlemek", "kilitlemeyi"
    ]

    private static let affirmations: Set<String> = [
        "evet", "tamam", "peki", "olur", "onayla", "onayliyorum", "dogru", "aynen", "tabii", "tabi"
    ]

    private static let denials: Set<String> = [
        "hayir", "olmaz", "istemiyorum", "onaylamiyorum"
    ]

    private static let cancellations: Set<String> = [
        "iptal", "vazgec", "dur", "bosver"
    ]

    private static let negativeTokens: Set<String> = [
        "acma", "acmayin", "kapatma", "kapatmayin", "kilitleme", "kilitlemeyin", "dokunma", "yapma"
    ]

    private static func hasOpenVerb(_ tokens: Set<String>) -> Bool {
        !tokens.isDisjoint(with: openVerbs)
    }

    private static func hasCloseVerb(_ tokens: Set<String>) -> Bool {
        !tokens.isDisjoint(with: closeVerbs)
    }

    private static func hasLockVerb(_ tokens: Set<String>) -> Bool {
        !tokens.isDisjoint(with: lockVerbs)
    }

    private static func isQuestion(_ tokens: Set<String>, _ text: String) -> Bool {
        !tokens.isDisjoint(with: [
            "mi", "mu", "midir", "mudur", "miydi", "muydu", "misin", "musun", "misiniz", "musunuz"
        ]) || text.contains("ne kadar") || text.contains("kac") || text.contains("nedir") || text.contains("nasil")
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    /// 16–30 aralığındaki sıcaklık değerini bulur ("klimayı 22 derece yap").
    private static func temperature(in tokens: Set<String>) -> Int? {
        tokens.compactMap(Int.init).first { (16...30).contains($0) }
    }

    /// Küçük harfe indirir, Türkçe karakterleri sadeleştirir ve noktalama
    /// işaretlerini atar. "Kapıları Aç!" → "kapilari ac"
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
}
