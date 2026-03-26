import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var sessionManager: AppSessionManager
    private var isHarness: Bool { UITestRuntime.participatesInUiTestHarness }
    private var harnessScenario: UITestScenario? { UITestRuntime.harnessScenario }

    var body: some View {
        Group {
            if isHarness {
                // Explicit equality avoids any ambiguity switching on `UITestScenario?`.
                if harnessScenario == .gameLog {
                    NavigationStack {
                        NewGameLogFormView(
                            frontPhotoData: UIImage(systemName: "photo")?.jpegData(compressionQuality: 0.8),
                            backPhotoData: UIImage(systemName: "photo")?.jpegData(compressionQuality: 0.8)
                        )
                    }
                } else if harnessScenario == .bracket {
                    NavigationStack {
                        CommunityDetailView(communityId: "ui-community-1")
                    }
                } else {
                    onboardingOrHomeContent
                }
            } else {
                onboardingOrHomeContent
            }
        }
        .onAppear {
            AppDebugLog.log("ContentView: harness=\(isHarness) scenario=\(String(describing: harnessScenario))")
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