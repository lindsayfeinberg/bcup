import SwiftUI

/// Builds `DependencyContainer` / session after a short async delay so XCTest `launchEnvironment` / argv are visible in `ProcessInfo` before the first `ContentView` appears.
@MainActor
final class AppShell: ObservableObject {
    @Published private(set) var router: AppRouter?
    @Published private(set) var container: DependencyContainer?
    @Published private(set) var sessionManager: AppSessionManager?
    /// When false, the root shows only the background so we never paint `ContentView` with a mistaken production container.
    @Published private(set) var hasAttachedUi = false

    func bootstrapIfNeeded() {
        AppDebugLog.log(
            "AppShell.bootstrapIfNeeded: UI_TESTING=\(ProcessInfo.processInfo.environment["UI_TESTING"] ?? "nil") " +
            "UI_TEST_SCENARIO=\(ProcessInfo.processInfo.environment["UI_TEST_SCENARIO"] ?? "nil") " +
            "UI_TEST_USER_ID=\(ProcessInfo.processInfo.environment["UI_TEST_USER_ID"] ?? "nil") " +
            "harnessScenario=\(String(describing: UITestRuntime.harnessScenario))"
        )
        if let scenario = UITestRuntime.harnessScenario {
            let (c, r, s) = UITestContainerFactory.makeContainer(for: scenario)
            container = c
            router = r
            sessionManager = s
            AppDebugLog.log("AppShell.bootstrapIfNeeded: selected UITest mock container for scenario=\(scenario.rawValue)")
            return
        }

        guard container == nil else { return }

        let r = AppRouter()
        let c = DependencyContainer()
        let s = AppSessionManager(
            router: r,
            authService: c.authService,
            userService: c.userService
        )
        container = c
        router = r
        sessionManager = s
        AppDebugLog.log("AppShell.bootstrapIfNeeded: selected production container")
    }

    /// Waits briefly so UI-test process info is populated, then bootstraps and allows `ContentView` to mount.
    func prepareFirstFrame() async {
        guard !hasAttachedUi else { return }
        let env = ProcessInfo.processInfo.environment
        let isUITestProcess = env["XCTestConfigurationFilePath"] != nil ||
            env["UI_TESTING"] == "1" ||
            env["UI_TEST_USER_ID"] != nil

        if isUITestProcess {
            // In UI tests, launch env/argv can show up a bit after process start.
            // Poll briefly to avoid locking into production DI.
            for _ in 0..<30 {
                if UITestRuntime.harnessScenario != nil { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        bootstrapIfNeeded()
        if router != nil, container != nil, sessionManager != nil {
            hasAttachedUi = true
            AppDebugLog.log("AppShell.prepareFirstFrame: hasAttachedUi=true")
        }
    }
}
