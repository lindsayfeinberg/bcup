import SwiftUI

struct FeedView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var sessionManager: AppSessionManager
    @EnvironmentObject private var container: DependencyContainer

    @State private var showCommunitiesFlow = false
    @State private var showCommunitiesList = false
    @State private var showGameLog = false
    @State private var showProfile = false
    @State private var profilePhotoUrl: URL?

    private enum FeedState {
        case loading
        case error(String)
        case empty
        case content([FeedRow])
    }
    @State private var feedState: FeedState = .loading
    @State private var selectedCommunityId: String? = nil  // nil = All leagues
    @State private var homeFeedCursor: HomeFeedPageCursor?
    @State private var hasMoreFeed = false
    @State private var isLoadingMoreFeed = false
    @State private var loadMoreErrorMessage: String?

    private let headerFont = Font.custom("NeueHaasDisplay-Bold", size: 34)

    // MARK: - Derived

    private var allRows: [FeedRow] {
        if case .content(let rows) = feedState { return rows }
        return []
    }

    private struct FilterOption: Identifiable, Hashable {
        let communityId: String
        let displayName: String
        var id: String { communityId }
    }

    private var filterOptions: [FilterOption] {
        var seen = Set<String>()
        var options: [FilterOption] = []
        for row in allRows {
            if !seen.contains(row.communityId) {
                seen.insert(row.communityId)
                options.append(FilterOption(
                    communityId: row.communityId,
                    displayName: row.communityName ?? row.communityId
                ))
            }
        }
        return options.sorted { $0.displayName < $1.displayName }
    }

    private var filteredRows: [FeedRow] {
        guard let selectedCommunityId else { return allRows }
        return allRows.filter { $0.communityId == selectedCommunityId }
    }

    private var currentFilterLabel: String {
        guard let selectedCommunityId else { return "All leagues" }
        return filterOptions.first { $0.communityId == selectedCommunityId }?.displayName ?? selectedCommunityId
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // MARK: Header
                HStack {
                    Text("BitchCUP")
                        .font(headerFont)
                    Spacer()
                    Menu {
                        Button {
                            showProfile = true
                        } label: {
                            Label("View profile", systemImage: "person")
                        }
                        Button {
                            showCommunitiesList = true
                        } label: {
                            Label("View leagues", systemImage: "person.3")
                        }
                        Divider()
                        Button(role: .destructive) {
                            sessionManager.signOut()
                        } label: {
                            Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        accountMenuAvatar
                    }
                    .accessibilityLabel("Account menu")
                }
                .padding(.horizontal)
                .padding(.top, 18)
                .padding(.bottom, 10)
                .background(Color(.systemBackground).opacity(0.92))

                // MARK: Body
                switch feedState {
                case .loading:
                    LoadingView(message: "Loading feed...")

                case .error(let message):
                    ErrorView(message: message) {
                        Task { await loadInitialFeed() }
                    }

                case .empty:
                    VStack(spacing: 10) {
                        Spacer()
                        Text("No games yet")
                            .font(.custom("NeueHaasDisplay-Bold", size: 32))
                            .multilineTextAlignment(.center)
                        Text("Log a game or join a league to see activity.")
                            .font(.custom("NeueHaasDisplay-Light", size: 18))
                            .foregroundStyle(.black)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                        Spacer()
                    }
                    .offset(y: -22)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .content:
                    VStack(spacing: 0) {

                        // MARK: Filter bar
                        if filterOptions.count > 1 {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    FilterChip(
                                        label: "All leagues",
                                        isSelected: selectedCommunityId == nil
                                    ) {
                                        selectedCommunityId = nil
                                    }
                                    ForEach(filterOptions) { option in
                                        FilterChip(
                                            label: option.displayName,
                                            isSelected: selectedCommunityId == option.communityId
                                        ) {
                                            selectedCommunityId = option.communityId
                                        }
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                            }
                            .accessibilityLabel("Feed filter")
                        }

                        // MARK: Feed list or filtered empty state
                        if filteredRows.isEmpty {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "tray")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("No games in this league yet.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                            Spacer()
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 12) {
                                    ForEach(Array(filteredRows.enumerated()), id: \.element.id) { index, row in
                                        FeedCardView(row: row)
                                            .onAppear {
                                                Task {
                                                    await loadMoreFeedIfNeeded(currentRow: row)
                                                    await prefetchUpcomingCards(from: index, rows: filteredRows)
                                                }
                                            }
                                    }

                                    feedFooter
                                }
                                .padding(.horizontal)
                                .padding(.top, 8)
                                .padding(.bottom, 16)
                            }
                            .refreshable {
                                await refreshFeed()
                            }
                        }
                    }
                }

                // MARK: Bottom actions
                HStack(spacing: 0) {
                    Button {
                        showCommunitiesFlow = true
                    } label: {
                        Text("Leagues")
                            .font(.custom("NeueHaasDisplay-Mediu", size: 20))
                            .frame(width: 150)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(FeedPrimaryActionButtonStyle())
                    
                    Spacer(minLength: 28)

                    Button {
                        showGameLog = true
                    } label: {
                        Text("Log Game")
                            .font(.custom("NeueHaasDisplay-Mediu", size: 20))
                            .frame(width: 150)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(FeedPrimaryActionButtonStyle())
                }
                .padding(.horizontal, 8)
                .padding(.bottom)
            }
            .background {
                if case .empty = feedState {
                    Image("blank_background")
                        .resizable()
                        .scaledToFill()
                        .padding(.top, 136)
                        .padding(.bottom, 52)
                }
            }
            .fullScreenCover(isPresented: $showCommunitiesFlow) {
                CommunitiesFlowStack()
                    .environmentObject(container)
            }
            .navigationDestination(isPresented: $showCommunitiesList) {
                CommunitiesListView()
            }
            .navigationDestination(isPresented: $showGameLog) {
                GameLogCaptureEntryView()
            }
            .navigationDestination(isPresented: $showProfile) {
                ProfileView()
            }
            .task {
                await sessionManager.ensureOnboardingCompleteOrRouteToOnboarding()
                await loadInitialFeed()
                await loadProfilePhoto()
            }
            .onChange(of: showGameLog) { wasShowing, isShowing in
                if wasShowing && !isShowing {
                    Task { await loadInitialFeed() }
                }
            }
            .onChange(of: showCommunitiesFlow) { wasShowing, isShowing in
                if wasShowing && !isShowing {
                    Task { await loadInitialFeed() }
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .background else { return }
                Task {
                    await ImageLoadTelemetry.shared.flushFeedSessionMedian(reason: "scene_background")
                }
            }
            .onDisappear {
                Task {
                    await ImageLoadTelemetry.shared.flushFeedSessionMedian(reason: "feed_disappear")
                }
            }
        }
    }

    @ViewBuilder
    private var accountMenuAvatar: some View {
        if let profilePhotoUrl {
            let transformedURL = ImageVariantURLBuilder.variantURL(from: profilePhotoUrl, variant: .avatar)
            AsyncImage(url: transformedURL) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(width: 38, height: 38)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    AsyncImage(url: profilePhotoUrl) { fallbackPhase in
                        switch fallbackPhase {
                        case .success(let fallbackImage):
                            fallbackImage
                                .resizable()
                                .scaledToFill()
                        default:
                            Image(systemName: "person.circle.fill")
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(.primary)
                        }
                    }
                @unknown default:
                    Image(systemName: "person.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.primary)
                }
            }
            .frame(width: 38, height: 38)
            .clipShape(Circle())
        } else {
            Image(systemName: "person.circle.fill")
                .font(.title)
                .foregroundStyle(.primary)
        }
    }
}

