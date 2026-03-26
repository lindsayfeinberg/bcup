import Foundation

enum UITestScenario: String {
    case onboarding
    case gameLog
    case bracket
}

enum UITestRuntime {
    /// `UI_TESTING=1` and/or `UI_TESTING` argv — used for analytics / strict gating where needed.
    static var isEnabled: Bool {
        if ProcessInfo.processInfo.environment["UI_TESTING"] == "1" { return true }
        let args = ProcessInfo.processInfo.arguments
        return args.contains("UI_TESTING") || args.contains("-UI_TESTING")
    }

    /// True when UI tests are driving the app: explicit `UI_TESTING`, or XCTest `UI_TEST_USER_ID` + `UI_TEST_SCENARIO` env pair.
    static var participatesInUiTestHarness: Bool {
        if isEnabled { return true }
        let uid = ProcessInfo.processInfo.environment["UI_TEST_USER_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard uid != nil, !(uid ?? "").isEmpty else { return false }
        return parseScenarioFromProcess() != nil
    }

    /// Scenario for `ContentView` routing and `AppShell` DI when the harness is active.
    static var harnessScenario: UITestScenario? {
        guard participatesInUiTestHarness else { return nil }
        return parseScenarioFromProcess()
    }

    /// Prefer `-UI_TEST_SCENARIO <name>` argv, then `UI_TEST_SCENARIO=…` argv, then `UI_TEST_SCENARIO` env.
    private static func parseScenarioFromProcess() -> UITestScenario? {
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "-UI_TEST_SCENARIO"), idx + 1 < args.count {
            if let s = UITestScenario(rawValue: args[idx + 1]) { return s }
        }
        for arg in args where arg.hasPrefix("UI_TEST_SCENARIO=") {
            let raw = String(arg.dropFirst("UI_TEST_SCENARIO=".count))
            if let s = UITestScenario(rawValue: raw) { return s }
        }
        if let raw = ProcessInfo.processInfo.environment["UI_TEST_SCENARIO"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return UITestScenario(rawValue: raw)
        }
        return nil
    }

    /// Prefer this for “who am I?” in forms when `Auth` may be nil (UI tests always set `UI_TEST_USER_ID`).
    static var currentUserIdFallback: String? {
        let v = ProcessInfo.processInfo.environment["UI_TEST_USER_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let v, !v.isEmpty else { return nil }
        return v
    }
}
