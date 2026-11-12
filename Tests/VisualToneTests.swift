import XCTest
@testable import ToqdasCore

/// Durum→görsel ton sözlüğü: yeşil=canlı · turuncu=bekleme/eski ·
/// pembe=hata · gri=bilgi yok. UI renkleri bu tonlardan çözülür.
final class VisualToneTests: XCTestCase {
    func testStateTones() {
        XCTAssertTrue(BleConnection.State.ready.visualTone == .positive)
        XCTAssertTrue(BleConnection.State.failed(.vehicleKeyMissing).visualTone == .warning, "Eşleştirme bekleniyor fatal hata değil")
        XCTAssertTrue(BleConnection.State.failed(.connectionTimeout).visualTone == .negative)
        XCTAssertTrue(BleConnection.State.failed(.unknown("hata")).visualTone == .negative)
        XCTAssertTrue(BleConnection.State.disconnected.visualTone == .neutral)
        for state: BleConnection.State in [.connecting, .discovering, .certificate, .challenge, .authenticated] {
            XCTAssertTrue(state.visualTone == .warning, "Ara aşama işlem sürüyor tonu: \(state)")
        }
    }

    func testLockTones() {
        XCTAssertTrue(LockVisual.tone(locked: true, isStale: false) == .positive)
        XCTAssertTrue(LockVisual.tone(locked: false, isStale: false) == .warning, "Açık kilit uyarı tonu")
        XCTAssertTrue(LockVisual.tone(locked: nil, isStale: false) == .neutral, "Bilgi yok asla hata değil")
        XCTAssertTrue(LockVisual.tone(locked: true, isStale: true) == .warning, "Eski veri bekleme/eski tonu")
        XCTAssertTrue(LockVisual.tone(locked: nil, isStale: true) == .warning)
    }
}
