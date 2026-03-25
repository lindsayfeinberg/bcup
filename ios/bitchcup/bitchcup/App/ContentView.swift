import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var sessionManager: AppSessionManager

    var body: some View {
        Group {
            if UITestRuntime.isEnabled {
                switch UITestRuntime.scenario {
                case .gameLog:
                    NavigationStack {
                        NewGameLogFormView(
                            frontPhotoData: UIImage(systemName: "photo")?.jpegData(compressionQuality: 0.8),
                            backPhotoData: UIImage(systemName: "photo")?.jpegData(compressionQuality: 0.8)
                        )
                    }
                case .bracket:
                    NavigationStack {
                        CommunityDetailView(communityId: "ui-community-1")
                    }
                default:
                    onboardingOrHomeContent
                }
            } else {
                onboardingOrHomeContent
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
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await sessionManager.refreshOnSceneBecameActive()
            }
        }
    }

    @ViewBuilder
    private var onboardingOrHomeContent: some View {
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
}