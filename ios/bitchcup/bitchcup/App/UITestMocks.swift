import Foundation
import UIKit

@MainActor
final class UITestAuthService: AuthServiceProtocol {
    private(set) var currentUserId: String?

    init(currentUserId: String?) {
        self.currentUserId = currentUserId
    }

    func signIn() async throws {
        if currentUserId == nil {
            currentUserId = "ui-test-user"
        }
    }

    func signOut() throws {
        currentUserId = nil
    }
}

@MainActor
final class UITestUserService: UserServiceProtocol {
    private var profile: ProfileRecord?

    init(initialProfile: ProfileRecord?) {
        self.profile = initialProfile
    }

    func fetchProfile(userId: String) async throws -> ProfileRecord? {
        profile
    }

    func createProfileAfterAgeConfirmation(userId: String) async throws {
        profile = ProfileRecord(
            userId: userId,
            displayName: "",
            profilePhotoUrl: "",
            overallOdds: 0,
            overallGamesPlayed: 0,
            overallOddsByGameType: [:],
            overallGamesPlayedByGameType: [:],
            ageConfirmed21PlusAt: Date(),
            onboardingCompleteAt: nil
        )
    }

    func uploadProfilePhoto(userId: String, data: Data, contentType: String, fileName: String) async throws -> String {
        "https://example.com/avatar.jpg"
    }

    func completeProfileOnboarding(userId: String, displayName: String, profilePhotoUrl: String) async throws {
        profile = ProfileRecord(
            userId: userId,
            displayName: displayName,
            profilePhotoUrl: profilePhotoUrl,
            overallOdds: 0.5,
            overallGamesPlayed: 1,
            overallOddsByGameType: ["PONG": 0.5],
            overallGamesPlayedByGameType: ["PONG": 1],
            ageConfirmed21PlusAt: profile?.ageConfirmed21PlusAt ?? Date(),
            onboardingCompleteAt: Date()
        )
    }
}

@MainActor
final class UITestCommunityService: CommunityServiceProtocol, BracketServiceProtocol {
    private let communities: [(communityId: String, name: String)] = [("ui-community-1", "UI Test League")]
    private let members: [CommunityMemberRosterRow] = [
        .init(profileId: "ui-test-user", displayName: "You", profilePhotoUrl: nil, communityOdds: 0.75, communityGamesPlayed: 4),
        .init(profileId: "ui-opponent-1", displayName: "Alex", profilePhotoUrl: nil, communityOdds: 0.62, communityGamesPlayed: 3),
        .init(profileId: "ui-opponent-2", displayName: "Riley", profilePhotoUrl: nil, communityOdds: 0.51, communityGamesPlayed: 2),
        .init(profileId: "ui-opponent-3", displayName: "Jordan", profilePhotoUrl: nil, communityOdds: 0.41, communityGamesPlayed: 2)
    ]
    private var brackets: [BracketListItem] = []

    func fetchCommunities() async throws -> [(communityId: String, name: String)] {
        communities
    }

    func fetchCommunitiesPage(
        cursor: CommunitiesPageCursor?,
        pageSize: Int
    ) async throws -> PagedResponse<[(communityId: String, name: String)], CommunitiesPageCursor> {
        PagedResponse(items: communities, nextCursor: nil, hasMore: false)
    }

    func fetchMembers(communityId: String) async throws -> [CommunityMemberRosterRow] {
        members
    }

    func fetchBrackets(communityId: String) async throws -> [BracketListItem] {
        brackets
    }

    func createCommunity(name: String) async throws -> (communityId: String, inviteCode: String, inviteLink: String) {
        ("ui-community-1", "ABC123", "https://example.com/invite/ABC123")
    }

    func joinCommunity(inviteCode: String) async throws -> String {
        "ui-community-1"
    }

    func previewJoinCommunity(inviteCode: String) async throws -> CommunityJoinPreview {
        CommunityJoinPreview(communityId: "ui-community-1", name: "UI Test League", memberCount: members.count)
    }

