import XCTest
@testable import ToqdasCore

final class ShortcutLinkTests: XCTestCase {
    func testParsesSupportedActions() {
        for action in ShortcutAction.allCases {
            let url = URL(string: "toqdas://command?action=\(action.rawValue)")!
            XCTAssertEqual(ShortcutLink.action(from: url), action)
        }
    }

    func testRoundTripURL() {
        for action in ShortcutAction.allCases {
            guard let url = ShortcutLink.url(for: action) else { return XCTFail("URL üretilemedi") }
            XCTAssertEqual(ShortcutLink.action(from: url), action)
        }
    }

    func testRejectsWrongSchemeOrHost() {
        XCTAssertNil(ShortcutLink.action(from: URL(string: "https://command?action=lock")!))
        XCTAssertNil(ShortcutLink.action(from: URL(string: "toqdas://other?action=lock")!))
        XCTAssertNil(ShortcutLink.action(from: URL(string: "superapp://prod/callback?action=lock")!))
    }

    func testRejectsMissingOrUnknownAction() {
        XCTAssertNil(ShortcutLink.action(from: URL(string: "toqdas://command")!))
        XCTAssertNil(ShortcutLink.action(from: URL(string: "toqdas://command?action=")!))
        XCTAssertNil(ShortcutLink.action(from: URL(string: "toqdas://command?action=drive")!))
        XCTAssertNil(ShortcutLink.action(from: URL(string: "toqdas://command?other=lock")!))
    }

    func testSchemeAndHostAreCaseInsensitive() {
        XCTAssertEqual(ShortcutLink.action(from: URL(string: "TOQDAS://COMMAND?action=lock")!), .lock)
    }

    func testBleCodesMatchProtocol() {
        XCTAssertEqual(ShortcutAction.unlock.bleCode, 2)
        XCTAssertEqual(ShortcutAction.trunkOpen.bleCode, 4)
        XCTAssertEqual(ShortcutAction.trunkClose.bleCode, 5)
        XCTAssertEqual(ShortcutAction.lock.bleCode, 7)
    }

    func testIdentifiersStayStable() {
        // Kısayol URL'leri kullanıcı tarafında kayıtlı olabilir; adlar değişmemeli.
        XCTAssertEqual(ShortcutAction.lock.rawValue, "lock")
        XCTAssertEqual(ShortcutAction.unlock.rawValue, "unlock")
        XCTAssertEqual(ShortcutAction.trunkOpen.rawValue, "trunkOpen")
        XCTAssertEqual(ShortcutAction.trunkClose.rawValue, "trunkClose")
    }
}
