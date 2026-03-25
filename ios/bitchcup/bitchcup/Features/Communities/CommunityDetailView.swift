import FirebaseFirestore
import SwiftUI

struct CommunityDetailView: View {
    let communityId: String

    private let pageTitleFont = Font.custom("NeueHaasDisplay-Bold", size: 42)
    private let sectionHeaderFont = Font.custom("NeueHaasDisplay-Mediu", size: 28)
    private let memberRankFont = Font.custom("NeueHaasDisplay-Mediu", size: 18)
    private let memberNameFont = Font.custom("NeueHaasDisplay-Mediu", size: 17)
    private let memberDetailFont = Font.custom("NeueHaasDisplay-Light", size: 15)

    @EnvironmentObject private var container: DependencyContainer
    @State private var communityName: String = ""
    @State private var members: [CommunityMemberRosterRow] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    @State private var feedRows: [FeedRow] = []
    @State private var isLoadingFeed = false
    @State private var feedErrorMessage: String?
    @State private var feedCursor: FeedPageCursor?
    @State private var hasMoreFeed = false
    @State private var isLoadingMoreFeed = false
    @State private var loadMoreFeedErrorMessage: String?

    private var displayCommunityName: String {
        let trimmed = communityName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "League" : trimmed
    }

    /// Highest `communityOdds` first (best → worst); ties broken by `profileId` for stable order.
    private var membersOrderedByOdds: [CommunityMemberRosterRow] {
        members.sorted { lhs, rhs in
            if lhs.communityOdds != rhs.communityOdds {
                return lhs.communityOdds > rhs.communityOdds
            }
            return lhs.profileId < rhs.profileId
        }
    }

    var body: some View {
        Group {
            if isLoading {
                LoadingView(message: "Loading league...")
            } else if let error = errorMessage {
                ErrorView(message: error) {
                    Task { await loadInitial() }
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text(displayCommunityName)
                        .font(pageTitleFont)
                        .foregroundStyle(.black)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal)
                        .padding(.top, 24)
                        .padding(.bottom, 28)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            membersSection
                            recentGamesSection
                            bracketPlaceholder
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    }
                    .refreshable {
                        await refreshAll()
                    }
                }
                .background(Color.white)
            }
        }
        .background(Color.white)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            await loadInitial()
        }
    }

    private var bracketPlaceholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bracket")
                .font(sectionHeaderFont)
                .foregroundStyle(.black)
            Text("Bracket entry will appear here (T10).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Members (\(members.count))")
                .font(sectionHeaderFont)
                .foregroundStyle(.black)

            if members.isEmpty {
                Text("No members yet.")
                    .font(memberDetailFont)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(membersOrderedByOdds.enumerated()), id: \.element.id) { index, member in
                    HStack(alignment: .center, spacing: 10) {
                        Text("\(index + 1).")
                            .font(memberRankFont)
                            .foregroundStyle(.black)
                            .frame(minWidth: 36, alignment: .trailing)
                            .monospacedDigit()

                        Circle()
                            .frame(width: 36, height: 36)
                            .foregroundStyle(Color(.systemGray4))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.displayName.isEmpty ? "Unknown" : member.displayName)
                                .font(memberNameFont)
                                .foregroundStyle(.black)
                            if member.communityGamesPlayed == 0 {
                                Text("No league games yet")
                                    .font(memberDetailFont)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(Self.oddsFormatter.string(
                                    from: NSNumber(value: member.communityOdds)
                                ) ?? "0.000")
                                    .font(memberDetailFont)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private var recentGamesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Games")
                .font(sectionHeaderFont)
                .foregroundStyle(.black)

            if isLoadingFeed && feedErrorMessage == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else if let feedError = feedErrorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(feedError)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await loadInitialFeedSection() }
                    }
                    .buttonStyle(.bordered)
                }
            } else if feedRows.isEmpty {
                Text("No games in this league yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(spacing: 24) {
                    ForEach(feedRows) { row in
                        FeedCardView(row: row, showCommunityLabel: false)
                            .onAppear {
                                Task { await loadMoreFeedIfNeeded(currentRow: row) }
                            }
                    }
                    feedFooter
                }
            }
        }
    }

    private func loadInitial() async {
        isLoading = true
        errorMessage = nil
        feedErrorMessage = nil
        do {
            try await fetchCommunityAndMembers()
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return
        }
        isLoading = false
        await loadInitialFeedSection()
    }

    private func fetchCommunityAndMembers() async throws {
        let db = AppFirestore.db()
        let communityDoc = try await db.collection("communities").document(communityId).getDocument()
        communityName = communityDoc.data()?["name"] as? String ?? "League"
        members = try await container.communityService.fetchMembers(communityId: communityId)
    }

    private func loadInitialFeedSection() async {
        isLoadingFeed = true
        feedErrorMessage = nil
        feedCursor = nil
        hasMoreFeed = false
        loadMoreFeedErrorMessage = nil
        do {
            let page = try await container.feedService.fetchFeedPage(
                forCommunityId: communityId,
                cursor: nil,
                pageSize: 20
            )
            feedRows = page.items
            feedCursor = page.nextCursor
            hasMoreFeed = page.hasMore
        } catch {
            feedRows = []
            feedErrorMessage = Self.mapFeedError(error)
        }
        isLoadingFeed = false
    }

    private func refreshAll() async {
        feedErrorMessage = nil
        errorMessage = nil
        do {
            try await fetchCommunityAndMembers()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        await loadInitialFeedSection()
    }

    private func loadMoreFeedIfNeeded(currentRow: FeedRow) async {
        guard hasMoreFeed, !isLoadingMoreFeed else { return }
        guard Set(feedRows.suffix(3).map(\.id)).contains(currentRow.id) else { return }

        isLoadingMoreFeed = true
        loadMoreFeedErrorMessage = nil
        defer { isLoadingMoreFeed = false }

        do {
            let page = try await container.feedService.fetchFeedPage(
                forCommunityId: communityId,
                cursor: feedCursor,
                pageSize: 20
            )
            let unique = Dictionary(grouping: (feedRows + page.items), by: \.gameLogId).compactMap { $0.value.first }
            feedRows = unique.sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt { return lhs.gameLogId > rhs.gameLogId }
                return lhs.createdAt > rhs.createdAt
            }
            feedCursor = page.nextCursor
            hasMoreFeed = page.hasMore
        } catch {
            loadMoreFeedErrorMessage = Self.mapFeedError(error)
        }
    }

    private static func mapFeedError(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == FirestoreErrorDomain,
           ns.code == FirestoreErrorCode.permissionDenied.rawValue {
            return "You can't view games in this league."
        }
        return ns.localizedDescription
    }

    @ViewBuilder
    private var feedFooter: some View {
        if isLoadingMoreFeed {
            ProgressView("Loading more...")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        } else if let loadMoreFeedErrorMessage {
            VStack(spacing: 8) {
                Text(loadMoreFeedErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Retry loading more") {
                    Task {
                        if let last = feedRows.last {
                            await loadMoreFeedIfNeeded(currentRow: last)
                        }
                    }
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        } else if !hasMoreFeed, !feedRows.isEmpty {
            Text("No older games.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
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
