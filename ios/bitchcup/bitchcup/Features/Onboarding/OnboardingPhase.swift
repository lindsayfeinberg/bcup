import Foundation

/// Which screen to show inside the onboarding stack (T05).
enum OnboardingPhase: Equatable {
    /// Firebase Auth + Google Sign-In not completed.
    case signInWithGoogle
    /// User is signed in but must confirm 21+ (writes partial profile if needed).
    case ageConfirmation
    /// Display name + optional profile photo, then mark onboarding complete.
    case profileSetup
}
