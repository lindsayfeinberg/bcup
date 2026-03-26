import SwiftUI

struct CommunitiesListView: View {
    private let rowButtonFont = Font.custom("NeueHaasDisplay-Mediu", size: 22)
    private let leagueListRowFont = Font.custom("NeueHaasDisplay-Mediu", size: 26)
    private let pageTitleFont = Font.custom("NeueHaasDisplay-Bold", size: 42)

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
        VStack(alignment: .leading, spacing: 0) {
            Text("Your Leagues")
                .font(pageTitleFont)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 24)
                .padding(.bottom, 28)

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
                            .foregroundStyle(.black)
                            .multilineTextAlignment(.center)
                        Button("Join or Create League") {
                            showCommunitiesFlow = true
                        }
                        .font(rowButtonFont)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(red: 180.0 / 255.0, green: 61.0 / 255.0, blue: 37.0 / 255.0))
                        )
                        .contentShape(Rectangle())
                        .buttonStyle(.plain)
                        .padding(.horizontal, 32)
                        .padding(.top, 8)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)
                } else {
                    List(communities, id: \.communityId) { community in
                        NavigationLink {
                            CommunityDetailView(communityId: community.communityId)
                        } label: {
                            Text(community.name)
                                .font(leagueListRowFont)
                                .foregroundStyle(.black)
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.white)
                        .onAppear {
                            Task { await loadMoreIfNeeded(currentCommunityId: community.communityId) }
                        }
                    }
                    .listStyle(.plain)
                    .listSectionSeparator(.hidden)
                    .scrollContentBackground(.hidden)
                    .background(Color.white)
                    .tint(.black)
                    .overlay(alignment: .bottom) {
                        footer
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Color.white)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
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
        }
    }
}
