import FirebaseAnalytics
import Foundation

/// T11.4: Shared Analytics helpers for major app flows. No PII; use `bcup_`-prefixed custom events and parameters.
enum AppAnalytics {
    private enum Param {
        static let errorSnippet = "bcup_error_snippet"
        static let outcome = "bcup_outcome"
        static let rowCount = "bcup_row_count"
        static let historyCount = "bcup_history_count"
        static let source = "bcup_source"
    }

    private enum Event {
        static let feedRefresh = "bcup_feed_refresh"
        static let feedLoad = "bcup_feed_load"
        static let feedLoadMoreFail = "bcup_feed_load_more_fail"
        static let profileLoad = "bcup_profile_load"
        static let profileLoadMoreFail = "bcup_profile_history_load_more_fail"
        static let authSignOut = "bcup_auth_sign_out"
    }

    // MARK: - Screen views

    static func logScreenView(_ screenName: String, screenClass: String = "SwiftUI") {
        Analytics.logEvent(AnalyticsEventScreenView, parameters: [
            AnalyticsParameterScreenName: screenName,
            AnalyticsParameterScreenClass: screenClass
        ])
    }

    static func logFeedScreen() {
        logScreenView("bcup_feed", screenClass: "FeedView")
    }

    static func logProfileScreen() {
        logScreenView("bcup_profile", screenClass: "ProfileView")
    }

    // MARK: - Feed

    enum FeedLoadOutcome: String {
        case successEmpty = "success_empty"
        case successContent = "success_content"
        case failed = "failed"
    }

    /// Initial or full reload of the home feed (not pull-to-refresh).
    static func logFeedLoad(outcome: FeedLoadOutcome, rowCount: Int? = nil, errorMessage: String? = nil) {
        var params: [String: Any] = [Param.outcome: outcome.rawValue]
        if let rowCount {
            params[Param.rowCount] = rowCount
        }
        if let errorMessage {
            params[Param.errorSnippet] = String(errorMessage.prefix(100))
        }
        Analytics.logEvent(Event.feedLoad, parameters: params)
    }

    static func logFeedRefresh() {
        Analytics.logEvent(Event.feedRefresh, parameters: [Param.source: "pull"])
    }

    static func logFeedLoadMoreFailed(message: String) {
        Analytics.logEvent(Event.feedLoadMoreFail, parameters: [
            Param.errorSnippet: String(message.prefix(100))
        ])
    }

    // MARK: - Profile

    enum ProfileLoadOutcome: String {
        case success = "success"
        case noAuth = "no_auth"
        case failed = "failed"
    }

    static func logProfileLoad(outcome: ProfileLoadOutcome, historyCount: Int? = nil, errorMessage: String? = nil) {
        var params: [String: Any] = [Param.outcome: outcome.rawValue]
        if let historyCount {
            params[Param.historyCount] = historyCount
        }
        if let errorMessage {
            params[Param.errorSnippet] = String(errorMessage.prefix(100))
        }
        Analytics.logEvent(Event.profileLoad, parameters: params)
    }

    static func logProfileHistoryLoadMoreFailed(message: String) {
        Analytics.logEvent(Event.profileLoadMoreFail, parameters: [
            Param.errorSnippet: String(message.prefix(100))
        ])
    }

    // MARK: - Auth

    static func logSignOut() {
        Analytics.logEvent(Event.authSignOut, parameters: nil)
    }
}
