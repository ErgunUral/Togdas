import XCTest
@testable import ToqdasCore

final class VoiceChatTests: XCTestCase {
    private let chat = VoiceChat()

    func testGreeting() {
        for text in ["merhaba", "Selam", "günaydın", "iyi akşamlar"] {
            XCTAssertEqual(chat.reply(for: text)?.topic, .greeting, text)
        }
    }

    func testWellbeingAnswersDirectly() {
        let reply = chat.reply(for: "nasılsın")
        XCTAssertEqual(reply?.topic, .wellbeing)
        XCTAssertTrue(reply?.text.contains("İyiyim") == true)
    }

    func testThanks() {
        for text in ["teşekkürler", "sağ ol", "eyvallah", "çok teşekkür ederim"] {
            XCTAssertEqual(chat.reply(for: text)?.topic, .thanks, text)
        }
    }

    func testCapabilitiesAndIdentity() {
        XCTAssertEqual(chat.reply(for: "neler yapabilirsin")?.topic, .capabilities)
        XCTAssertEqual(chat.reply(for: "hangi komutlar var")?.topic, .capabilities)
        XCTAssertEqual(chat.reply(for: "sen kimsin")?.topic, .identity)
    }

    func testCapabilitiesWinOverGreeting() {
        XCTAssertEqual(chat.reply(for: "merhaba neler yapabilirsin")?.topic, .capabilities)
    }

    func testCommandTextIsNotChat() {
        for text in [
            "şarjım ne kadar",
            "kapılar kilitli mi",
            "bagajı aç",
            "lastik basınçları",
            "kilidi aç"
        ] {
            XCTAssertNil(chat.reply(for: text), text)
        }
    }

    func testEmptyAndNoiseAreNotChat() {
        XCTAssertNil(chat.reply(for: ""))
        XCTAssertNil(chat.reply(for: "   "))
        XCTAssertNil(chat.reply(for: "hmm"))
    }

    func testNoAraçStateClaims() {
        // Sohbet katmanı araç verisi iddia etmez; yanıtlar yalnızca yönlendirme içerir.
        for text in ["nasılsın", "merhaba", "teşekkürler"] {
            let reply = chat.reply(for: text)?.text ?? ""
            XCTAssertFalse(reply.contains("%"))
            XCTAssertFalse(reply.contains("km"))
            XCTAssertFalse(reply.lowercased().contains("kilitli."))
        }
    }

    // MARK: - Saat / tarih

    private var fixedNow: Date {
        // 26 Ekim 2026, 16:23 İstanbul
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 26
        components.hour = 16
        components.minute = 23
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return calendar.date(from: components)!
    }

    private var istanbul: TimeZone { TimeZone(identifier: "Europe/Istanbul")! }

    func testTimeUsesInjectedClock() {
        let reply = chat.reply(for: "saat kaç", now: fixedNow, timeZone: istanbul)
        XCTAssertEqual(reply?.topic, .time)
        XCTAssertEqual(reply?.text, "Saat 16:23.")
    }

    func testDateUsesInjectedClock() {
        let reply = chat.reply(for: "bugün günlerden ne", now: fixedNow, timeZone: istanbul)
        XCTAssertEqual(reply?.topic, .date)
        XCTAssertEqual(reply?.text, "Bugün 26 Ekim 2026, Pazartesi.")
    }

    func testTimeVariants() {
        for text in ["saat kaç", "saati söyler misin", "şu an saat kaç"] {
            XCTAssertEqual(chat.reply(for: text, now: fixedNow, timeZone: istanbul)?.topic, .time, text)
        }
    }

    func testTimeAndDateStayOutOfCommandParser() {
        let parser = VoiceCommandParser()
        for text in ["saat kaç", "bugün günlerden ne"] {
            XCTAssertEqual(parser.parse(text), .unknown, text)
        }
    }
}
