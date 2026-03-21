import SwiftUI
import Foundation

enum AppRoute {
    case onboarding
    case home
}

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