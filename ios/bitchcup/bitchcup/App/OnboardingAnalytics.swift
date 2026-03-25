import FirebaseAnalytics
import Foundation

/// T05.6 / T11.4: Firebase Analytics for the onboarding funnel. No user IDs, emails, or display names.
enum OnboardingAnalytics {
    private enum CustomEvent {
        static let signInTap = "bcup_onb_sign_in_tap"
        static let signInFail = "bcup_onb_sign_in_fail"
        static let ageConfirmOk = "bcup_onb_age_confirm_ok"
        static let ageConfirmFail = "bcup_onb_age_confirm_fail"
        static let profileSubmitOk = "bcup_onb_profile_submit_ok"
        static let profileSubmitFail = "bcup_onb_profile_submit_fail"
        static let funnelComplete = "bcup_onb_funnel_complete"
    }

    private enum Param {
        static let photoAdded = "bcup_photo_added"
        static let errorSnippet = "bcup_error_snippet"
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
        case .signInWithGoogle: name = "bcup_onb_sign_in"
        case .ageConfirmation: name = "bcup_onb_age_gate"
        case .profileSetup: name = "bcup_onb_profile_setup"
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
