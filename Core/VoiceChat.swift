import Foundation

/// Komut olmayan sorulara verilen yerel, deterministik yanıtlar.
///
/// - Ağa çıkmaz, LLM kullanmaz, hiçbir komut yürütmez.
/// - Yalnızca tanınan sohbet kalıplarını yanıtlar. Tanınmayan cümle `nil`
///   döner ve mevcut komut politikasının “anlaşılmadı” yanıtına bırakılır.
/// - Araç durumu iddiası içermez; veri gerektiren her soru komut hattına gider.
/// - Saat/tarih yanıtları dışarıdan verilen `Date` ve saat dilimiyle üretilir;
///   böylece testler zamandan bağımsız kalır.
public struct VoiceChat {
    public enum Topic: Equatable {
        case greeting
        case wellbeing
        case thanks
        case capabilities
        case identity
        case time
        case date
    }

    public struct Reply: Equatable {
        public let topic: Topic
        public let text: String

        public init(topic: Topic, text: String) {
            self.topic = topic
            self.text = text
        }
    }

    public init() {}

    /// Sohbet kalıbı eşleşirse yanıtı döner; komut metinlerinde `nil`.
    public func reply(
        for text: String,
        now: Date = Date(),
        timeZone: TimeZone = .current
    ) -> Reply? {
        let normalized = VoiceCommandParser.normalize(text)
        guard !normalized.isEmpty else { return nil }
        let padded = " \(normalized) "

        for (topic, phrases) in Self.patterns {
            guard phrases.contains(where: { padded.contains(" \($0) ") }) else { continue }
            return Reply(topic: topic, text: Self.text(for: topic, now: now, timeZone: timeZone))
        }
        return nil
    }

    // Sıra önemli: yetenek/kimlik/saat soruları selamlamadan önce eşleşir,
    // böylece “merhaba neler yapabilirsin” yetenek yanıtı verir.
    private static let patterns: [(Topic, [String])] = [
        (.capabilities, [
            "neler yapabilirsin", "ne yapabilirsin", "neler yapabiliyorsun",
            "hangi komutlar", "komutlar neler", "bana ne sorabilirim",
            "yardim", "yardim eder misin"
        ]),
        (.identity, [
            "sen kimsin", "kimsin", "adin ne", "senin adin ne",
            "ne ise yararsin", "sen nesin"
        ]),
        (.time, [
            "saat kac", "saat kacta", "su an saat kac", "saati soyler misin"
        ]),
        (.date, [
            "bugun gunlerden ne", "gunlerden ne", "bugun hangi gun",
            "tarih ne", "bugunun tarihi ne"
        ]),
        (.wellbeing, [
            "nasilsin", "nasilsiniz", "iyi misin", "keyfin yerinde mi",
            "naber", "ne haber", "nasil gidiyor"
        ]),
        (.thanks, [
            "tesekkurler", "tesekkur ederim", "cok tesekkurler",
            "sag ol", "sagol", "eyvallah"
        ]),
        (.greeting, [
            "merhaba", "selam", "gunaydin", "iyi aksamlar", "iyi geceler", "alo"
        ])
    ]

    private static func text(for topic: Topic, now: Date, timeZone: TimeZone) -> String {
        switch topic {
        case .greeting:
            return "Merhaba. Aracınla ilgili soru sorabilirsin: batarya, menzil, kapılar, lastik basıncı."
        case .wellbeing:
            return "İyiyim, teşekkürler. Araçla ilgili bir şey sormak istersen buradayım."
        case .thanks:
            return "Rica ederim. Başka bir şey sormak ister misin?"
        case .capabilities:
            return "Batarya ve menzili, kapıların kilit durumunu, lastik basınçlarını, iç ve dış sıcaklığı, şarj durumunu sorabilirsin. Kilit ve kilit açma için onay isterim."
        case .identity:
            return "Ben Toqdas'ın araç asistanıyım. Aracın verilerini okurum; kilit ve kilit açma komutlarını yalnızca senin onayınla gönderirim."
        case .time:
            return "Saat \(formatted(now, format: "HH:mm", timeZone: timeZone))."
        case .date:
            return "Bugün \(formatted(now, format: "d MMMM yyyy, EEEE", timeZone: timeZone))."
        }
    }

    private static func formatted(_ date: Date, format: String, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
