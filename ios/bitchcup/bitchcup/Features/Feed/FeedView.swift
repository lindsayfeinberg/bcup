import SwiftUI

private struct GameLogEditSheetItem: Identifiable {
    let id: String
}

private struct ViewingLiveStream: Identifiable {
    let stream: LiveStreamSummary
    let communityName: String
    let session: LiveStreamSession
    var id: String { stream.streamId }
}

struct FeedView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var sessionManager: AppSessionManager
    @EnvironmentObject private var container: DependencyContainer

    @State private var showCommunitiesFlow = false
    @State private var showCommunitiesList = false
    @State private var showGameLog = false
    @State private var showGoLive = false
    @State private var pendingLiveStreamCommunityId: String?
    @State private var showProfile = false
    @State private var showGameRulesExplainer = false
    @State private var showAccountMenu = false
    @State private var showPlatformAdmin = false
    @State private var profilePhotoUrl: URL?
    @State private var gameLogEditSheet: GameLogEditSheetItem?
    @State private var liveStreams: [LiveStreamSummary] = []
    @State private var liveStreamCommunityNames: [String: String] = [:]
    @State private var liveStreamCommunityIds: [String] = []
    @State private var viewingLiveStream: ViewingLiveStream?
    @State private var joiningStreamId: String?
    @State private var joinLiveStreamErrorMessage: String?

    private enum FeedState {
        case loading
        case error(String)
        case empty
        case content([FeedRow])
    }
    @State private var feedState: FeedState = .loading
    /// Empty set = show all leagues; otherwise only rows whose `communityId` is in the set.
    @State private var selectedCommunityIds: Set<String> = []
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

    private var filteredRows: [FeedRow] {
        if selectedCommunityIds.isEmpty { return allRows }
        return allRows.filter { selectedCommunityIds.contains($0.communityId) }
    }

    @ViewBuilder
    private var feedBottomActions: some View {
        HStack(spacing: 10) {
            Button {
                showCommunitiesFlow = true
            } label: {
                Text("Leagues")
                    .font(.custom("NeueHaasDisplay-Mediu", size: 18))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(FeedPrimaryActionButtonStyle())
            .accessibilityIdentifier("feed.leagues")

            Button {
                showGoLive = true
            } label: {
                Text("Go Live")
                    .font(.custom("NeueHaasDisplay-Mediu", size: 18))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(FeedPrimaryActionButtonStyle())
            .accessibilityIdentifier("feed.goLive")

            Button {
                showGameLog = true
            } label: {
                Text("Log Game")
                    .font(.custom("NeueHaasDisplay-Mediu", size: 18))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(FeedPrimaryActionButtonStyle())
            .accessibilityIdentifier("feed.logGame")
        }
        .padding(.horizontal, 8)
        .padding(.bottom)
        .background(Color.clear)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // MARK: Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Bitch Cup")
                            .font(headerFont)
                            .onLongPressGesture(minimumDuration: 0.85) {
                                guard sessionManager.isPlatformAdmin else { return }
                                showPlatformAdmin = true
                            }
                        Button {
                            showGameRulesExplainer = true
                        } label: {
                            Text("How each game works")
                                .font(.custom("NeueHaasDisplay-Mediu", size: 15))
                                .foregroundStyle(FeedBrand.primaryButtonRed)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("feed.howGamesWork")
                    }
                    Spacer()
                    HStack(spacing: 12) {
                        // Temporarily hidden filter control.
                        // To re-enable: restore `showFeedFilter`, `showCommunityFilterControl`,
                        // `feedFilterAccessibilityLabel`, and `feedFilterPopoverContent`, then
                        // uncomment the button block below.
                        /*
                        if showCommunityFilterControl {
                            Button {
                                showFeedFilter = true
                            } label: {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                    .font(.system(size: 28))
                                    .imageScale(.large)
                                    .foregroundStyle(.primary)
                                    .frame(width: 38, height: 38)
                            }
                            .contentShape(Rectangle())
                            .buttonStyle(.plain)
                            .popover(isPresented: $showFeedFilter, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                                feedFilterPopoverContent
                                    .presentationCompactAdaptation(.popover)
                            }
                            .accessibilityLabel(feedFilterAccessibilityLabel)
                        }
                        */

                        Button {
                            showAccountMenu = true
                        } label: {
                            accountMenuAvatar
                        }
                        .popover(isPresented: $showAccountMenu, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                            accountMenuPopoverContent
                                .presentationCompactAdaptation(.popover)
                        }
                        .accessibilityLabel("Account menu")
                    }
                }
                .padding(.horizontal)
                .padding(.top, 18)
                .padding(.bottom, 10)
                .background(Color(.systemBackground).opacity(0.92))

                if !liveStreams.isEmpty {
                    LiveNowBannerView(
                        streams: liveStreams,
                        communityName: { liveStreamCommunityNames[$0] ?? "League" },
                        joiningStreamId: joiningStreamId,
                        onSelect: { stream in
                            Task { await joinLiveStream(stream) }
                        }
                    )
                    .padding(.top, 4)
                    if let joinLiveStreamErrorMessage {
                        Text(joinLiveStreamErrorMessage)
                            .font(.custom("NeueHaasDisplay-Light", size: 13))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                            .padding(.bottom, 4)
                    }
                }

                // MARK: Body
                Group {
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
                        .offset(y: -160)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    case .content:
                        VStack(spacing: 0) {

                            // MARK: Feed list or filtered empty state
                            if filteredRows.isEmpty {
                                Spacer()
                                VStack(spacing: 8) {
                                    Image(systemName: "tray")
                                        .font(.largeTitle)
                                        .foregroundStyle(.secondary)
                                    Text("No games match this filter.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                Spacer()
                            } else {
                                ScrollView {
                                    LazyVStack(spacing: 24) {
                                        ForEach(Array(filteredRows.enumerated()), id: \.element.id) { index, row in
                                            FeedCardView(row: row, onRequestEdit: { r in
                                                gameLogEditSheet = GameLogEditSheetItem(id: r.gameLogId)
                                            })
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
                                .scrollContentBackground(.hidden)
                                .refreshable {
                                    AppAnalytics.logFeedRefresh()
                                    await refreshFeed()
                                    await loadLiveStreamCommunities()
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    feedBottomActions
                }
            }
            .background {
                if case .empty = feedState {
                    Image("no_leagues_background")
                        .resizable()
                        .scaledToFill()
                        .padding(.top, 136)
                        .padding(.bottom, 52)
                }
            }
            .fullScreenCover(isPresented: $showCommunitiesFlow) {
                CommunitiesFlowStack()
                    .environmentObject(container)
                    .environmentObject(sessionManager)
            }
            .navigationDestination(isPresented: $showCommunitiesList) {
                CommunitiesListView()
            }
            .navigationDestination(isPresented: $showGameLog) {
                GameLogCaptureEntryView(preselectedCommunityId: pendingLiveStreamCommunityId)
            }
            .navigationDestination(isPresented: $showGoLive) {
                GoLiveCommunityPickerView(onStreamEnded: { communityId in
                    pendingLiveStreamCommunityId = communityId
                    showGoLive = false
                    showGameLog = true
                })
            }
            .navigationDestination(isPresented: $showProfile) {
                ProfileView()
            }
            .navigationDestination(isPresented: $showGameRulesExplainer) {
                GameRulesExplainerView()
            }
            .navigationDestination(isPresented: $showPlatformAdmin) {
                PlatformAdminRootView()
                    .environmentObject(sessionManager)
                    .environmentObject(container)
            }
            .fullScreenCover(item: $viewingLiveStream) { viewing in
                LiveViewerView(
                    stream: viewing.stream,
                    communityName: viewing.communityName,
                    session: viewing.session,
                    onLeave: { viewingLiveStream = nil }
                )
                .environmentObject(container)
            }
            .sheet(item: $gameLogEditSheet) { item in
                NavigationStack {
                    NewGameLogFormView(editingGameLogId: item.id)
                        .environmentObject(container)
                        .environmentObject(sessionManager)
                        .navigationTitle("Edit game")
                        .navigationBarTitleDisplayMode(.inline)
                        .communityFlowNavigationBarChrome()
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                CommunityFlowCloseToolbarButton {
                                    gameLogEditSheet = nil
                                }
                            }
                        }
                }
            }
            .onChange(of: sessionManager.adminConsolePresentationRequested) { _, requested in
                guard requested else { return }
                if sessionManager.isPlatformAdmin {
                    showPlatformAdmin = true
                }
                sessionManager.acknowledgeAdminConsolePresentationRequest()
            }
            .onAppear {
                // Deep link may have fired before Feed was mounted (e.g. still on onboarding).
                guard sessionManager.adminConsolePresentationRequested else { return }
                if sessionManager.isPlatformAdmin {
                    showPlatformAdmin = true
                }
                sessionManager.acknowledgeAdminConsolePresentationRequest()
            }
            .onChange(of: showProfile) { wasShowing, isShowing in
                if wasShowing && !isShowing {
                    Task {
                        await loadProfilePhoto()
                        await loadInitialFeed()
                        await loadLiveStreamCommunities()
                    }
                }
            }
            .task {
                AppAnalytics.logFeedScreen()
                await sessionManager.ensureOnboardingCompleteOrRouteToOnboarding()
                await loadInitialFeed()
                await loadProfilePhoto()
                await loadLiveStreamCommunities()
            }
            .task(id: liveStreamCommunityIds) {
                guard !liveStreamCommunityIds.isEmpty else {
                    liveStreams = []
                    return
                }
                for await streams in container.liveStreamService.observeActiveLiveStreams(
                    communityIds: liveStreamCommunityIds
                ) {
                    liveStreams = streams
                }
            }
            .onChange(of: showGameLog) { wasShowing, isShowing in
                if wasShowing && !isShowing {
                    pendingLiveStreamCommunityId = nil
                    Task {
                        await loadInitialFeed()
                        await loadLiveStreamCommunities()
                    }
                }
            }
            .onChange(of: showCommunitiesFlow) { wasShowing, isShowing in
                if wasShowing && !isShowing {
                    Task {
                        await loadInitialFeed()
                        await loadLiveStreamCommunities()
                    }
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

    /// Compact account actions (popover width is fixed; `Menu` dropdown cannot be narrowed on iOS).
    @ViewBuilder
    private var accountMenuPopoverContent: some View {
        VStack(alignment: .center, spacing: 0) {
            Button {
                showAccountMenu = false
                showProfile = true
            } label: {
                Text("View Profile")
                    .font(.custom("NeueHaasDisplay-Mediu", size: 22))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            .contentShape(Rectangle())
            .buttonStyle(.plain)

            Button {
                showAccountMenu = false
                showCommunitiesList = true
            } label: {
                Text("View Leagues")
                    .font(.custom("NeueHaasDisplay-Mediu", size: 22))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            .contentShape(Rectangle())
            .buttonStyle(.plain)

            Button {
                showAccountMenu = false
                showGameRulesExplainer = true
            } label: {
                Text("How games work")
                    .font(.custom("NeueHaasDisplay-Mediu", size: 22))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            .contentShape(Rectangle())
            .buttonStyle(.plain)

            Divider()

            Button {
                showAccountMenu = false
                sessionManager.signOut()
            } label: {
                Text("Log out")
                    .font(.custom("NeueHaasDisplay-Mediu", size: 22))
                    .foregroundStyle(FeedBrand.primaryButtonRed)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
            .contentShape(Rectangle())
            .buttonStyle(.plain)
        }
        .frame(width: 196)
    }

    @ViewBuilder
    private var accountMenuAvatar: some View {
        if let profilePhotoUrl {
            FeedToolbarResolvedAvatar(originalURL: profilePhotoUrl)
        } else {
            Circle()
                .fill(Color(.systemGray4))
                .frame(width: 38, height: 38)
        }
    }
}

/// Loads `400x400` Storage variant using a correct per-object download URL (token matches the variant file).
private struct FeedToolbarResolvedAvatar: View {
    let originalURL: URL

    @State private var loadURL: URL?

    var body: some View {
        Group {
            if let loadURL {
                AsyncImage(url: loadURL) { phase in
                    switch phase {
                    case .empty:
                        Circle()
                            .fill(Color(.systemGray4))
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        AsyncImage(url: originalURL) { fallbackPhase in
                            switch fallbackPhase {
                            case .success(let fallbackImage):
                                fallbackImage
                                    .resizable()
                                    .scaledToFill()
                            default:
                                Circle()
                                    .fill(Color(.systemGray4))
                            }
                        }
                    @unknown default:
                        Circle()
                            .fill(Color(.systemGray4))
                    }
                }
            } else {
                Circle()
                    .fill(Color(.systemGray4))
            }
        }
        .frame(width: 38, height: 38)
        .clipShape(Circle())
        .task(id: originalURL) {
            loadURL = await ImageVariantURLResolver.shared.resolveURL(originalURL: originalURL, variant: .avatar)
        }
    }
}

private enum FeedBrand {
    static let primaryButtonRed = Color(red: 180.0 / 255.0, green: 61.0 / 255.0, blue: 37.0 / 255.0)
}

private struct FeedPrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(FeedBrand.primaryButtonRed)
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
            let validIds = Set(rows.map(\.communityId))
            selectedCommunityIds = selectedCommunityIds.intersection(validIds)
            homeFeedCursor = page.nextCursor
            hasMoreFeed = page.hasMore
            feedState = rows.isEmpty ? .empty : .content(rows)
            if rows.isEmpty {
                AppAnalytics.logFeedLoad(outcome: .successEmpty)
            } else {
                AppAnalytics.logFeedLoad(outcome: .successContent, rowCount: rows.count)
            }
        } catch {
            feedState = .error(error.localizedDescription)
            AppDebugLog.log("FeedView.loadFeed error: \(error.localizedDescription)")
            AppAnalytics.logFeedLoad(outcome: .failed, errorMessage: error.localizedDescription)
        }
    }

    private func refreshFeed() async {
        await loadInitialFeed()
    }

    /// Refreshes the community id/name map that drives the "live now" banner listener
    /// (`.task(id: liveStreamCommunityIds)`) — changing `liveStreamCommunityIds` restarts it.
    private func loadLiveStreamCommunities() async {
        do {
            let communities = try await container.communityService.fetchCommunities()
            liveStreamCommunityNames = Dictionary(uniqueKeysWithValues: communities.map { ($0.communityId, $0.name) })
            liveStreamCommunityIds = communities.map(\.communityId)
        } catch {
            liveStreamCommunityIds = []
            AppDebugLog.log("FeedView.loadLiveStreamCommunities error: \(error.localizedDescription)")
        }
    }

    private func joinLiveStream(_ stream: LiveStreamSummary) async {
        joiningStreamId = stream.streamId
        joinLiveStreamErrorMessage = nil
        defer { joiningStreamId = nil }
        do {
            let session = try await container.liveStreamService.joinLiveStreamAsViewer(streamId: stream.streamId)
            viewingLiveStream = ViewingLiveStream(
                stream: stream,
                communityName: liveStreamCommunityNames[stream.communityId] ?? "League",
                session: session
            )
        } catch {
            joinLiveStreamErrorMessage = error.localizedDescription
        }
    }

    private func loadMoreFeedIfNeeded(currentRow: FeedRow) async {
        guard hasMoreFeed, !isLoadingMoreFeed else { return }
        guard case .content(let rows) = feedState else { return }
        let visibleRows: [FeedRow]
        if selectedCommunityIds.isEmpty {
            visibleRows = rows
        } else {
            visibleRows = rows.filter { selectedCommunityIds.contains($0.communityId) }
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
            AppAnalytics.logFeedLoadMoreFailed(message: error.localizedDescription)
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
        let photosPerCard = 1
        let nextRows = rows.dropFirst(currentIndex + 1).prefix(lookaheadCardCount)

        var urlsToPrefetch: [URL] = []
        for row in nextRows {
            let rawURLs = row.photoUrls.compactMap(URL.init(string:)).prefix(photosPerCard)
            for originalURL in rawURLs {
                let target = await ImageVariantURLResolver.shared.resolveURL(originalURL: originalURL, variant: .feedThumb)
                urlsToPrefetch.append(target)
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
