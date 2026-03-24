import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var container: DependencyContainer

    @State private var displayName: String = "Profile"
    @State private var profilePhotoUrl: URL?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var historyRows: [ProfileHistoryRow] = []
    @State private var stats = ProfileAggregateStats.empty
    @State private var overallOdds: Double = 0.0
    @State private var historyCursor: HomeFeedPageCursor?
    @State private var hasMoreHistory = false
    @State private var isLoadingMoreHistory = false
    @State private var loadMoreHistoryErrorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                LoadingView(message: "Loading profile...")
            } else if let errorMessage {
                ErrorView(message: errorMessage) {
                    Task { await loadProfile() }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        profileHeaderSection
                        statsSection
                        if historyRows.isEmpty {
                            EmptyStateView(
                                title: "No games yet",
                                message: "Once you play games, your private history and stats will show here.",
                                actionLabel: "Refresh"
                            ) {
                                Task { await loadProfile() }
                            }
                        } else {
                            historySection
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
                .refreshable {
                    await loadProfile()
                }
            }
        }
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadProfile() }
    }

    private var profileHeaderSection: some View {
        HStack(spacing: 12) {
            profileAvatar

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text("Profile")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var profileAvatar: some View {
        if let profilePhotoUrl {
            let transformedURL = ImageVariantURLBuilder.variantURL(from: profilePhotoUrl, variant: .avatar)
            AsyncImage(url: transformedURL) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .frame(width: 64, height: 64)
                        .background(Color(.systemGray5))
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
                            avatarPlaceholder
                        }
                    }
                @unknown default:
                    avatarPlaceholder
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color(.systemGray4), lineWidth: 1))
        } else {
            avatarPlaceholder
                .frame(width: 64, height: 64)
        }
    }

    private var avatarPlaceholder: some View {
        ZStack {
            Circle()
                .fill(Color(.systemGray5))
            Image(systemName: "person.fill")
                .foregroundStyle(.secondary)
        }
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Aggregate Stats")
                .font(.headline)

            HStack(spacing: 10) {
                statTile(title: "Games", value: "\(stats.gamesPlayed)")
                statTile(title: "Wins", value: "\(stats.wins)")
                statTile(title: "Losses", value: "\(stats.losses)")
            }

            HStack(spacing: 10) {
                statTile(title: "Win Rate", value: stats.winRateText)
                statTile(title: "Leagues", value: "\(stats.uniqueLeagues)")
            }
            HStack(spacing: 10) {
                statTile(title: "Overall Odds", value: Self.oddsFormatter.string(from: NSNumber(value: overallOdds)) ?? "0.000")
            }

            HStack(spacing: 10) {
                statTile(title: "MVPs", value: "\(stats.mvps)")
                statTile(title: "LVPs", value: "\(stats.lvps)")
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Game History")
                .font(.headline)

            ForEach(historyRows) { row in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(row.outcomeLabel)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(row.outcomeColor.opacity(0.2))
                            .foregroundStyle(row.outcomeColor)
                            .clipShape(Capsule())
                        Spacer()
                        Text(row.dateText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(row.gameTypeText)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text("League: \(row.communityText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onAppear {
                    Task { await loadMoreHistoryIfNeeded(currentRow: row) }
                }
            }
            historyFooter
        }
    }

    private func statTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func loadProfile() async {
        isLoading = true
        errorMessage = nil
        overallOdds = 0.0
        historyRows = []
        historyCursor = nil
        hasMoreHistory = false
        loadMoreHistoryErrorMessage = nil
        defer { isLoading = false }

        guard let userId = container.authService.currentUserId else {
            errorMessage = "Sign in again to view your profile."
            return
        }

        do {
            async let profileRecord = container.userService.fetchProfile(userId: userId)
            async let firstHistoryPage = container.feedService.fetchFeedPage(cursor: nil, pageSize: 20)
            async let allRowsForStats = fetchAllFeedRows()

            let (profile, firstPage, allRows) = try await (profileRecord, firstHistoryPage, allRowsForStats)
            let resolvedName = profile?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            displayName = (resolvedName?.isEmpty == false) ? resolvedName! : "Profile"
            profilePhotoUrl = profile?.profilePhotoUrl.flatMap(URL.init(string:))
            overallOdds = profile?.overallOdds ?? 0.0

            let relevantRows = allRows.filter {
                $0.winnerProfileIds.contains(userId) || $0.loserProfileIds.contains(userId)
            }

            let initialHistory = firstPage.items
                .filter { $0.winnerProfileIds.contains(userId) || $0.loserProfileIds.contains(userId) }
                .map { Self.mapHistoryRow(from: $0, userId: userId) }
            historyRows = initialHistory
            historyCursor = firstPage.nextCursor
            hasMoreHistory = firstPage.hasMore
            await fillInitialHistoryIfNeeded(userId: userId)

            let wins = relevantRows.filter { $0.winnerProfileIds.contains(userId) }.count
            let losses = relevantRows.filter { $0.loserProfileIds.contains(userId) }.count
            let mvps = relevantRows.filter { $0.mvpProfileId == userId }.count
            let lvps = relevantRows.filter { $0.lvpProfileId == userId }.count
            stats = ProfileAggregateStats(
                gamesPlayed: relevantRows.count,
                wins: wins,
                losses: losses,
                uniqueLeagues: Set(relevantRows.map(\.communityId)).count,
                mvps: mvps,
                lvps: lvps
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMoreHistoryIfNeeded(currentRow: ProfileHistoryRow) async {
        guard hasMoreHistory, !isLoadingMoreHistory else { return }
        guard Set(historyRows.suffix(3).map(\.id)).contains(currentRow.id) else { return }
        await loadMoreHistory()
    }

    @ViewBuilder
    private var historyFooter: some View {
        if isLoadingMoreHistory {
            ProgressView("Loading more...")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        } else if historyRows.isEmpty, hasMoreHistory {
            Button("Load older games") {
                Task { await loadMoreHistory() }
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        } else if let loadMoreHistoryErrorMessage {
            VStack(spacing: 8) {
                Text(loadMoreHistoryErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Retry loading more") {
                    Task { await loadMoreHistory() }
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        } else if !hasMoreHistory, !historyRows.isEmpty {
            Text("No older games.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
    }

    private static func mapHistoryRow(from row: FeedRow, userId: String) -> ProfileHistoryRow {
        let didWin = row.winnerProfileIds.contains(userId)
        return ProfileHistoryRow(
            gameLogId: row.gameLogId,
            gameTypeText: row.gameType.replacingOccurrences(of: "_", with: " ").capitalized,
            communityText: row.communityName ?? row.communityId,
            didWin: didWin,
            createdAt: row.createdAt
        )
    }

    private func fetchAllFeedRows() async throws -> [FeedRow] {
        var allRows: [FeedRow] = []
        var cursor: HomeFeedPageCursor?
        while true {
            let page = try await container.feedService.fetchFeedPage(cursor: cursor, pageSize: 50)
            allRows.append(contentsOf: page.items)
            guard page.hasMore, let nextCursor = page.nextCursor else { break }
            cursor = nextCursor
        }
        let unique = Dictionary(grouping: allRows, by: \.gameLogId).compactMap { $0.value.first }
        return unique.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt { return lhs.gameLogId > rhs.gameLogId }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func fillInitialHistoryIfNeeded(userId: String) async {
        guard historyRows.isEmpty else { return }
        while hasMoreHistory && historyRows.isEmpty && !isLoadingMoreHistory {
            await loadMoreHistory()
        }
    }

    private func loadMoreHistory() async {
        guard hasMoreHistory, !isLoadingMoreHistory else { return }
        guard let userId = container.authService.currentUserId else { return }

        isLoadingMoreHistory = true
        loadMoreHistoryErrorMessage = nil
        defer { isLoadingMoreHistory = false }

        do {
            let page = try await container.feedService.fetchFeedPage(cursor: historyCursor, pageSize: 20)
            let mapped = page.items
                .filter { $0.winnerProfileIds.contains(userId) || $0.loserProfileIds.contains(userId) }
                .map { Self.mapHistoryRow(from: $0, userId: userId) }

            let merged = Dictionary(grouping: historyRows + mapped, by: \.gameLogId).compactMap { $0.value.first }
            historyRows = merged.sorted { $0.createdAt > $1.createdAt }
            historyCursor = page.nextCursor
            hasMoreHistory = page.hasMore
        } catch {
            loadMoreHistoryErrorMessage = error.localizedDescription
        }
    }
    private static let oddsFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.minimumFractionDigits = 3
        f.maximumFractionDigits = 3
        f.numberStyle = .decimal
        return f
    }()
}

private struct ProfileAggregateStats {
    let gamesPlayed: Int
    let wins: Int
    let losses: Int
    let uniqueLeagues: Int
    let mvps: Int
    let lvps: Int

    static let empty = ProfileAggregateStats(gamesPlayed: 0, wins: 0, losses: 0, uniqueLeagues: 0, mvps: 0, lvps: 0)

    var winRateText: String {
        guard gamesPlayed > 0 else { return "0%" }
        let rate = (Double(wins) / Double(gamesPlayed)) * 100
        return "\(Int(rate.rounded()))%"
    }
}

private struct ProfileHistoryRow: Identifiable {
    let gameLogId: String
    let gameTypeText: String
    let communityText: String
    let didWin: Bool
    let createdAt: Date

    var id: String { gameLogId }

    var outcomeLabel: String { didWin ? "Win" : "Loss" }
    var outcomeColor: Color { didWin ? .green : .red }
    var dateText: String { createdAt.formatted(date: .abbreviated, time: .shortened) }
}
