import Foundation

/// Ağ isteklerinde hangi hataların yeniden denenebileceğini ve bekleme
/// süresini belirler. Yalnızca tekrar gönderilmesi güvenli isteklerde
/// (GET/HEAD) ve oturum yenileme sonrası 401'de kullanılır.
enum NetworkRetryPolicy {
    static let maxAttempts = 3
    static let baseDelay: TimeInterval = 0.6
    static let maximumDelay: TimeInterval = 6

    static func shouldRetry(_ error: URLError) -> Bool {
        switch error.code {
        case .timedOut,
             .networkConnectionLost,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .notConnectedToInternet,
             .internationalRoamingOff,
             .dataNotAllowed,
             .secureConnectionFailed,
             .resourceUnavailable:
            return true
        default:
            return false
        }
    }

    static func shouldRetry(statusCode: Int) -> Bool {
        [408, 425, 429, 500, 502, 503, 504].contains(statusCode)
    }

    /// `attempt` 0'dan başlar. Sunucunun `Retry-After` değeri varsa ona
    /// uyulur, ancak 6 saniyeden fazla beklenmez.
    static func delay(afterAttempt attempt: Int, retryAfter: TimeInterval? = nil) -> TimeInterval {
        if let retryAfter, retryAfter > 0 {
            return min(retryAfter, maximumDelay)
        }
        let exponent = max(0, attempt)
        return min(baseDelay * pow(2, Double(exponent)), maximumDelay)
    }

    static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        if let seconds = TimeInterval(value) {
            return seconds
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: value) else { return nil }
        return max(0, date.timeIntervalSinceNow)
    }
}