private struct FeedPrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(red: 180.0 / 255.0, green: 61.0 / 255.0, blue: 37.0 / 255.0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white, lineWidth: 2)
            )
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Load

extension FeedView {
    private func loadInitialFeed() async {
        feedState = .loading
        homeFeedCursor = nil
        hasMoreFeed = false
        loadMoreErrorMessage = nil
        do {
            let page = try await container.feedService.fetchFeedPage(cursor: nil, pageSize: 20)
            let rows = page.items
            // After reload, keep selected filter only if still valid
            if let selected = selectedCommunityId {
                let stillValid = rows.contains { $0.communityId == selected }
                if !stillValid { selectedCommunityId = nil }
            }
            homeFeedCursor = page.nextCursor
            hasMoreFeed = page.hasMore
            feedState = rows.isEmpty ? .empty : .content(rows)
        } catch {
            feedState = .error(error.localizedDescription)
            AppDebugLog.log("FeedView.loadFeed error: \(error.localizedDescription)")
        }
    }

    private func refreshFeed() async {
        await loadInitialFeed()
    }

    private func loadMoreFeedIfNeeded(currentRow: FeedRow) async {
        guard hasMoreFeed, !isLoadingMoreFeed else { return }
        guard case .content(let rows) = feedState else { return }
        let visibleRows: [FeedRow]
        if let selectedCommunityId {
            visibleRows = rows.filter { $0.communityId == selectedCommunityId }
        } else {
            visibleRows = rows
        }
        guard loadMoreTriggerRows(rows: visibleRows).contains(currentRow.id) else { return }
        await loadMoreFeed()
    }

