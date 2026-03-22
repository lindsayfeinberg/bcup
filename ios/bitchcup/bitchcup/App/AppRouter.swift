import SwiftUI
import Foundation

enum AppRoute {
    case onboarding
    case home
}

/// High-level session for root UI (see `AppSessionManager`).
/// - `loading`: Initial `restoreSession()` in progress; avoid showing main chrome.
/// - `unauthenticated`: No Firebase user **or** user is signed in but onboarding is not finished
///   (`profiles/{uid}.onboardingCompleteAt` missing). Prefer `needsOnboarding` to distinguish.
/// - `authenticated`: Signed in and Firestore profile has `onboardingCompleteAt`.
enum SessionState {
    case loading
    case unauthenticated
    case authenticated
}

@MainActor
final class AppRouter: ObservableObject {
    @Published var route: AppRoute = .onboarding

    func showOnboarding() {
        AppDebugLog.log("AppRouter.showOnboarding: setting route=.onboarding")
        route = .onboarding
    }

    func showHome() {
        AppDebugLog.log("AppRouter.showHome: setting route=.home")
        route = .home
    }
}