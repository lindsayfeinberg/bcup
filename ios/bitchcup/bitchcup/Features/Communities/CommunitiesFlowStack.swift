import SwiftUI

struct CommunitiesFlowStack: View {
    @EnvironmentObject private var container: DependencyContainer
    @StateObject private var navigator = CommunitiesNavigator()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack(path: $navigator.path) {
            CommunitiesEntryView(path: $navigator.path)
                .navigationDestination(for: CommunityRoute.self) { route in
                    switch route {
                    case .create:
                        CreateCommunityFlowView(onSuccess: { _, _, _ in })
                            .environmentObject(container)
                            .environmentObject(navigator)

                    case .join:
                        JoinCommunityFlowView { communityId in
                            navigator.navigateToDetail(communityId: communityId)
                        }
                        .environmentObject(container)
                        .environmentObject(navigator)

                    case .invite(let communityId, let inviteCode, let inviteLink):
                        InviteView(
                            communityId: communityId,
                            inviteCode: inviteCode,
                            inviteLink: inviteLink
                        ) {
                            navigator.navigateToDetail(communityId: communityId)
                        }

                    case .detail(let communityId):
                        CommunityDetailView(communityId: communityId)
                    
                    case .list:
                        CommunitiesListView()
                            .environmentObject(container)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Close") {
                            dismiss()
                        }
                    }
                }
        }
        .environmentObject(navigator)
    }
}