    private func loadMoreFeed() async {
        guard hasMoreFeed, !isLoadingMoreFeed else { return }
        guard case .content(let rows) = feedState else { return }

        isLoadingMoreFeed = true
        loadMoreErrorMessage = nil
        defer { isLoadingMoreFeed = false }

        do {
            let page = try await container.feedService.fetchFeedPage(cursor: homeFeedCursor, pageSize: 20)
            let merged = dedupedRows(rows + page.items)
            feedState = .content(merged)
            homeFeedCursor = page.nextCursor
            hasMoreFeed = page.hasMore
        } catch {
            loadMoreErrorMessage = error.localizedDescription
        }
    }

    private func loadMoreTriggerRows(rows: [FeedRow]) -> Set<String> {
        guard !rows.isEmpty else { return [] }
        return Set(rows.suffix(3).map(\.id))
    }

    private func dedupedRows(_ rows: [FeedRow]) -> [FeedRow] {
        let unique = Dictionary(grouping: rows, by: \.gameLogId).compactMap { $0.value.first }
        return unique.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt { return lhs.gameLogId > rhs.gameLogId }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func prefetchUpcomingCards(from currentIndex: Int, rows: [FeedRow]) async {
        guard currentIndex < rows.count - 1 else { return }
        let lookaheadCardCount = 4
        let photosPerCard = 2
        let nextRows = rows.dropFirst(currentIndex + 1).prefix(lookaheadCardCount)

        var urlsToPrefetch: [URL] = []
        for row in nextRows {
            let rawURLs = row.photoUrls.compactMap(URL.init(string:)).prefix(photosPerCard)
            for originalURL in rawURLs {
                if ImageDeliveryConfig.isTransformedDeliveryEnabled {
                    urlsToPrefetch.append(ImageVariantURLBuilder.variantURL(from: originalURL, variant: .feedThumb))
                } else {
                    urlsToPrefetch.append(originalURL)
                }
            }
        }
        await ImagePrefetcher.shared.prefetch(urls: urlsToPrefetch, limit: lookaheadCardCount * photosPerCard)
    }

    private func loadProfilePhoto() async {
        guard let userId = container.authService.currentUserId else {
            profilePhotoUrl = nil
            return
        }
        do {
            let profile = try await container.userService.fetchProfile(userId: userId)
            profilePhotoUrl = profile?.profilePhotoUrl.flatMap(URL.init(string:))
        } catch {
            profilePhotoUrl = nil
        }
    }
}

private extension FeedView {
    @ViewBuilder
    var feedFooter: some View {
        if isLoadingMoreFeed {
            ProgressView("Loading more...")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 12)
        } else if let loadMoreErrorMessage {
            VStack(spacing: 8) {
                Text(loadMoreErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Retry loading more") {
                    Task { await loadMoreFeed() }
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        } else if !hasMoreFeed, !filteredRows.isEmpty {
            Text("You're all caught up.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(label)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isSelected ? Color.primary : Color(.systemGray5))
                .foregroundStyle(isSelected ? Color(.systemBackground) : Color.primary)
                .clipShape(Capsule())
        }
        .accessibilityLabel("Filter by \(label)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
