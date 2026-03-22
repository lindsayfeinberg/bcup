import SwiftUI

/// Full navigation for “Your Communities”: entry → create or join → detail on success.
struct CommunitiesFlowStack: View {
    @EnvironmentObject private var container: DependencyContainer
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            CommunitiesEntryView(path: $path)
                .navigationDestination(for: CommunityRoute.self) { route in
                    switch route {
                    case .create:
                        CreateCommunityFlowView { communityId in
                            path = NavigationPath()
                            path.append(CommunityRoute.detail(communityId: communityId))
                        }
                        .environmentObject(container)
                    case .join:
                        JoinCommunityFlowView { communityId in
                            path = NavigationPath()
                            path.append(CommunityRoute.detail(communityId: communityId))
                        }
                        .environmentObject(container)
                    case .detail(let communityId):
                        CommunityDetailView(communityId: communityId)
                    }
                }
        }
    }
}
