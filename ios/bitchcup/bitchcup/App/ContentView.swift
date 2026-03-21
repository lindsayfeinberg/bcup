import SwiftUI

struct ContentView: View {
    @EnvironmentObject var router: AppRouter

    var body: some View {
        switch router.route {
        case .onboarding:
            OnboardingView()
        case .home:
            FeedView()
        }
    }
}