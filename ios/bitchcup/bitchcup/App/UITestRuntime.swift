import Foundation

enum UITestScenario: String {
    case onboarding
    case gameLog
    case bracket
}

enum UITestRuntime {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("UI_TESTING")
    }

    static var scenario: UITestScenario? {
        guard isEnabled else { return nil }
        guard let raw = ProcessInfo.processInfo.environment["UI_TEST_SCENARIO"] else { return nil }
        return UITestScenario(rawValue: raw)
    }

    static var currentUserIdFallback: String? {
        guard isEnabled else { return nil }
        return ProcessInfo.processInfo.environment["UI_TEST_USER_ID"]
    }
}

