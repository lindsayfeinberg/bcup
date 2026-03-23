import SwiftUI

struct FeedView: View {
    @EnvironmentObject private var sessionManager: AppSessionManager
    @EnvironmentObject private var container: DependencyContainer

    @State private var showCommunitiesFlow = false
    @State private var showCommunitiesList = false
    @State private var showGameLog = false
    @State private var showProfile = false

    private enum FeedState {
        case loading
        case error(String)
        case empty
        case content([FeedRow])
    }
    @State private var feedState: FeedState = .loading
    @State private var selectedCommunityId: String? = nil  // nil = All leagues

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
                        Image(systemName: "person.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("Account menu")
                }
                .padding(.horizontal)
                .padding(.vertical, 8)

                // MARK: Body
                switch feedState {
                case .loading:
                    LoadingView(message: "Loading feed...")

                case .error(let message):
                    ErrorView(message: message) {
                        Task { await loadFeed() }
                    }

                case .empty:
                    EmptyStateView(
                        title: "No games yet",
                        message: "Log a game or join a league to see activity here.",
                        actionLabel: "Log a Game"
                    ) {
                        showGameLog = true
                    }

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
                                    ForEach(filteredRows) { row in
                                        FeedCardView(row: row)
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.top, 8)
                                .padding(.bottom, 16)
                            }
                            .refreshable {
                                await loadFeed()
                            }
                        }
                    }
                }

                // MARK: Bottom bar
                HStack {
                    Button("Create/Join a League") {
                        showCommunitiesFlow = true
                    }
                    .frame(maxWidth: .infinity)
                    .padding()

                    Divider()
                        .frame(height: 30)

                    Button("Submit Game") {
                        showGameLog = true
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .background(Color(.systemGray5))
                .cornerRadius(12)
                .padding(.horizontal)
                .padding(.bottom)
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
                guard case .loading = feedState else { return }
                await loadFeed()
            }
            .onAppear {
                Task { await loadFeed() }
            }
        }
    }
}

// MARK: - Load

extension FeedView {
    private func loadFeed() async {
        feedState = .loading
        do {
            let rows = try await container.feedService.fetchFeed()
            // After reload, keep selected filter only if still valid
            if let selected = selectedCommunityId {
                let stillValid = rows.contains { $0.communityId == selected }
                if !stillValid { selectedCommunityId = nil }
            }
            feedState = rows.isEmpty ? .empty : .content(rows)
        } catch {
            feedState = .error(error.localizedDescription)
            AppDebugLog.log("FeedView.loadFeed error: \(error.localizedDescription)")
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

// MARK: - Feed Card

private struct FeedCardView: View {
    let row: FeedRow

    private static let dateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Photo preview
            photoSection

            // Card content
            VStack(alignment: .leading, spacing: 10) {

                // Game type + timestamp
                HStack(alignment: .firstTextBaseline) {
                    Text(gameTypeDisplay)
                        .font(.headline)
                        .accessibilityLabel("Game type: \(gameTypeDisplay)")
                    Spacer()
                    Text(Self.dateFormatter.localizedString(for: row.createdAt, relativeTo: Date()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Posted \(Self.dateFormatter.localizedString(for: row.createdAt, relativeTo: Date()))")
                }

                Divider()

                // Winners
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(.yellow)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Winners")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(row.winnersText)
                            .font(.subheadline)
                            .lineLimit(2)
                            .accessibilityLabel("Winners: \(row.winnersText)")
                    }
                }

                // Losers
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "figure.walk")
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Losers")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(row.losersText)
                            .font(.subheadline)
                            .lineLimit(2)
                            .accessibilityLabel("Losers: \(row.losersText)")
                    }
                }

                // League
                HStack(spacing: 4) {
                    Image(systemName: "person.3")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(row.communityName ?? row.communityId)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .accessibilityLabel("League: \(row.communityName ?? row.communityId)")
                }
            }
            .padding(12)
        }
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }

    // MARK: Photo section

    @ViewBuilder
    private var photoSection: some View {
        let urls = row.photoUrls.compactMap { URL(string: $0) }
        if !urls.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(urls, id: \.absoluteString) { url in
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                Color(.systemGray5)
                                    .frame(width: UIScreen.main.bounds.width - 32, height: 500)
                                    .overlay(ProgressView())
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: UIScreen.main.bounds.width - 32, height: 500)
                                    .accessibilityLabel("Game photo")
                            case .failure:
                                photoPlaceholder(isLoading: false)
                                    .frame(width: UIScreen.main.bounds.width - 32, height: 500)
                            @unknown default:
                                photoPlaceholder(isLoading: false)
                                    .frame(width: UIScreen.main.bounds.width - 32, height: 500)
                            }
                        }
                    }
                }
            }
            .frame(height: 500)
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: 14,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 14
            ))
        }
    }

    @ViewBuilder
    private func photoPlaceholder(isLoading: Bool) -> some View {
        ZStack {
            Color(.systemGray5)
            if isLoading {
                ProgressView()
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("Photo unavailable")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 500)
        .accessibilityLabel(isLoading ? "Loading photo" : "Photo unavailable")
    }

    private var gameTypeDisplay: String {
        row.gameType
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}