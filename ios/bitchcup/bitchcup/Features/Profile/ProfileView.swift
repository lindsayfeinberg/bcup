import SwiftUI

private enum ProfileBrandColor {
    static let red = Color(red: 180.0 / 255.0, green: 61.0 / 255.0, blue: 37.0 / 255.0)
    static let formLightRed = Color(red: 232.0 / 255.0, green: 162.0 / 255.0, blue: 145.0 / 255.0)
    /// Win pill background (history).
    static let forestGreen = Color(red: 36.0 / 255.0, green: 138.0 / 255.0, blue: 28.0 / 255.0)
}

private enum ProfileTestStyle {
    static let ink = Color.black
}

private enum ProfileChrome {
    static let lightBorder = Color(red: 220.0 / 255.0, green: 220.0 / 255.0, blue: 222.0 / 255.0)
}

private enum ProfileTypography {
    static let profileName = Font.custom("NeueHaasDisplay-Mediu", size: 32)
    /// Aggregate Stats and Game History section titles (same size).
    static let sectionHeader = Font.custom("NeueHaasDisplay-Mediu", size: 26)
    static let statValue = Font.custom("NeueHaasDisplay-Mediu", size: 22)
    static let statLabel = Font.custom("NeueHaasDisplay-Mediu", size: 17)
}

private let profileAvatarSize: CGFloat = 168

struct ProfileView: View {
    @EnvironmentObject private var container: DependencyContainer
    @EnvironmentObject private var sessionManager: AppSessionManager

