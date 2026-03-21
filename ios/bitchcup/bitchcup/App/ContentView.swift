import SwiftUI

struct ContentView: View {
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var sessionManager: AppSessionManager

    var body: some View {
        Group {
            switch sessionManager.sessionState {
            case .loading:
                LoadingView(message: "Checking session...")
            case .unauthenticated, .authenticated:
                switch router.route {
                case .onboarding:
                    OnboardingView()
                case .home:
                    FeedView()
                }
            }
        }
        .onAppear {
            AppDebugLog.log("ContentView: onAppear sessionState=\(String(describing: sessionManager.sessionState)) route=\(String(describing: router.route))")
        }
        .onChange(of: sessionManager.sessionState) { _, newValue in
            AppDebugLog.log("ContentView: sessionState changed → \(String(describing: newValue))")
        }
        .onChange(of: router.route) { _, newValue in
            AppDebugLog.log("ContentView: route changed → \(String(describing: newValue))")
        }
    }
}