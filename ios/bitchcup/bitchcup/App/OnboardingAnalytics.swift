import FirebaseAnalytics
import Foundation

/// T05.6: Firebase Analytics for the onboarding funnel. No user IDs, emails, or display names.
enum OnboardingAnalytics {
    private enum CustomEvent {
        static let signInTap = "onb_sign_in_tap"
        static let signInFail = "onb_sign_in_fail"
        static let ageConfirmOk = "onb_age_confirm_ok"
        static let ageConfirmFail = "onb_age_confirm_fail"
        static let profileSubmitOk = "onb_profile_submit_ok"
        static let profileSubmitFail = "onb_profile_submit_fail"
        static let funnelComplete = "onb_funnel_complete"
    }

    private enum Param {
        static let photoAdded = "photo_added"
        static let errorSnippet = "error_snippet"
    }

    // MARK: - Sign-in

    static func logSignInButtonTapped() {
        Analytics.logEvent(CustomEvent.signInTap, parameters: nil)
    }

    /// Standard login event (recommended by Firebase) after Google → Firebase Auth succeeds.
    static func logLoginSuccess() {
        Analytics.logEvent(AnalyticsEventLogin, parameters: [
            AnalyticsParameterMethod: "google.com"
        ])
    }

    /// Truncated error text only — avoid logging tokens or PII.
    static func logSignInFailed(message: String) {
        let snippet = String(message.prefix(100))
        Analytics.logEvent(CustomEvent.signInFail, parameters: [
            Param.errorSnippet: snippet
        ])
    }

    // MARK: - Screen / step

    static func logOnboardingScreen(_ phase: OnboardingPhase) {
        let name: String
        switch phase {
        case .signInWithGoogle: name = "OnboardingSignIn"
        case .ageConfirmation: name = "OnboardingAgeGate"
        case .profileSetup: name = "OnboardingProfileSetup"
        }
        Analytics.logEvent(AnalyticsEventScreenView, parameters: [
            AnalyticsParameterScreenName: name,
            AnalyticsParameterScreenClass: "OnboardingView"
        ])
    }

    // MARK: - Age gate

    static func logAgeConfirmed() {
        Analytics.logEvent(CustomEvent.ageConfirmOk, parameters: nil)
    }

    static func logAgeConfirmFailed() {
        Analytics.logEvent(CustomEvent.ageConfirmFail, parameters: nil)
    }

    // MARK: - Profile

    static func logProfileSubmitted(photoAdded: Bool) {
        Analytics.logEvent(CustomEvent.profileSubmitOk, parameters: [
            Param.photoAdded: photoAdded ? "true" : "false"
        ])
    }

    static func logProfileSubmitFailed() {
        Analytics.logEvent(CustomEvent.profileSubmitFail, parameters: nil)
    }

    /// Fires once when the user finishes profile setup and is routed to home (not on every cold start).
    static func logOnboardingFunnelComplete() {
        Analytics.logEvent(CustomEvent.funnelComplete, parameters: nil)
    }
}
