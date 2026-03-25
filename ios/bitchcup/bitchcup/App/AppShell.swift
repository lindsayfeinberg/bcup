import SwiftUI

/// Defers building `DependencyContainer` / session until the first view `task` so `ProcessInfo` (UI test env + argv) is populated.
@MainActor
final class AppShell: ObservableObject {
    @Published private(set) var router: AppRouter?
    @Published private(set) var container: DependencyContainer?
    @Published private(set) var sessionManager: AppSessionManager?

    func bootstrapIfNeeded() {
        guard container == nil else { return }

        if let scenario = UITestRuntime.harnessScenario {
            let (c, r, s) = UITestContainerFactory.makeContainer(for: scenario)
            container = c
            router = r
            sessionManager = s
            return
        }

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
    }
}