    func createBracket(
        communityId: String,
        seedMethod: SeedMethod,
        teamSize: Int
    ) async throws -> String {
        let id = "ui-bracket-\(brackets.count + 1)"
        brackets.insert(
            BracketListItem(
                bracketId: id,
                communityId: communityId,
                seedMethod: seedMethod,
                status: seedMethod == .manual ? "DRAFT" : "ACTIVE",
                teamSize: teamSize,
                createdAt: Date()
            ),
            at: 0
        )
        return id
    }

    func finalizeManualBracket(
        bracketId: String,
        teams: [[String]]
    ) async throws {}
}

@MainActor
final class UITestGameLogService: GameLogServiceProtocol, FeedServiceProtocol {
    private let seededRows: [FeedRow] = [
        FeedRow(
            gameLogId: "ui-feed-1",
            communityId: "ui-community-1",
            communityName: "UI Test League",
            gameType: "PONG",
            winnerProfileIds: ["ui-test-user"],
            loserProfileIds: ["ui-opponent-1"],
            winnerNames: ["You"],
            loserNames: ["Alex"],
            mvpProfileId: nil,
            lvpProfileId: nil,
            mvpDisplayName: nil,
            lvpDisplayName: nil,
            statsSummary: nil,
            notes: nil,
            photoUrls: [],
            createdAt: Date()
        )
    ]

    func fetchLogs(communityId: String) async throws {}

    func canCurrentUserEditDelete(createdByProfileId: String) -> Bool { true }

    func uploadGamePhoto(
        communityId: String,
        gameLogId: String,
        side: String,
        data: Data,
        contentType: String
    ) async throws -> String {
        "https://example.com/game.jpg"
    }

    func createGameLog(payload: GameLogCreatePayload) async throws {}

    func updateGameLog(payload: GameLogUpdatePayload) async throws {}

    func deleteGameLog(gameLogId: String) async throws {}

    func fetchFeed() async throws -> [FeedRow] { seededRows }

    func fetchFeed(forCommunityId communityId: String) async throws -> [FeedRow] { seededRows }

    func fetchFeedPage(
        cursor: HomeFeedPageCursor?,
        pageSize: Int
    ) async throws -> PagedResponse<[FeedRow], HomeFeedPageCursor> {
        PagedResponse(items: seededRows, nextCursor: nil, hasMore: false)
    }

    func fetchFeedPage(
        forCommunityId communityId: String,
        cursor: FeedPageCursor?,
        pageSize: Int
    ) async throws -> PagedResponse<[FeedRow], FeedPageCursor> {
        PagedResponse(items: seededRows, nextCursor: nil, hasMore: false)
    }
}

@MainActor
enum UITestContainerFactory {
    static func makeContainer(for scenario: UITestScenario) -> (DependencyContainer, AppRouter, AppSessionManager) {
        let router = AppRouter()
        let userId = UITestRuntime.currentUserIdFallback ?? "ui-test-user"
        let auth = UITestAuthService(currentUserId: userId)
        let community = UITestCommunityService()
        let feedAndGameLog = UITestGameLogService()

        let initialProfile: ProfileRecord?
        switch scenario {
        case .onboarding:
            initialProfile = nil
            router.showOnboarding()
        case .gameLog, .bracket:
            initialProfile = ProfileRecord(
                userId: userId,
                displayName: "You",
                profilePhotoUrl: "",
                overallOdds: 0.75,
                overallGamesPlayed: 12,
                overallOddsByGameType: ["PONG": 0.8, "CROSSFIRE": 0.5],
                overallGamesPlayedByGameType: ["PONG": 5, "CROSSFIRE": 4],
                ageConfirmed21PlusAt: Date(),
                onboardingCompleteAt: Date()
            )
            router.showHome()
        }

        let user = UITestUserService(initialProfile: initialProfile)
        let container = DependencyContainer(
            authService: auth,
            userService: user,
            communityService: community,
            gameLogService: feedAndGameLog,
            feedService: feedAndGameLog,
            bracketService: community
        )
        let sessionManager = AppSessionManager(router: router, authService: auth, userService: user)
        return (container, router, sessionManager)
    }
}