    @State private var displayName: String = "Profile"
    /// Raw name from Firestore for the edit sheet (empty when unset).
    @State private var editingNameSeed: String = ""
    @State private var showEditProfile = false
    @State private var profilePhotoUrl: URL?
    /// Shown immediately after saving a new photo from the edit sheet (avoids AsyncImage reload spinner).
    @State private var avatarDisplayOverride: UIImage?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var historyRows: [ProfileHistoryRow] = []
    @State private var stats = ProfileAggregateStats.empty
    @State private var overallOdds: Double = 0.0
    @State private var overallOddsByGameType: [String: Double] = [:]
    @State private var overallGamesPlayedByGameType: [String: Int] = [:]
    @State private var historyCursor: HomeFeedPageCursor?
    @State private var hasMoreHistory = false
    @State private var isLoadingMoreHistory = false
    @State private var loadMoreHistoryErrorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                profileLoadingState
            } else if let errorMessage {
                profileErrorState(message: errorMessage)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        profileHeaderSection
                        statsSection
                        perGameTypeStatsSection
                        if historyRows.isEmpty {
                            profileEmptyHistoryCard
                        } else {
                            historySection
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
                .scrollContentBackground(.hidden)
                .background(Color.white)
                .refreshable {
                    await loadProfile()
                }
            }
        }
        .background(Color.white)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                CommunityFlowBackToolbarButton()
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if container.authService.currentUserId != nil {
                    Button("Edit") {
                        showEditProfile = true
                    }
                    .font(.custom("NeueHaasDisplay-Mediu", size: 16))
                    .foregroundStyle(ProfileBrandColor.red)
                }
            }
        }
        .sheet(isPresented: $showEditProfile) {
            EditProfileView(
                initialDisplayName: editingNameSeed,
                initialPhotoURL: profilePhotoUrl,
                onSaved: { image in
                    if let image {
                        avatarDisplayOverride = image
                    }
                    Task { await loadProfile() }
                }
            )
            .environmentObject(container)
            .environmentObject(sessionManager)
        }
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            AppAnalytics.logProfileScreen()
            await loadProfile()
        }
    }

    private var profileLoadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(ProfileTestStyle.ink)
                .scaleEffect(1.2)
            Text("Loading profile...")
                .font(AppFont.subheadline)
                .foregroundStyle(ProfileTestStyle.ink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }

    private func profileErrorState(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(ProfileTestStyle.ink)
            Text("Error")
                .font(AppFont.headline)
                .foregroundStyle(ProfileTestStyle.ink)
            Text(message)
                .font(AppFont.subheadline)
                .foregroundStyle(ProfileTestStyle.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button {
                Task { await loadProfile() }
            } label: {
                Text("Retry")
                    .font(AppFont.buttonProminent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(ProfilePrimaryButtonStyle())
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }

    private var profileEmptyHistoryCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundStyle(ProfileTestStyle.ink)
            Text("No games yet")
                .font(AppFont.emptyStateTitle)
                .foregroundStyle(ProfileTestStyle.ink)
            Text("Once you play games, your private history and stats will show here.")
                .font(AppFont.subheadline)
                .foregroundStyle(ProfileTestStyle.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button {
                Task { await loadProfile() }
            } label: {
                Text("Refresh")
                    .font(AppFont.buttonProminent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(ProfilePrimaryButtonStyle())
            .padding(.horizontal, 8)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(ProfileChrome.lightBorder, lineWidth: 1)
        )
    }

    private var profileHeaderSection: some View {
        VStack(spacing: 12) {
            profileAvatar

            Text(displayName)
                .font(ProfileTypography.profileName)
                .foregroundStyle(ProfileTestStyle.ink)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
        )
    }

    @ViewBuilder
    private var profileAvatar: some View {
        if let avatarDisplayOverride {
            Image(uiImage: avatarDisplayOverride)
                .resizable()
                .scaledToFill()
                .frame(width: profileAvatarSize, height: profileAvatarSize)
                .clipShape(Circle())
        } else if let profilePhotoUrl {
            ProfileAvatarCircleView(originalURL: profilePhotoUrl, size: profileAvatarSize)
        } else {
            avatarPlaceholder
                .frame(width: profileAvatarSize, height: profileAvatarSize)
        }
    }

    private var avatarPlaceholder: some View {
        ZStack {
            Circle()
                .fill(ProfileBrandColor.formLightRed.opacity(0.35))
            Image(systemName: "person.fill")
                .foregroundStyle(ProfileTestStyle.ink)
        }
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Aggregate Stats")
                .font(ProfileTypography.sectionHeader)
                .foregroundStyle(ProfileTestStyle.ink)

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
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
        )
    }

    private var perGameTypeStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("By game type")
                .font(ProfileTypography.sectionHeader)
                .foregroundStyle(ProfileTestStyle.ink)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(LeagueRankingBasis.allCases.filter { $0 != .allGames }) { basis in
                    let games = overallGamesPlayedByGameType[basis.rawValue] ?? 0
                    let odds = overallOddsByGameType[basis.rawValue] ?? 0
                    HStack(alignment: .firstTextBaseline) {
                        Text(basis.displayName)
                            .font(AppFont.subheadlineBold)
                            .foregroundStyle(ProfileTestStyle.ink)
                        Spacer(minLength: 8)
                        if games == 0 {
                            Text("No games")
                                .font(AppFont.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            let pct = Int((odds * 100).rounded())
                            Text("\(pct)% win rate · \(games) \(games == 1 ? "game" : "games")")
                                .font(AppFont.subheadline)
                                .foregroundStyle(ProfileTestStyle.ink)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(ProfileChrome.lightBorder, lineWidth: 1)
        )
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Game History")
                .font(ProfileTypography.sectionHeader)
                .foregroundStyle(ProfileTestStyle.ink)

            ForEach(historyRows) { row in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(row.outcomeLabel)
                            .font(AppFont.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(row.didWin ? ProfileBrandColor.forestGreen : ProfileBrandColor.red)
                            .clipShape(Capsule())
                        Spacer()
                        Text(row.dateText)
                            .font(AppFont.caption)
                            .foregroundStyle(ProfileTestStyle.ink)
                    }

                    Text(row.gameTypeText)
                        .font(AppFont.subheadlineBold)
                        .foregroundStyle(ProfileTestStyle.ink)

                    Text("League: \(row.communityText)")
                        .font(AppFont.caption)
                        .foregroundStyle(ProfileTestStyle.ink)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(ProfileChrome.lightBorder, lineWidth: 1)
                )
                .onAppear {
                    Task { await loadMoreHistoryIfNeeded(currentRow: row) }
                }
            }
            historyFooter
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
        )
    }

    private func statTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(ProfileTypography.statValue)
                .foregroundStyle(ProfileTestStyle.ink)
            Text(title)
                .font(ProfileTypography.statLabel)
                .foregroundStyle(ProfileTestStyle.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(ProfileChrome.lightBorder, lineWidth: 1)
        )
    }

    private func loadProfile() async {
        isLoading = true
        errorMessage = nil
        overallOdds = 0.0
        overallOddsByGameType = [:]
        overallGamesPlayedByGameType = [:]
        historyRows = []
        historyCursor = nil
        hasMoreHistory = false
        loadMoreHistoryErrorMessage = nil
        defer { isLoading = false }

        guard let userId = container.authService.currentUserId else {
            errorMessage = "Sign in again to view your profile."
            AppAnalytics.logProfileLoad(outcome: .noAuth)
            return
        }

        do {
            async let profileRecord = container.userService.fetchProfile(userId: userId)
            async let firstHistoryPage = container.feedService.fetchFeedPage(cursor: nil, pageSize: 20)
            async let allRowsForStats = fetchAllFeedRows()

            let (profile, firstPage, allRows) = try await (profileRecord, firstHistoryPage, allRowsForStats)
            let resolvedName = profile?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            editingNameSeed = (resolvedName?.isEmpty == false) ? resolvedName! : ""
            displayName = editingNameSeed.isEmpty ? "Profile" : editingNameSeed
            profilePhotoUrl = profile?.profilePhotoUrl.flatMap(URL.init(string:))
            overallOdds = profile?.overallOdds ?? 0.0
            overallOddsByGameType = profile?.overallOddsByGameType ?? [:]
            overallGamesPlayedByGameType = profile?.overallGamesPlayedByGameType ?? [:]

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
            AppAnalytics.logProfileLoad(outcome: .success, historyCount: historyRows.count)
        } catch {
            errorMessage = error.localizedDescription
            AppAnalytics.logProfileLoad(outcome: .failed, errorMessage: error.localizedDescription)
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
                .font(AppFont.footnote)
                .tint(ProfileTestStyle.ink)
                .foregroundStyle(ProfileTestStyle.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        } else if historyRows.isEmpty, hasMoreHistory {
            Button("Load older games") {
                Task { await loadMoreHistory() }
            }
            .font(AppFont.button)
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(ProfileTestStyle.ink)
            )
            .padding(.vertical, 4)
        } else if let loadMoreHistoryErrorMessage {
            VStack(spacing: 8) {
                Text(loadMoreHistoryErrorMessage)
                    .font(AppFont.footnote)
                    .foregroundStyle(ProfileTestStyle.ink)
                Button("Retry loading more") {
                    Task { await loadMoreHistory() }
                }
                .font(AppFont.button)
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(ProfileTestStyle.ink)
                )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        } else if !hasMoreHistory, !historyRows.isEmpty {
            Text("No older games.")
                .font(AppFont.footnote)
                .foregroundStyle(ProfileTestStyle.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
    }

    private static func mapHistoryRow(from row: FeedRow, userId: String) -> ProfileHistoryRow {
        let didWin = row.winnerProfileIds.contains(userId)
        let gameTypeLabel: String
        if row.gameType == "CUSTOM" {
            if let name = row.customGameDefinitionName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !name.isEmpty {
                gameTypeLabel = name
            } else {
                gameTypeLabel = "Custom game"
            }
        } else {
            gameTypeLabel = row.gameType.replacingOccurrences(of: "_", with: " ").capitalized
        }
        return ProfileHistoryRow(
            gameLogId: row.gameLogId,
            gameTypeText: gameTypeLabel,
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
            AppAnalytics.logProfileHistoryLoadMoreFailed(message: error.localizedDescription)
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

private struct ProfilePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.white)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(ProfileTestStyle.ink)
            )
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
    var dateText: String { createdAt.formatted(date: .abbreviated, time: .shortened) }
}
