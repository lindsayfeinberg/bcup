import FirebaseFirestore
import SwiftUI

struct CommunityDetailView: View {
    let communityId: String

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

    var body: some View {
        Group {
            if isLoading {
                LoadingView(message: "Loading league...")
            } else if let error = errorMessage {
                ErrorView(message: error) {
                    Task { await loadInitial() }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {

                        membersSection

                        recentGamesSection

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Bracket")
                                .font(.headline)
                            Text("Bracket entry will appear here (T10).")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
                .refreshable {
                    await refreshAll()
                }
            }
        }
        .navigationTitle(communityName.isEmpty ? "League" : communityName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadInitial()
        }
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Members (\(members.count))")
                .font(.headline)

            if members.isEmpty {
                Text("No members yet.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(members) { member in
                    HStack {
                        Circle()
                            .frame(width: 36, height: 36)
                            .foregroundStyle(Color(.systemGray4))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.displayName.isEmpty ? "Unknown" : member.displayName)
                                .font(.subheadline)
                            if member.communityGamesPlayed == 0 {
                                Text("No league games yet")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(Self.oddsFormatter.string(
                                    from: NSNumber(value: member.communityOdds)
                                ) ?? "0.000")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    private var recentGamesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Games")
                .font(.headline)

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
