import SwiftUI

struct FeedView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var sessionManager: AppSessionManager
    @EnvironmentObject private var container: DependencyContainer

    @State private var showCommunitiesFlow = false
    @State private var showCommunitiesList = false
    @State private var showGameLog = false
    @State private var showProfile = false
    @State private var showAccountMenu = false
    @State private var showFeedFilter = false
    @State private var profilePhotoUrl: URL?

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
        if selectedCommunityIds.isEmpty { return allRows }
        return allRows.filter { selectedCommunityIds.contains($0.communityId) }
    }

    /// Show beside the profile photo whenever the feed has loaded rows so filtering is always available (including a single league).
    private var showCommunityFilterControl: Bool {
        if case .content = feedState { return true }
        return false
    }

    private var feedFilterAccessibilityLabel: String {
        if selectedCommunityIds.isEmpty {
            return "Filter feed, showing all leagues"
        }
        if selectedCommunityIds.count == 1, let onlyId = selectedCommunityIds.first {
            let name = filterOptions.first { $0.communityId == onlyId }?.displayName ?? onlyId
            return "Filter feed, \(name)"
        }
        return "Filter feed, \(selectedCommunityIds.count) leagues selected"
    }

    @ViewBuilder
    private var feedBottomActions: some View {
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
            .accessibilityIdentifier("feed.leagues")

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
                HStack {
                    Text("Bitch Cup")
                        .font(headerFont)
                    Spacer()
                    HStack(spacing: 12) {
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
                            .buttonStyle(.plain)
                            .popover(isPresented: $showFeedFilter, attachmentAnchor: .rect(.bounds), arrowEdge: .top) {
                                feedFilterPopoverContent
                                    .presentationCompactAdaptation(.popover)
                            }
                            .accessibilityLabel(feedFilterAccessibilityLabel)
                        }

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
                                .scrollContentBackground(.hidden)
                                .refreshable {
                                    AppAnalytics.logFeedRefresh()
                                    await refreshFeed()
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
                AppAnalytics.logFeedScreen()
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
            .buttonStyle(.plain)
        }
        .frame(width: 196)
    }

    @ViewBuilder
    private var feedFilterPopoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                selectedCommunityIds = []
            } label: {
                HStack(alignment: .center) {
                    Text("All leagues")
                        .font(.custom("NeueHaasDisplay-Mediu", size: 22))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if selectedCommunityIds.isEmpty {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)

            ForEach(filterOptions) { option in
                Toggle(isOn: Binding(
                    get: { selectedCommunityIds.contains(option.communityId) },
                    set: { isOn in
                        if isOn {
                            selectedCommunityIds.insert(option.communityId)
                        } else {
                            selectedCommunityIds.remove(option.communityId)
                        }
                    }
                )) {
                    Text(option.displayName)
                        .font(.custom("NeueHaasDisplay-Mediu", size: 22))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
        .frame(width: 220)
    }

    @ViewBuilder
    private var accountMenuAvatar: some View {
        if let profilePhotoUrl {
            FeedToolbarResolvedAvatar(originalURL: profilePhotoUrl)
        } else {
            Image(systemName: "person.circle.fill")
                .font(.title)
                .foregroundStyle(.primary)
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
                        ProgressView()
                            .frame(width: 38, height: 38)
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
            } else {
                ProgressView()
                    .frame(width: 38, height: 38)
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
