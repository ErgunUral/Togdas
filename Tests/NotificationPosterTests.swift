import XCTest
import UserNotifications
@testable import ToqdasCore

/// `NotificationPoster`: tek gönderim noktası — içerik kurulumu, başarı
/// geri çağrısı ve time-sensitive bayrağı.
final class NotificationPosterTests: XCTestCase {
    private final class FakeCenter: NotificationPosting {
        struct AuthCall {
            var options: UNAuthorizationOptions
        }
        var requests: [UNNotificationRequest] = []
        var authCalls: [AuthCall] = []
        /// Sahte merkez: nil = başarı, dolu = hata.
        var addError: Error?

        func add(_ request: UNNotificationRequest, completion: ((Error?) -> Void)?) {
            requests.append(request)
            completion?(addError)
        }

        func requestAuthorization(options: UNAuthorizationOptions, completion: ((Bool) -> Void)?) {
            authCalls.append(AuthCall(options: options))
            completion?(true)
        }
    }

    func testPostBuildsContentAndCallsAdd() {
        let center = FakeCenter()
        NotificationPoster.post(
            NotificationPoster.Draft(
                identifier: "test-id",
                title: "Başlık",
                body: "Gövde"
            ),
            using: center
        )
        XCTAssertEqual(center.requests.count, 1)
        let request = center.requests[0]
        XCTAssertEqual(request.identifier, "test-id")
        XCTAssertEqual(request.content.title, "Başlık")
        XCTAssertEqual(request.content.body, "Gövde")
        // Varsayılan: ses açık, time-sensitive yok (mevcut davranış).
        XCTAssertNotNil(request.content.sound)
        XCTAssertEqual(request.content.interruptionLevel, .active)
        XCTAssertNil(request.trigger)
    }

    func testOnSuccessOnlyOnSuccess() {
        struct SendError: Error {}
        let ok = FakeCenter()
        var okCount = 0
        NotificationPoster.post(
            NotificationPoster.Draft(identifier: "a", title: "t", body: "b"),
            using: ok,
            onSuccess: { okCount += 1 }
        )
        XCTAssertEqual(okCount, 1)

        let failing = FakeCenter()
        failing.addError = SendError()
        var failCount = 0
        NotificationPoster.post(
            NotificationPoster.Draft(identifier: "b", title: "t", body: "b"),
            using: failing,
            onSuccess: { failCount += 1 }
        )
        XCTAssertEqual(failing.requests.count, 1)
        XCTAssertEqual(failCount, 0)
    }

    func testTimeSensitiveFlag() {
        let center = FakeCenter()
        NotificationPoster.post(
            NotificationPoster.Draft(identifier: "id", title: "t", body: "b", timeSensitive: true),
            using: center
        )
        XCTAssertEqual(center.requests[0].content.interruptionLevel, .timeSensitive)
    }

    func testSoundCanBeDisabled() {
        let center = FakeCenter()
        NotificationPoster.post(
            NotificationPoster.Draft(identifier: "id", title: "t", body: "b", sound: false),
            using: center
        )
        XCTAssertNil(center.requests[0].content.sound)
    }

    func testRequestAuthorizationPassesOptions() {
        let center = FakeCenter()
        NotificationPoster.requestAuthorization(using: center)
        XCTAssertEqual(center.authCalls.count, 1)
        XCTAssertTrue(center.authCalls[0].options.contains(.alert))
        XCTAssertTrue(center.authCalls[0].options.contains(.sound))
    }
}
