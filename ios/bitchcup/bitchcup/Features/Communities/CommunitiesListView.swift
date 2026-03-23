import SwiftUI

struct CommunitiesListView: View {
    @EnvironmentObject private var container: DependencyContainer
    @State private var communities: [(communityId: String, name: String)] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                LoadingView(message: "Loading leagues...")
            } else if let error = errorMessage {
                ErrorView(message: error) {
                    Task { await load() }
                }
            } else if communities.isEmpty {
                EmptyStateView(
                    title: "No leagues yet",
                    message: "Create or join a league to get started.",
                    actionLabel: nil
                )
            } else {
                List(communities, id: \.communityId) { community in
                    NavigationLink(community.name) {
                        CommunityDetailView(communityId: community.communityId)
                    }
                }
            }
        }
        .navigationTitle("Your Leagues")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            communities = try await container.communityService.fetchCommunities()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
