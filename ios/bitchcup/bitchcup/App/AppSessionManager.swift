import FirebaseAuth
import Foundation

@MainActor
final class AppSessionManager: ObservableObject {
    @Published private(set) var sessionState: SessionState = .loading
    @Published private(set) var currentUserId: String?
    @Published private(set) var isOnboardingComplete = false
    @Published var errorMessage: String?

    private let router: AppRouter
    private let authService: AuthServiceProtocol
    private let userService: UserServiceProtocol

    init(
        router: AppRouter,
        authService: AuthServiceProtocol,
        userService: UserServiceProtocol
    ) {
        self.router = router
        self.authService = authService
        self.userService = userService
    }

    /// `true` when Firebase Auth has a user but Firestore says onboarding is not complete.
    var needsOnboarding: Bool {
        authService.currentUserId != nil && !isOnboardingComplete
    }

    /// Re-evaluates Auth + Firestore and corrects `route` if the user must not see the home feed (T05.5 guardrail).
    func ensureOnboardingCompleteOrRouteToOnboarding() async {
        AppDebugLog.log("ensureOnboardingCompleteOrRouteToOnboarding")
        guard let userId = authService.currentUserId else {
            currentUserId = nil
            isOnboardingComplete = false
            sessionState = .unauthenticated
            router.showOnboarding()
            AppDebugLog.log("ensureOnboardingCompleteOrRouteToOnboarding: no uid → onboarding")
            return
        }
        currentUserId = userId
        await resolveOnboardingState(for: userId)
    }

    /// Call when app returns to foreground to resync with Firestore (remote edits, completion elsewhere).
    func refreshOnSceneBecameActive() async {
        guard authService.currentUserId != nil else { return }
        // Avoid overlapping Firestore reads while cold restore is still in progress.
        guard sessionState != .loading else {
            AppDebugLog.log("refreshOnSceneBecameActive: skipping — session still loading")
            return
        }
        AppDebugLog.log("refreshOnSceneBecameActive: re-validating session + profile")
        await ensureOnboardingCompleteOrRouteToOnboarding()
    }

    func restoreSession() async {
        AppDebugLog.log("restoreSession: begin — clearing error, setting .loading")
        sessionState = .loading
        errorMessage = nil

        guard let userId = authService.currentUserId else {
            AppDebugLog.log("restoreSession: no Firebase Auth user — staying unauthenticated, route onboarding")
            currentUserId = nil
            isOnboardingComplete = false
            sessionState = .unauthenticated
            router.showOnboarding()
            return
        }

        AppDebugLog.log("restoreSession: found existing user uid=\(userId)")
        currentUserId = userId
        await resolveOnboardingState(for: userId)
    }

    func signInWithGoogle() async {
        AppDebugLog.log("signInWithGoogle: begin — setting .loading")
        sessionState = .loading
        errorMessage = nil

        do {
            AppDebugLog.log("signInWithGoogle: calling authService.signIn()")
            try await authService.signIn()
            currentUserId = authService.currentUserId
            AppDebugLog.log("signInWithGoogle: authService.signIn() OK — currentUserId=\(currentUserId ?? "nil")")
            OnboardingAnalytics.logLoginSuccess()

            guard let userId = currentUserId else {
                throw SessionError.missingUserAfterSignIn
            }

            await resolveOnboardingState(for: userId)
        } catch {
            AppDebugLog.log("signInWithGoogle: FAILED — \(error.localizedDescription)")
            OnboardingAnalytics.logSignInFailed(message: error.localizedDescription)
            sessionState = .unauthenticated
            router.showOnboarding()
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        AppDebugLog.log("signOut: begin")
        do {
            try authService.signOut()
            currentUserId = nil
            isOnboardingComplete = false
            sessionState = .unauthenticated
            router.showOnboarding()
            AppDebugLog.log("signOut: success — route onboarding")
        } catch {
            AppDebugLog.log("signOut: FAILED — \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    private func resolveOnboardingState(for userId: String) async {
        AppDebugLog.log("resolveOnboardingState: fetching profile for uid=\(userId)")
        await refreshAuthTokenForFirestoreIfNeeded()
        do {
            let profile = try await userService.fetchProfile(userId: userId)
            errorMessage = nil
            let onboardingComplete = profile?.onboardingCompleteAt != nil
            AppDebugLog.log("resolveOnboardingState: profile=\(profile == nil ? "nil" : "exists") onboardingCompleteAt=\(profile?.onboardingCompleteAt.map { "\($0)" } ?? "nil") → onboardingComplete=\(onboardingComplete)")

            isOnboardingComplete = onboardingComplete
            sessionState = onboardingComplete ? .authenticated : .unauthenticated
            if onboardingComplete {
                router.showHome()
                AppDebugLog.log("resolveOnboardingState: → sessionState=.authenticated route=.home")
            } else {
                router.showOnboarding()
                AppDebugLog.log("resolveOnboardingState: → sessionState=.unauthenticated route=.onboarding (finish onboarding in app)")
            }
        } catch {
            AppDebugLog.log("resolveOnboardingState: fetchProfile FAILED — \(FirestoreErrorMapper.developerDebugLine(for: error))")
            // Fallback: do not block sign-in on profile fetch during early milestones.
            isOnboardingComplete = false
            sessionState = .unauthenticated
            router.showOnboarding()
            errorMessage = FirestoreErrorMapper.userFacingMessage(for: error)
        }
    }

    /// Ensures an ID token is available so Firestore requests aren’t sent before Auth finished restoring credentials.
    private func refreshAuthTokenForFirestoreIfNeeded() async {
        guard let user = Auth.auth().currentUser else { return }
        do {
            _ = try await user.getIDToken()
        } catch {
            AppDebugLog.log("refreshAuthTokenForFirestoreIfNeeded: \(error.localizedDescription)")
        }
    }

    /// Call after T05 profile + onboarding fields are written so routing re-evaluates from Firestore (T05.4).
    func refreshAfterProfileSaved() async {
        guard let userId = authService.currentUserId else {
            AppDebugLog.log("refreshAfterProfileSaved: no uid")
            return
        }
        AppDebugLog.log("refreshAfterProfileSaved: re-fetching profile for uid=\(userId)")
        await resolveOnboardingState(for: userId)
    }
}

enum SessionError: LocalizedError {
    case missingUserAfterSignIn

    var errorDescription: String? {
        switch self {
        case .missingUserAfterSignIn:
            return "Signed in successfully, but no user session was found."
        }
    }
}
