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

@MainActor
final class GoogleAuthService: AuthServiceProtocol {
    var currentUserId: String? {
        let uid = Auth.auth().currentUser?.uid
        return uid
    }

    func fetchPlatformAdminClaimFromIDToken(forceRefresh: Bool) async throws -> Bool {
        guard let user = Auth.auth().currentUser else { return false }
        let token = try await user.getIDTokenResult(forcingRefresh: forceRefresh)
        return (token.claims["platformAdmin"] as? Bool) == true
    }

    func signIn() async throws {
        AppDebugLog.log("GoogleAuthService.signIn: resolving root VC for Google UI")
        guard let presentingViewController = Self.rootViewController() else {
            AppDebugLog.log("GoogleAuthService.signIn: missing root VC")
            throw GoogleAuthServiceError.missingRootViewController
        }

        AppDebugLog.log("GoogleAuthService.signIn: presenting GIDSignIn…")
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController)
        guard let idToken = result.user.idToken?.tokenString else {
            AppDebugLog.log("GoogleAuthService.signIn: missing ID token from Google")
            throw GoogleAuthServiceError.missingIDToken
        }

        let accessToken = result.user.accessToken.tokenString
        let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
        AppDebugLog.log("GoogleAuthService.signIn: exchanging Google tokens for Firebase credential…")
        let authResult = try await Auth.auth().signIn(with: credential)
        AppDebugLog.log("GoogleAuthService.signIn: Firebase sign-in OK uid=\(authResult.user.uid) isNewUser=\(authResult.additionalUserInfo?.isNewUser ?? false)")
    }

    func signOut() throws {
        AppDebugLog.log("GoogleAuthService.signOut: GIDSignIn + Firebase signOut")
        GIDSignIn.sharedInstance.signOut()
        try Auth.auth().signOut()
        AppDebugLog.log("GoogleAuthService.signOut: done")
    }

    private static func rootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
}
