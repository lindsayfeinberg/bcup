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
                            leagueName: nil,
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
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            dismiss()
                        } label: {
                            Text("Home")
                                .font(.custom("NeueHaasDisplay-Mediu", size: 16))
                                .foregroundStyle(Color(red: 41.0 / 255.0, green: 0.0 / 255.0, blue: 3.0 / 255.0))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
        }
        .environmentObject(navigator)
    }
}
