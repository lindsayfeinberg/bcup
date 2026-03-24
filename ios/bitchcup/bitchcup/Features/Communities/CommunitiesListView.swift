import SwiftUI

struct CommunitiesListView: View {
    @EnvironmentObject private var container: DependencyContainer
    @State private var communities: [(communityId: String, name: String)] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var cursor: CommunitiesPageCursor?
    @State private var hasMore = false
    @State private var isLoadingMore = false
    @State private var loadMoreErrorMessage: String?
    @State private var showCommunitiesFlow = false

    var body: some View {
        Group {
            if isLoading {
                LoadingView(message: "Loading leagues...")
            } else if let error = errorMessage {
                ErrorView(message: error) {
                    Task { await load() }
                }
            } else if communities.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                        .frame(maxHeight: 165)
                    Text("No leagues yet")
                        .font(.custom("NeueHaasDisplay-Bold", size: 32))
                        .multilineTextAlignment(.center)
                    Button("Join or Create League") {
                        showCommunitiesFlow = true
                    }
                    .font(.custom("NeueHaasDisplay-Bold", size: 24))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(red: 180.0 / 255.0, green: 61.0 / 255.0, blue: 37.0 / 255.0))
                    )
                    .buttonStyle(.plain)
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(communities, id: \.communityId) { community in
                    NavigationLink(community.name) {
                        CommunityDetailView(communityId: community.communityId)
                    }
                    .onAppear {
                        Task { await loadMoreIfNeeded(currentCommunityId: community.communityId) }
                    }
                }
                .overlay(alignment: .bottom) {
                    footer
                }
            }
        }
        .navigationTitle("Your Leagues")
        .navigationBarTitleDisplayMode(.inline)
        .background {
            if communities.isEmpty, errorMessage == nil, !isLoading {
                Image("no_leagues_background")
                    .resizable()
                    .scaledToFill()
                    .padding(.vertical, 12)
            }
        }
        .task { await load() }
        .fullScreenCover(isPresented: $showCommunitiesFlow) {
            CommunitiesFlowStack()
                .environmentObject(container)
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        cursor = nil
        hasMore = false
        loadMoreErrorMessage = nil
        do {
            let page = try await container.communityService.fetchCommunitiesPage(cursor: nil, pageSize: 25)
            communities = page.items
            cursor = page.nextCursor
            hasMore = page.hasMore
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func loadMoreIfNeeded(currentCommunityId: String) async {
        guard hasMore, !isLoadingMore else { return }
        guard Set(communities.suffix(3).map(\.communityId)).contains(currentCommunityId) else { return }

        isLoadingMore = true
        loadMoreErrorMessage = nil
        defer { isLoadingMore = false }
        do {
            let page = try await container.communityService.fetchCommunitiesPage(cursor: cursor, pageSize: 25)
            communities += page.items
            let deduped = Dictionary(grouping: communities, by: \.communityId).compactMap { $0.value.first }
            communities = deduped.sorted { $0.name < $1.name }
            cursor = page.nextCursor
            hasMore = page.hasMore
        } catch {
            loadMoreErrorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private var footer: some View {
        if isLoadingMore {
            ProgressView("Loading more...")
                .padding(.bottom, 12)
        } else if let loadMoreErrorMessage {
            VStack(spacing: 8) {
                Text(loadMoreErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Retry loading more") {
                    Task {
                        if let last = communities.last?.communityId {
                            await loadMoreIfNeeded(currentCommunityId: last)
                        }
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding(.bottom, 12)
        } else if !hasMore, !communities.isEmpty {
            Text("No more leagues.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)
        }
    }
}
