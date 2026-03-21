import SwiftUI
import Foundation

enum AppRoute {
    case onboarding
    case home
}

class AppRouter: ObservableObject {
    @Published var route: AppRoute = .onboarding

    func resolve(onboardingCompleteAt: Date?) {
        if onboardingCompleteAt != nil {
            route = .home
        } else {
            route = .onboarding
        }
    }
}