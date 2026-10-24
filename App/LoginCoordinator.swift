import AuthenticationServices
import UIKit

@MainActor
final class LoginCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func login() async throws -> (code: String, verifier: String) {
        guard session == nil else { throw AppError.message("Giriş zaten devam ediyor.") }
        let attempt = try OAuthAttempt()
        return try await withCheckedThrowingContinuation { continuation in
            let auth = ASWebAuthenticationSession(url: attempt.authorizationURL, callbackURLScheme: "superapp") { [weak self] url, error in
                Task { @MainActor in
                    self?.session = nil
                    do {
                        if let error { throw error }
                        guard let url else { throw AppError.message("Giriş dönüşü alınamadı.") }
                        continuation.resume(returning: (try attempt.code(from: url), attempt.verifier))
                    } catch { continuation.resume(throwing: error) }
                }
            }
            auth.presentationContextProvider = self
            auth.prefersEphemeralWebBrowserSession = true
            session = auth
            if !auth.start() {
                session = nil
                continuation.resume(throwing: AppError.message("Giriş penceresi açılamadı."))
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
