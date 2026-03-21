import FirebaseAuth
import GoogleSignIn
import UIKit

enum GoogleAuthServiceError: LocalizedError {
    case missingRootViewController
    case missingIDToken

    var errorDescription: String? {
        switch self {
        case .missingRootViewController:
            return "Unable to present Google Sign-In."
        case .missingIDToken:
            return "Google Sign-In did not return an ID token."
        }
    }
}

final class GoogleAuthService {
    func signIn() async throws {
        guard let presentingViewController = Self.rootViewController() else {
            throw GoogleAuthServiceError.missingRootViewController
        }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController)
        guard let idToken = result.user.idToken?.tokenString else {
            throw GoogleAuthServiceError.missingIDToken
        }

        let accessToken = result.user.accessToken.tokenString
        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
        _ = try await Auth.auth().signIn(with: credential)
    }

    private static func rootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
}
