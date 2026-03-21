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
class AppRouter: ObservableObject {
    @Published var route: AppRoute = .onboarding
    @Published var sessionState: SessionState = .loading

    func resolve(onboardingCompleteAt: Date?) {
        if onboardingCompleteAt != nil {
            route = .home
            sessionState = .authenticated
        } else {
            route = .onboarding
            sessionState = .unauthenticated
        }
    }
}