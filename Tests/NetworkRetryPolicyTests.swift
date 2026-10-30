import XCTest
@testable import ToqdasCore

final class NetworkRetryPolicyTests: XCTestCase {
    func testTransientTransportErrorsRetry() {
        for code: URLError.Code in [.timedOut, .networkConnectionLost, .notConnectedToInternet,
                                    .cannotConnectToHost, .dnsLookupFailed] {
            XCTAssertTrue(NetworkRetryPolicy.shouldRetry(URLError(code)), "\(code) yeniden denenmeli")
        }
    }

    func testCancellationAndClientErrorsDoNotRetry() {
        XCTAssertFalse(NetworkRetryPolicy.shouldRetry(URLError(.cancelled)))
        XCTAssertFalse(NetworkRetryPolicy.shouldRetry(URLError(.badURL)))
        XCTAssertFalse(NetworkRetryPolicy.shouldRetry(statusCode: 400))
        XCTAssertFalse(NetworkRetryPolicy.shouldRetry(statusCode: 404))
        XCTAssertFalse(NetworkRetryPolicy.shouldRetry(statusCode: 401))
    }

    func testServerAndRateLimitErrorsRetry() {
        for status in [408, 425, 429, 500, 502, 503, 504] {
            XCTAssertTrue(NetworkRetryPolicy.shouldRetry(statusCode: status), "\(status) yeniden denenmeli")
        }
    }

    func testBackoffGrowsAndIsCapped() {
        XCTAssertEqual(NetworkRetryPolicy.delay(afterAttempt: 0), 0.6, accuracy: 0.001)
        XCTAssertEqual(NetworkRetryPolicy.delay(afterAttempt: 1), 1.2, accuracy: 0.001)
        XCTAssertEqual(NetworkRetryPolicy.delay(afterAttempt: 2), 2.4, accuracy: 0.001)
        XCTAssertEqual(NetworkRetryPolicy.delay(afterAttempt: 20), 6.0, accuracy: 0.001)
    }

    func testRetryAfterOverridesBackoff() {
        XCTAssertEqual(NetworkRetryPolicy.delay(afterAttempt: 0, retryAfter: 3), 3, accuracy: 0.001)
        XCTAssertEqual(NetworkRetryPolicy.delay(afterAttempt: 0, retryAfter: 60), 6, accuracy: 0.001)
    }
}
