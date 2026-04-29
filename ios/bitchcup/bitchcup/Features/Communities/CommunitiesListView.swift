import SwiftUI

struct CommunitiesListView: View {
    private enum LeagueListSegment: String, CaseIterable, Identifiable {
        case active = "Active"
        case hidden = "Hidden"

        var id: String { rawValue }
    }

    private let rowButtonFont = Font.custom("NeueHaasDisplay-Mediu", size: 22)
    private let leagueListRowFont = Font.custom("NeueHaasDisplay-Mediu", size: 26)
    private let pageTitleFont = Font.custom("NeueHaasDisplay-Bold", size: 42)

    @EnvironmentObject private var container: DependencyContainer
    @EnvironmentObject private var sessionManager: AppSessionManager
    @State private var communities: [CommunityListItem] = []
    @State private var listSegment: LeagueListSegment = .active
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var cursor: CommunitiesPageCursor?
    @State private var hasMore = false
    @State private var isLoadingMore = false
    @State private var loadMoreErrorMessage: String?
    @State private var showCommunitiesFlow = false

    private var currentUserId: String? {
        container.authService.currentUserId
    }

    /// True when the signed-in user created at least one league on this page (shows Active / Hidden).
    private var isCreatorOfAnyListedLeague: Bool {
        guard let uid = currentUserId else { return false }
        return communities.contains { $0.createdByProfileId == uid }
    }

    private func activeRows(from items: [CommunityListItem]) -> [CommunityListItem] {
        items.filter(\.appearsOnActiveTab)
    }

    private func hiddenRows(from items: [CommunityListItem]) -> [CommunityListItem] {
        guard let uid = currentUserId else { return [] }
        return items.filter { $0.appearsInHiddenCreatorList(forCurrentUserId: uid) }
    }

    private var displayedCommunities: [CommunityListItem] {
        if !isCreatorOfAnyListedLeague {
            return activeRows(from: communities)
        }
        switch listSegment {
        case .active: return activeRows(from: communities)
        case .hidden: return hiddenRows(from: communities)
        }
    }

    private var emptyListTitle: String {
        if listSegment == .hidden {
            return "No hidden leagues"
        }
        if !hiddenRows(from: communities).isEmpty {
            return "No active leagues"
        }
        return "No leagues here"
    }

    /// Pill segment matching league list reference (light gray track, white selected chip + light shadow).
    private var leagueSegmentControl: some View {
        HStack(spacing: 4) {
            ForEach(LeagueListSegment.allCases) { segment in
                let selected = listSegment == segment
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        listSegment = segment
                    }
                } label: {
                    Text(segment.rawValue)
                        .font(.custom("NeueHaasDisplay-Mediu", size: 16))
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white)
                                    .shadow(color: Color.black.opacity(0.07), radius: 3, x: 0, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(UIColor.systemGray5))
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("League list")
    }

    private var showLeagueSegmentControl: Bool {
        isCreatorOfAnyListedLeague && !isLoading && errorMessage == nil && !communities.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            pageHeader
            if showLeagueSegmentControl {
                leagueSegmentControl
                    .padding(.horizontal)
                    .padding(.bottom, 16)
            }
            listContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Color.white)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                CommunityFlowBackToolbarButton()
            }
        }
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { await load() }
        .fullScreenCover(isPresented: $showCommunitiesFlow) {
            CommunitiesFlowStack()
                .environmentObject(container)
                .environmentObject(sessionManager)
        }
    }

    private var pageHeader: some View {
        Text("Your Leagues")
            .font(pageTitleFont)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.top, 24)
            .padding(.bottom, showLeagueSegmentControl ? 8 : 24)
    }

    @ViewBuilder
    private var listContent: some View {
        if isLoading {
            LoadingView(message: "Loading leagues...")
        } else if let error = errorMessage {
            ErrorView(message: error) {
                Task { await load() }
            }
        } else if communities.isEmpty {
            emptyNoLeaguesState
        } else if displayedCommunities.isEmpty {
            emptyFilteredListState
        } else {
            leagueList
        }
    }

    private var emptyNoLeaguesState: some View {
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
    }

    private var emptyFilteredListState: some View {
        VStack(spacing: 12) {
            Spacer().frame(maxHeight: 120)
            Text(emptyListTitle)
                .font(.custom("NeueHaasDisplay-Bold", size: 28))
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            if listSegment == .active {
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
                .buttonStyle(.plain)
                .padding(.horizontal, 32)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }

    private var leagueList: some View {
        List(displayedCommunities, id: \.communityId) { community in
            NavigationLink {
                CommunityDetailView(communityId: community.communityId)
            } label: {
                Text(community.name)
                    .font(leagueListRowFont)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
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
            communities = deduped.sorted { lhs, rhs in
                if lhs.name.caseInsensitiveCompare(rhs.name) != .orderedSame {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.communityId < rhs.communityId
            }
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
