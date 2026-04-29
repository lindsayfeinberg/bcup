import FirebaseFirestore
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

    func fetchPlatformAdminClaimFromIDToken(forceRefresh: Bool) async throws -> Bool {
        _ = forceRefresh
        return false
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

    func updateProfile(userId: String, displayName: String, profilePhotoUrl: String) async throws {
        let prior = profile
        profile = ProfileRecord(
            userId: userId,
            displayName: displayName,
            profilePhotoUrl: profilePhotoUrl,
            overallOdds: prior?.overallOdds ?? 0,
            overallGamesPlayed: prior?.overallGamesPlayed ?? 0,
            overallOddsByGameType: prior?.overallOddsByGameType ?? [:],
            overallGamesPlayedByGameType: prior?.overallGamesPlayedByGameType ?? [:],
            ageConfirmed21PlusAt: prior?.ageConfirmed21PlusAt,
            onboardingCompleteAt: prior?.onboardingCompleteAt
        )
    }
}

@MainActor
final class UITestCommunityService: CommunityServiceProtocol, BracketServiceProtocol {
    private var communities: [CommunityListItem] = [
        CommunityListItem(
            communityId: "ui-community-1",
            name: "UI Test League",
            hiddenFromMembers: false,
            createdByProfileId: "ui-test-user"
        )
    ]
    private let members: [CommunityMemberRosterRow] = [
        .init(profileId: "ui-test-user", displayName: "You", profilePhotoUrl: nil, communityOdds: 0.75, communityGamesPlayed: 4),
        .init(profileId: "ui-opponent-1", displayName: "Alex", profilePhotoUrl: nil, communityOdds: 0.62, communityGamesPlayed: 3),
        .init(profileId: "ui-opponent-2", displayName: "Riley", profilePhotoUrl: nil, communityOdds: 0.51, communityGamesPlayed: 2),
        .init(profileId: "ui-opponent-3", displayName: "Jordan", profilePhotoUrl: nil, communityOdds: 0.41, communityGamesPlayed: 2)
    ]
    private var brackets: [BracketListItem] = []

    func fetchCommunities() async throws -> [CommunityListItem] {
        communities
    }

    func fetchCommunitiesPage(
        cursor: CommunitiesPageCursor?,
        pageSize: Int
    ) async throws -> PagedResponse<[CommunityListItem], CommunitiesPageCursor> {
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

    func setCommunityHidden(communityId: String, hidden: Bool) async throws {
        guard communityId == "ui-community-1" else { return }
        if let idx = communities.firstIndex(where: { $0.communityId == communityId }) {
            let prior = communities[idx]
            communities[idx] = CommunityListItem(
                communityId: prior.communityId,
                name: prior.name,
                hiddenFromMembers: hidden,
                createdByProfileId: prior.createdByProfileId
            )
        }
    }

    func resolveBoardAuthorDisplayNames(communityId: String, profileIds: [String]) async -> [String: String] {
        _ = communityId
        var map: [String: String] = [:]
        for id in profileIds {
            if let row = members.first(where: { $0.profileId == id }) {
                map[id] = row.displayName
            } else {
                map[id] = id
            }
        }
        return map
    }

    func postLeagueBoardMessage(communityId: String, text: String) async throws {
        _ = communityId
        _ = text
    }

    func fetchLeagueBoardMessagesOlderThan(
        communityId: String,
        startAfter: DocumentSnapshot,
        limit: Int
    ) async throws -> [QueryDocumentSnapshot] {
        _ = communityId
        _ = startAfter
        _ = limit
        return []
    }

    func listGameDefinitions(communityId: String) async throws -> [GameDefinitionRecord] {
        _ = communityId
        return []
    }

    func createGameDefinition(communityId: String, name: String, rulesText: String?) async throws -> String {
        _ = communityId
        _ = name
        _ = rulesText
        return "ui-game-definition-1"
    }

    func updateGameDefinition(communityId: String, gameDefinitionId: String, name: String, rulesText: String?) async throws {
        _ = communityId
        _ = gameDefinitionId
        _ = name
        _ = rulesText
    }

    func deleteGameDefinition(communityId: String, gameDefinitionId: String) async throws {
        _ = communityId
        _ = gameDefinitionId
    }

    func createBracket(
        communityId: String,
        seedMethod: SeedMethod,
        teamSize: Int,
        gameType: String,
        customGameDefinitionId: String?
    ) async throws -> String {
        let id = "ui-bracket-\(brackets.count + 1)"
        brackets.insert(
            BracketListItem(
                bracketId: id,
                communityId: communityId,
                seedMethod: seedMethod,
                status: seedMethod == .manual ? "DRAFT" : "ACTIVE",
                teamSize: teamSize,
                gameType: gameType,
                customGameDefinitionId: customGameDefinitionId,
                customGameDefinitionName: nil,
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
            createdByProfileId: "ui-test-user",
            participantProfileIds: ["ui-test-user", "ui-opponent-1"],
            gameType: "PONG",
            customGameDefinitionName: nil,
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

    func fetchGameLogForEditing(gameLogId: String) async throws -> GameLogEditableSnapshot {
        GameLogEditableSnapshot(
            gameLogId: gameLogId,
            communityId: "ui-community-1",
            createdByProfileId: "ui-test-user",
            gameType: "PONG",
            customGameDefinitionName: nil,
            participantProfileIds: ["ui-test-user", "ui-opponent-1"],
            winnerProfileIds: ["ui-test-user"],
            loserProfileIds: ["ui-opponent-1"],
            mvpProfileId: nil,
            lvpProfileId: nil,
            photoUrls: ["https://example.com/game.jpg"],
            notes: nil,
            pongStats: nil,
            beerBallStats: nil,
            battlePongStats: nil,
            baseballStats: nil,
            crossfireStats: nil
        )
    }

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
final class UITestPlatformAdminService: PlatformAdminServiceProtocol {
    func listCommunitiesPage(startAfterCommunityId: String?, pageSize: Int) async throws -> AdminCommunitiesPageResult {
        _ = startAfterCommunityId
        _ = pageSize
        return AdminCommunitiesPageResult(items: [], nextCursor: nil, hasMore: false)
    }

    func listGameLogsPage(
        communityId: String?,
        cursor: AdminGameLogsCursor?,
        pageSize: Int
    ) async throws -> AdminGameLogsPageResult {
        _ = communityId
        _ = cursor
        _ = pageSize
        return AdminGameLogsPageResult(items: [], nextCursor: nil, hasMore: false)
    }

    func listAdminActionsPage(
        action: String?,
        targetCommunityId: String?,
        cursor: AdminActionsCursor?,
        pageSize: Int
    ) async throws -> AdminActionsPageResult {
        _ = action
        _ = targetCommunityId
        _ = cursor
        _ = pageSize
        return AdminActionsPageResult(items: [], nextCursor: nil, hasMore: false)
    }

    func kickMember(communityId: String, profileId: String) async throws {
        _ = communityId
        _ = profileId
    }

    func deleteGameLog(gameLogId: String) async throws {
        _ = gameLogId
    }

    func adminUpdateGameLog(payload: GameLogUpdatePayload) async throws {
        _ = payload
    }

    func deleteLeagueMessage(communityId: String, messageId: String) async throws {
        _ = communityId
        _ = messageId
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
        let platformAdmin = UITestPlatformAdminService()

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
            bracketService: community,
            platformAdminService: platformAdmin
        )
        let sessionManager = AppSessionManager(router: router, authService: auth, userService: user)
        return (container, router, sessionManager)
    }
}

