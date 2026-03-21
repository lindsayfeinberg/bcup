import SwiftUI

enum AppRoute {
    case onboarding
    case home
}

class AppRouter: ObservableObject {
    @Published var route: AppRoute = .onboarding
}