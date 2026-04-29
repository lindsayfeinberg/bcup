import FirebaseAuth
import FirebaseCore
import Foundation
import FirebaseFirestore
import FirebaseStorage

// MARK: - Service Protocols

@MainActor
protocol AuthServiceProtocol {
    func signIn() async throws
    func signOut() throws
    var currentUserId: String? { get }
    /// Reads `platformAdmin` from the Firebase ID token custom claims.
    func fetchPlatformAdminClaimFromIDToken(forceRefresh: Bool) async throws -> Bool
}

struct ProfileRecord {
    let userId: String
    let displayName: String?
    let profilePhotoUrl: String?
    let overallOdds: Double
    let overallGamesPlayed: Int
    /// Server-computed win rate (`wins/games`) per `gameLogs.gameType` key.
    let overallOddsByGameType: [String: Double]
    let overallGamesPlayedByGameType: [String: Int]
    let ageConfirmed21PlusAt: Date?
    let onboardingCompleteAt: Date?
}

/// League roster ordering: all games in the league vs. one game type (matches `gameLogs.gameType`).
enum LeagueRankingBasis: String, CaseIterable, Identifiable {
    case allGames = "ALL"
    case pong = "PONG"
    case beerBall = "BEER_BALL"
    case battlePong = "BATTLE_PONG"
    case baseball = "BASEBALL"
    case crossfire = "CROSSFIRE"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .allGames: return "All games"
        case .pong: return "Pong"
        case .beerBall: return "Beer Ball"
        case .battlePong: return "Battle Pong"
        case .baseball: return "Baseball"
        case .crossfire: return "Crossfire"
        }
    }

    /// Single game types only (excludes aggregate `allGames`), aligned with `gameLogs.gameType`.
    static var perGameTypeCases: [LeagueRankingBasis] {
        allCases.filter { $0 != .allGames }
    }

    /// Players-per-side bounds for this game category (before capping by league roster size).
    var baseTeamSizeRange: ClosedRange<Int> {
        switch self {
        case .allGames:
            return 1...25
        case .pong, .beerBall, .crossfire:
            return 1...25
        case .battlePong, .baseball:
            return 3...25
        }
    }

    /// Clamped range so both sides fit in `memberCount` league members (`floor(n/2)` cap per side).
    func validTeamSizeRange(memberCount: Int) -> ClosedRange<Int> {
        let leagueCap = max(1, memberCount / 2)
        let base = baseTeamSizeRange
        let upperBound = min(base.upperBound, leagueCap)
        if upperBound < base.lowerBound {
            return base.lowerBound...base.lowerBound
        }
        return base.lowerBound...upperBound
    }
}

/// League ranking / per-type stats scope: aggregate, built-in `gameLogs.gameType`, or `CUSTOM:{definitionId}` (matches server odds maps).
enum LeagueRankingChip: Hashable, Identifiable {
    case allGames
    case builtIn(LeagueRankingBasis)
    case customDefinition(id: String, name: String)

    var id: String {
        switch self {
        case .allGames:
            return "ALL"
        case .builtIn(let basis):
            return basis.rawValue
        case .customDefinition(let id, _):
            return "CUSTOM:\(id)"
        }
    }

    var displayName: String {
        switch self {
        case .allGames:
            return "All games"
        case .builtIn(let basis):
            return basis.displayName
        case .customDefinition(_, let name):
            return name
        }
    }

    /// Key into `communityOddsByGameType` / `communityGamesPlayedByGameType`. `nil` means use aggregate league fields.
    var communityStatsBucketKey: String? {
        switch self {
        case .allGames:
            return nil
        case .builtIn(let basis):
            return basis == .allGames ? nil : basis.rawValue
        case .customDefinition(let id, _):
            return "CUSTOM:\(id)"
        }
    }

    /// Rank-by grid: all games, each built-in type, then one chip per custom definition (sorted by name).
    static func rankingChips(gameDefinitions: [GameDefinitionRecord]) -> [LeagueRankingChip] {
        var chips: [LeagueRankingChip] = [.allGames]
        chips.append(contentsOf: LeagueRankingBasis.perGameTypeCases.map { .builtIn($0) })
        let sortedDefs = gameDefinitions.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        for def in sortedDefs {
            chips.append(.customDefinition(id: def.gameDefinitionId, name: def.name))
        }
        return chips
    }

    /// What-if: single-type stats only (no aggregate-all).
    static func whatIfGameChips(gameDefinitions: [GameDefinitionRecord]) -> [LeagueRankingChip] {
        var chips: [LeagueRankingChip] = LeagueRankingBasis.perGameTypeCases.map { .builtIn($0) }
        let sortedDefs = gameDefinitions.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        for def in sortedDefs {
            chips.append(.customDefinition(id: def.gameDefinitionId, name: def.name))
        }
        return chips
    }

    /// Team-size bounds for hypothetical matchups (custom games follow the same flexible range as Pong).
    func whatIfTeamSizeRange(memberCount: Int) -> ClosedRange<Int> {
        switch self {
        case .allGames:
            return LeagueRankingBasis.pong.validTeamSizeRange(memberCount: memberCount)
        case .builtIn(let basis):
            return basis.validTeamSizeRange(memberCount: memberCount)
        case .customDefinition:
            return LeagueRankingBasis.pong.validTeamSizeRange(memberCount: memberCount)
        }
    }
}

protocol UserServiceProtocol {
    func fetchProfile(userId: String) async throws -> ProfileRecord?
    /// Creates `profiles/{uid}` after 21+ confirmation (no `onboardingCompleteAt` yet).
    func createProfileAfterAgeConfirmation(userId: String) async throws
    /// Uploads image to `profilePhotos/{uid}/{fileName}` and returns download URL string.
    func uploadProfilePhoto(userId: String, data: Data, contentType: String, fileName: String) async throws -> String
    /// Sets display name, photo URL, and `onboardingCompleteAt`.
    func completeProfileOnboarding(userId: String, displayName: String, profilePhotoUrl: String) async throws
    /// Updates display name and photo URL without changing onboarding or server-owned odds fields.
    func updateProfile(userId: String, displayName: String, profilePhotoUrl: String) async throws
}

enum UserServiceError: LocalizedError {
    case emptyDisplayName

    var errorDescription: String? {
        switch self {
        case .emptyDisplayName:
            return "Enter a display name."
        }
    }
}
struct CommunityMemberRosterRow: Identifiable {
    let profileId: String
    let displayName: String
    let profilePhotoUrl: String?
    let communityOdds: Double
    let communityGamesPlayed: Int
    let communityOddsByGameType: [String: Double]
    let communityGamesPlayedByGameType: [String: Int]
    var id: String { profileId }

    init(
        profileId: String,
        displayName: String,
        profilePhotoUrl: String?,
        communityOdds: Double,
        communityGamesPlayed: Int,
        communityOddsByGameType: [String: Double] = [:],
        communityGamesPlayedByGameType: [String: Int] = [:]
    ) {
        self.profileId = profileId
        self.displayName = displayName
        self.profilePhotoUrl = profilePhotoUrl
        self.communityOdds = communityOdds
        self.communityGamesPlayed = communityGamesPlayed
        self.communityOddsByGameType = communityOddsByGameType
        self.communityGamesPlayedByGameType = communityGamesPlayedByGameType
    }

    func effectiveOdds(chip: LeagueRankingChip) -> Double {
        switch chip {
        case .allGames:
            return communityOdds
        case .builtIn(let basis):
            if basis == .allGames { return communityOdds }
            return communityOddsByGameType[basis.rawValue] ?? 0
        case .customDefinition(let id, _):
            return communityOddsByGameType["CUSTOM:\(id)"] ?? 0
        }
    }

    func effectiveOdds(basis: LeagueRankingBasis) -> Double {
        effectiveOdds(chip: .builtIn(basis))
    }

    func effectiveGamesPlayed(chip: LeagueRankingChip) -> Int {
        switch chip {
        case .allGames:
            return communityGamesPlayed
        case .builtIn(let basis):
            if basis == .allGames { return communityGamesPlayed }
            return communityGamesPlayedByGameType[basis.rawValue] ?? 0
        case .customDefinition(let id, _):
            return communityGamesPlayedByGameType["CUSTOM:\(id)"] ?? 0
        }
    }

    func effectiveGamesPlayed(basis: LeagueRankingBasis) -> Int {
        effectiveGamesPlayed(chip: .builtIn(basis))
    }

    /// Win rate used for hypothetical matchups: type-specific when the player has games in that type in this league; otherwise aggregate league odds (sparse fallback, mirrors server `effectiveOdds`).
    func resolvedOddsForMatchup(chip: LeagueRankingChip) -> Double {
        switch chip {
        case .allGames:
            return communityOdds
        case .builtIn(let basis):
            if basis == .allGames { return communityOdds }
            if effectiveGamesPlayed(chip: .builtIn(basis)) > 0 {
                return communityOddsByGameType[basis.rawValue] ?? communityOdds
            }
            return communityOdds
        case .customDefinition(let id, _):
            let key = "CUSTOM:\(id)"
            if effectiveGamesPlayed(chip: .customDefinition(id: id, name: "")) > 0 {
                return communityOddsByGameType[key] ?? communityOdds
            }
            return communityOdds
        }
    }

    func resolvedOddsForMatchup(basis: LeagueRankingBasis) -> Double {
        resolvedOddsForMatchup(chip: .builtIn(basis))
    }

    /// Games in the same scope as `resolvedOddsForMatchup` (for reconstructing W–L).
    private func matchupGamesPlayed(chip: LeagueRankingChip) -> Int {
        switch chip {
        case .allGames:
            return communityGamesPlayed
        case .builtIn(let basis):
            if basis == .allGames { return communityGamesPlayed }
            if effectiveGamesPlayed(chip: .builtIn(basis)) > 0 {
                return effectiveGamesPlayed(chip: .builtIn(basis))
            }
            return communityGamesPlayed
        case .customDefinition(let id, let name):
            let scoped = LeagueRankingChip.customDefinition(id: id, name: name)
            if effectiveGamesPlayed(chip: scoped) > 0 {
                return effectiveGamesPlayed(chip: scoped)
            }
            return communityGamesPlayed
        }
    }

    /// Integer wins implied by stored odds × games (same rounding as league member subtitles).
    private static func reconstructedWins(odds: Double, gamesPlayed: Int) -> Int {
        guard gamesPlayed > 0 else { return 0 }
        let raw = (odds * Double(gamesPlayed)).rounded()
        let w = Int(raw)
        return min(max(w, 0), gamesPlayed)
    }

    /// Laplace-smoothed strength `(wins + 1) / (games + 2)` for what-if matchups; dampens small-sample extremes.
    func laplaceSmoothedStrengthForMatchup(chip: LeagueRankingChip) -> Double {
        let odds = resolvedOddsForMatchup(chip: chip)
        let games = matchupGamesPlayed(chip: chip)
        let wins = Self.reconstructedWins(odds: odds, gamesPlayed: games)
        return Double(wins + 1) / Double(games + 2)
    }

    func laplaceSmoothedStrengthForMatchup(basis: LeagueRankingBasis) -> Double {
        laplaceSmoothedStrengthForMatchup(chip: .builtIn(basis))
    }
}

protocol CommunityServiceProtocol {
    func fetchCommunities() async throws -> [CommunityListItem]
    func fetchCommunitiesPage(
        cursor: CommunitiesPageCursor?,
        pageSize: Int
    ) async throws -> PagedResponse<[CommunityListItem], CommunitiesPageCursor>
    func fetchMembers(communityId: String) async throws -> [CommunityMemberRosterRow]
    func fetchBrackets(communityId: String) async throws -> [BracketListItem]
    func createCommunity(name: String) async throws -> (communityId: String, inviteCode: String, inviteLink: String)
    func joinCommunity(inviteCode: String) async throws -> String
    func previewJoinCommunity(inviteCode: String) async throws -> CommunityJoinPreview
    /// Creator-only callable: hide or unhide the league for non-creator members.
    func setCommunityHidden(communityId: String, hidden: Bool) async throws
    /// Resolve author labels from `memberships` roster rows (same source as feed; avoids `profiles` read denial).
    func resolveBoardAuthorDisplayNames(communityId: String, profileIds: [String]) async -> [String: String]
    /// Post a message to the league thread (`data-contracts` + Firestore rules Phase C2).
    func postLeagueBoardMessage(communityId: String, text: String) async throws
    /// Load older messages than `startAfter` (exclusive), newest-first query batch; used with board pagination.
    func fetchLeagueBoardMessagesOlderThan(
        communityId: String,
        startAfter: DocumentSnapshot,
        limit: Int
    ) async throws -> [QueryDocumentSnapshot]
    /// E1 custom game definitions under `communities/{communityId}/gameDefinitions/*`.
    func listGameDefinitions(communityId: String) async throws -> [GameDefinitionRecord]
    /// League-member callable (Admin SDK) to add a custom game definition.
    func createGameDefinition(communityId: String, name: String, rulesText: String?) async throws -> String
    /// League-member callable (Admin SDK) to update a custom game definition.
    func updateGameDefinition(communityId: String, gameDefinitionId: String, name: String, rulesText: String?) async throws
    /// League-member callable (Admin SDK) to delete a custom game definition.
    func deleteGameDefinition(communityId: String, gameDefinitionId: String) async throws
}

protocol GameLogServiceProtocol {
    func fetchLogs(communityId: String) async throws
    func canCurrentUserEditDelete(createdByProfileId: String) -> Bool
    func fetchGameLogForEditing(gameLogId: String) async throws -> GameLogEditableSnapshot
    func uploadGamePhoto(
        communityId: String,
        gameLogId: String,
        side: String,
        data: Data,
        contentType: String
    ) async throws -> String
    func createGameLog(payload: GameLogCreatePayload) async throws
    func updateGameLog(payload: GameLogUpdatePayload) async throws
    func deleteGameLog(gameLogId: String) async throws
}

// MARK: - Feed

struct FeedRow: Identifiable {
    let gameLogId: String
    let communityId: String
    let communityName: String?
    /// Log creator — used for edit/delete affordances (`gameLogs.createdByProfileId`).
    let createdByProfileId: String
    let participantProfileIds: [String]
    let gameType: String
    /// Denormalized display label when `gameType == "CUSTOM"` (optional on older logs).
    let customGameDefinitionName: String?
    let winnerProfileIds: [String]
    let loserProfileIds: [String]
    let winnerNames: [String]
    let loserNames: [String]
    let mvpProfileId: String?
    let lvpProfileId: String?
    /// Resolved display names for MVP/LVP when set (for back-of-card copy).
    let mvpDisplayName: String?
    let lvpDisplayName: String?
    /// Formatted game-type stats (multi-line), or nil when none stored.
    let statsSummary: String?
    /// Optional caption text from the game log (shown under the photo on the feed).
    let notes: String?
    let photoUrls: [String]
    let createdAt: Date
    var id: String { gameLogId }

    var primaryPhotoUrl: URL? {
        photoUrls.first.flatMap { URL(string: $0) }
    }

    var winnersText: String {
        winnerNames.isEmpty
            ? winnerProfileIds.joined(separator: ", ")
            : winnerNames.joined(separator: ", ")
    }

    var losersText: String {
        loserNames.isEmpty
            ? loserProfileIds.joined(separator: ", ")
            : loserNames.joined(separator: ", ")
    }

    /// Back-of-card rows only: Winners, Losers, MVP, LVP, Stats (empty optional rows are omitted).
    func backDetailRows() -> [(title: String, value: String)] {
        let ordered: [(String, String?)] = [
            ("Winners", winnersText.isEmpty ? nil : winnersText),
            ("Losers", losersText.isEmpty ? nil : losersText),
            ("MVP", mvpDisplayName),
            ("LVP", lvpDisplayName),
            ("Stats", statsSummary.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 })
        ]
        return ordered.compactMap { title, value in value.map { (title, $0) } }
    }
}

struct PagedResponse<Items, Cursor> {
    let items: Items
    let nextCursor: Cursor?
    let hasMore: Bool
}

struct FeedPageCursor {
    let createdAt: Timestamp
    let documentId: String
}

struct HomeFeedPageCursor {
    let createdAt: Timestamp
    let documentId: String
}

struct CommunitiesPageCursor {
    let membershipDocumentId: String
}

/// One row in `communities/{communityId}/messages/*` (league board / Phase C).
struct LeagueBoardMessage: Identifiable, Equatable {
    let id: String
    let authorProfileId: String
    let authorDisplayName: String
    let text: String
    let createdAt: Date
}

/// One league row for lists (Leagues tab, new game form). Matches `communities/*` fields used by the client.
struct CommunityListItem: Hashable, Identifiable {
    var id: String { communityId }
    let communityId: String
    let name: String
    let hiddenFromMembers: Bool
    let createdByProfileId: String

    /// Shown under **Active**: not hidden (hidden leagues never appear here, even for the host).
    var appearsOnActiveTab: Bool { !hiddenFromMembers }

    /// Shown under **Hidden** for the league creator only.
    func appearsInHiddenCreatorList(forCurrentUserId userId: String) -> Bool {
        hiddenFromMembers && createdByProfileId == userId
    }
}

protocol FeedServiceProtocol {
    /// Returns recent logs scoped to the signed-in user's communities.
    func fetchFeed() async throws -> [FeedRow]
    /// Returns recent logs for a single community (caller must be a member; rules enforce read access).
    func fetchFeed(forCommunityId communityId: String) async throws -> [FeedRow]
    /// Returns one page of the home feed scoped to the signed-in user's communities.
    func fetchFeedPage(
        cursor: HomeFeedPageCursor?,
        pageSize: Int
    ) async throws -> PagedResponse<[FeedRow], HomeFeedPageCursor>
    /// Returns one page of a community-scoped feed.
    func fetchFeedPage(
        forCommunityId communityId: String,
        cursor: FeedPageCursor?,
        pageSize: Int
    ) async throws -> PagedResponse<[FeedRow], FeedPageCursor>
}

// MARK: - Bracket

enum SeedMethod: String, CaseIterable, Identifiable {
    case communityOdds = "COMMUNITY_ODDS"
    case manual = "MANUAL"
    case random = "RANDOM"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .communityOdds: return "League Odds"
        case .manual: return "Manual"
        case .random: return "Random"
        }
    }

    var subtitle: String {
        switch self {
        case .communityOdds: return "Seed by win rate in this league"
        case .manual: return "Pick the order yourself"
        case .random: return "Randomly assign seeds"
        }
    }
}

enum BracketServiceError: LocalizedError {
    case invalidResponse
    case notAMember
    case tooFewMembers

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Unexpected response from server."
        case .notAMember: return "You are not a member of this league."
        case .tooFewMembers: return "Need at least 2 members to create a bracket."
        }
    }
}

protocol BracketServiceProtocol {
    func createBracket(
        communityId: String,
        seedMethod: SeedMethod,
        teamSize: Int,
        gameType: String,
        customGameDefinitionId: String?
    ) async throws -> String
    func finalizeManualBracket(
        bracketId: String,
        teams: [[String]]
    ) async throws
}

struct BracketListItem: Identifiable, Hashable {
    let bracketId: String
    let communityId: String
    let seedMethod: SeedMethod
    let status: String
    let teamSize: Int
    let gameType: String
    let customGameDefinitionId: String?
    let customGameDefinitionName: String?
    let createdAt: Date?

    var id: String { bracketId }

    var gameTypeSummary: String {
        if gameType == "CUSTOM" {
            let n = customGameDefinitionName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return n.isEmpty ? "Custom game" : n
        }
        return gameType.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
// MARK: - Container

@MainActor
final class DependencyContainer: ObservableObject {
    let authService: AuthServiceProtocol
    let userService: UserServiceProtocol
    let communityService: CommunityServiceProtocol
    let gameLogService: GameLogServiceProtocol
    let feedService: FeedServiceProtocol
    let bracketService: BracketServiceProtocol
    let platformAdminService: PlatformAdminServiceProtocol

    init() {
        self.authService = GoogleAuthService()
        self.userService = UserService()
        let cs = CommunityService()
        self.communityService = cs
        let gls = GameLogService()
        self.gameLogService = gls
        self.feedService = gls
        self.bracketService = cs
        self.platformAdminService = PlatformAdminService()
    }

    init(
        authService: AuthServiceProtocol,
        userService: UserServiceProtocol,
        communityService: CommunityServiceProtocol,
        gameLogService: GameLogServiceProtocol,
        feedService: FeedServiceProtocol,
        bracketService: BracketServiceProtocol,
        platformAdminService: PlatformAdminServiceProtocol
    ) {
        self.authService = authService
        self.userService = userService
        self.communityService = communityService
        self.gameLogService = gameLogService
        self.feedService = feedService
        self.bracketService = bracketService
        self.platformAdminService = platformAdminService
    }
}

struct CommunityJoinPreview {
    let communityId: String
    let name: String
    let memberCount: Int
}

struct GameDefinitionRecord: Identifiable, Hashable {
    let gameDefinitionId: String
    let communityId: String
    let name: String
    let rulesText: String?
    let createdByProfileId: String
    let createdAt: Date?
    let updatedAt: Date?

    var id: String { gameDefinitionId }
}

struct GameLogCreatePayload {
    let gameLogId: String
    let communityId: String
    let bracketId: String?
    let bracketMatchId: String?
    let gameType: String
    /// When `gameType` is `CUSTOM`, Firestore rules require this (league `gameDefinitions` doc id).
    let customGameDefinitionId: String?
    /// Snapshot of definition name at create time (feed / history); optional for older clients.
    let customGameDefinitionName: String?
    let createdByProfileId: String
    let participantProfileIds: [String]
    let winnerProfileIds: [String]
    let loserProfileIds: [String]
    let mvpProfileId: String?
    let lvpProfileId: String?
    let photoUrls: [String]
    let notes: String?
    let pongStats: [String: Any]?
    let beerBallStats: [String: Any]?
    let battlePongStats: [String: Any]?
    let baseballStats: [String: Any]?
    let crossfireStats: [String: Any]?

    init(
        gameLogId: String,
        communityId: String,
        bracketId: String?,
        bracketMatchId: String?,
        gameType: String,
        customGameDefinitionId: String? = nil,
        customGameDefinitionName: String? = nil,
        createdByProfileId: String,
        participantProfileIds: [String],
        winnerProfileIds: [String],
        loserProfileIds: [String],
        mvpProfileId: String?,
        lvpProfileId: String?,
        photoUrls: [String],
        notes: String?,
        pongStats: [String: Any]?,
        beerBallStats: [String: Any]?,
        battlePongStats: [String: Any]?,
        baseballStats: [String: Any]?,
        crossfireStats: [String: Any]?
    ) {
        self.gameLogId = gameLogId
        self.communityId = communityId
        self.bracketId = bracketId
        self.bracketMatchId = bracketMatchId
        self.gameType = gameType
        self.customGameDefinitionId = customGameDefinitionId
        self.customGameDefinitionName = customGameDefinitionName
        self.createdByProfileId = createdByProfileId
        self.participantProfileIds = participantProfileIds
        self.winnerProfileIds = winnerProfileIds
        self.loserProfileIds = loserProfileIds
        self.mvpProfileId = mvpProfileId
        self.lvpProfileId = lvpProfileId
        self.photoUrls = photoUrls
        self.notes = notes
        self.pongStats = pongStats
        self.beerBallStats = beerBallStats
        self.battlePongStats = battlePongStats
        self.baseballStats = baseballStats
        self.crossfireStats = crossfireStats
    }
}

struct GameLogUpdatePayload {
    let gameLogId: String
    /// Immutable on `gameLogs`; included for completeness / admin tooling (optional).
    let customGameDefinitionId: String?
    let participantProfileIds: [String]
    let winnerProfileIds: [String]
    let loserProfileIds: [String]
    let mvpProfileId: String?
    let lvpProfileId: String?
    let photoUrls: [String]
    let notes: String?
    let pongStats: [String: Any]?
    let beerBallStats: [String: Any]?
    let battlePongStats: [String: Any]?
    let baseballStats: [String: Any]?
    let crossfireStats: [String: Any]?

    init(
        gameLogId: String,
        customGameDefinitionId: String? = nil,
        participantProfileIds: [String],
        winnerProfileIds: [String],
        loserProfileIds: [String],
        mvpProfileId: String?,
        lvpProfileId: String?,
        photoUrls: [String],
        notes: String?,
        pongStats: [String: Any]?,
        beerBallStats: [String: Any]?,
        battlePongStats: [String: Any]?,
        baseballStats: [String: Any]?,
        crossfireStats: [String: Any]?
    ) {
        self.gameLogId = gameLogId
        self.customGameDefinitionId = customGameDefinitionId
        self.participantProfileIds = participantProfileIds
        self.winnerProfileIds = winnerProfileIds
        self.loserProfileIds = loserProfileIds
        self.mvpProfileId = mvpProfileId
        self.lvpProfileId = lvpProfileId
        self.photoUrls = photoUrls
        self.notes = notes
        self.pongStats = pongStats
        self.beerBallStats = beerBallStats
        self.battlePongStats = battlePongStats
        self.baseballStats = baseballStats
        self.crossfireStats = crossfireStats
    }
}

/// Fields loaded from `gameLogs/{id}` to hydrate the edit form (`NewGameLogFormView`).
struct GameLogEditableSnapshot {
    let gameLogId: String
    let communityId: String
    let createdByProfileId: String
    let gameType: String
    let customGameDefinitionId: String?
    let customGameDefinitionName: String?
    let participantProfileIds: [String]
    let winnerProfileIds: [String]
    let loserProfileIds: [String]
    let mvpProfileId: String?
    let lvpProfileId: String?
    let photoUrls: [String]
    let notes: String?
    let pongStats: [String: Any]?
    let beerBallStats: [String: Any]?
    let battlePongStats: [String: Any]?
    let baseballStats: [String: Any]?
    let crossfireStats: [String: Any]?

    init(
        gameLogId: String,
        communityId: String,
        createdByProfileId: String,
        gameType: String,
        customGameDefinitionId: String? = nil,
        customGameDefinitionName: String? = nil,
        participantProfileIds: [String],
        winnerProfileIds: [String],
        loserProfileIds: [String],
        mvpProfileId: String?,
        lvpProfileId: String?,
        photoUrls: [String],
        notes: String?,
        pongStats: [String: Any]?,
        beerBallStats: [String: Any]?,
        battlePongStats: [String: Any]?,
        baseballStats: [String: Any]?,
        crossfireStats: [String: Any]?
    ) {
        self.gameLogId = gameLogId
        self.communityId = communityId
        self.createdByProfileId = createdByProfileId
        self.gameType = gameType
        self.customGameDefinitionId = customGameDefinitionId
        self.customGameDefinitionName = customGameDefinitionName
        self.participantProfileIds = participantProfileIds
        self.winnerProfileIds = winnerProfileIds
        self.loserProfileIds = loserProfileIds
        self.mvpProfileId = mvpProfileId
        self.lvpProfileId = lvpProfileId
        self.photoUrls = photoUrls
        self.notes = notes
        self.pongStats = pongStats
        self.beerBallStats = beerBallStats
        self.battlePongStats = battlePongStats
        self.baseballStats = baseballStats
        self.crossfireStats = crossfireStats
    }
}

// MARK: - Default Service Implementations

private enum FirestoreStringKeyMaps {
    static func stringToDouble(_ value: Any?) -> [String: Double] {
        guard let dict = value as? [String: Any] else { return [:] }
        var out: [String: Double] = [:]
        out.reserveCapacity(dict.count)
        for (key, v) in dict {
            if let d = v as? Double {
                out[key] = d
            } else if let n = v as? NSNumber {
                out[key] = n.doubleValue
            } else if let i = v as? Int {
                out[key] = Double(i)
            }
        }
        return out
    }

    static func stringToInt(_ value: Any?) -> [String: Int] {
        guard let dict = value as? [String: Any] else { return [:] }
        var out: [String: Int] = [:]
        out.reserveCapacity(dict.count)
        for (key, v) in dict {
            if let i = v as? Int {
                out[key] = i
            } else if let n = v as? NSNumber {
                out[key] = n.intValue
            } else if let d = v as? Double {
                out[key] = Int(d)
            }
        }
        return out
    }
}

final class UserService: UserServiceProtocol {
    func fetchProfile(userId: String) async throws -> ProfileRecord? {
        try await ProfileFetchGate.shared.run(userId: userId) {
            try await Self.fetchProfileOnceWithPermissionRetry(userId: userId)
        }
    }

    /// One retry after forced ID token refresh when Firestore returns `permission_denied` (rules + auth token timing).
    private static func fetchProfileOnceWithPermissionRetry(userId: String) async throws -> ProfileRecord? {
        do {
            return try await fetchProfileOnce(userId: userId)
        } catch {
            let ns = error as NSError
            guard ns.domain == FirestoreErrorDomain,
                  ns.code == FirestoreErrorCode.permissionDenied.rawValue,
                  let user = Auth.auth().currentUser
            else {
                throw error
            }
            AppDebugLog.log("UserService.fetchProfile: permission_denied — forcing ID token refresh and retrying once")
            try await Self.forceRefreshIDToken(user: user)
            return try await fetchProfileOnce(userId: userId)
        }
    }

    private static func forceRefreshIDToken(user: User) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            user.getIDTokenForcingRefresh(true) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Single Firestore read (not coalesced — use `fetchProfile` from app code).
    private static func fetchProfileOnce(userId: String) async throws -> ProfileRecord? {
        let db = AppFirestore.db()
        AppDebugLog.log("UserService.fetchProfile: GET profiles/\(userId)")
        let snapshot = try await db
            .collection("profiles")
            .document(userId)
            .getDocument()

        guard snapshot.exists else {
            AppDebugLog.log("UserService.fetchProfile: document missing — returning nil")
            return nil
        }

        let data = snapshot.data() ?? [:]
        let onboardingCompleteAt = Self.parseDate(from: data["onboardingCompleteAt"])
        let ageConfirmed21PlusAt = Self.parseDate(from: data["ageConfirmed21PlusAt"])
        let displayName = data["displayName"] as? String
        let profilePhotoUrl = data["profilePhotoUrl"] as? String
        let overallOdds = (data["overallOdds"] as? Double)
            ?? (data["overallOdds"] as? Int).map(Double.init)
            ?? 0.0
        let overallGamesPlayed = (data["overallGamesPlayed"] as? Int)
            ?? (data["overallGamesPlayed"] as? Double).map(Int.init)
            ?? 0
        let overallOddsByGameType = FirestoreStringKeyMaps.stringToDouble(data["overallOddsByGameType"])
        let overallGamesPlayedByGameType = FirestoreStringKeyMaps.stringToInt(data["overallGamesPlayedByGameType"])
        AppDebugLog.log("UserService.fetchProfile: exists onboardingCompleteAt=\(onboardingCompleteAt != nil) age21=\(ageConfirmed21PlusAt != nil)")
        return ProfileRecord(
            userId: userId,
            displayName: displayName,
            profilePhotoUrl: profilePhotoUrl,
            overallOdds: overallOdds,
            overallGamesPlayed: overallGamesPlayed,
            overallOddsByGameType: overallOddsByGameType,
            overallGamesPlayedByGameType: overallGamesPlayedByGameType,
            ageConfirmed21PlusAt: ageConfirmed21PlusAt,
            onboardingCompleteAt: onboardingCompleteAt
        )
    }

    func createProfileAfterAgeConfirmation(userId: String) async throws {
        AppDebugLog.log("UserService.createProfileAfterAgeConfirmation: profiles/\(userId)")
        let now = Timestamp(date: Date())
        let data: [String: Any] = [
            "id": userId,
            "googleAuthId": userId,
            "displayName": "",
            "profilePhotoUrl": "",
            "overallOdds": 0,
            "overallGamesPlayed": 0,
            "ageConfirmed21PlusAt": now,
            "createdAt": now,
            "updatedAt": now
        ]
        try await AppFirestore.db()
            .collection("profiles")
            .document(userId)
            .setData(data)
        AppDebugLog.log("UserService.createProfileAfterAgeConfirmation: wrote profile shell")
    }

    func uploadProfilePhoto(userId: String, data: Data, contentType: String, fileName: String) async throws -> String {
        AppDebugLog.log("UserService.uploadProfilePhoto: profilePhotos/\(userId)/\(fileName)")
        let ref = Storage.storage().reference().child("profilePhotos/\(userId)/\(fileName)")
        let metadata = StorageMetadata()
        metadata.contentType = contentType
        metadata.cacheControl = "public,max-age=31536000,immutable"
        _ = try await ref.putDataAsync(data, metadata: metadata)
        let url = try await ref.downloadURL()
        AppDebugLog.log("UserService.uploadProfilePhoto: downloadURL OK")
        return url.absoluteString
    }

    func completeProfileOnboarding(userId: String, displayName: String, profilePhotoUrl: String) async throws {
        AppDebugLog.log("UserService.completeProfileOnboarding: update profiles/\(userId)")
        let now = Timestamp(date: Date())
        try await AppFirestore.db()
            .collection("profiles")
            .document(userId)
            .updateData([
                "displayName": displayName,
                "profilePhotoUrl": profilePhotoUrl,
                "onboardingCompleteAt": now,
                "updatedAt": now
            ])
        AppDebugLog.log("UserService.completeProfileOnboarding: onboardingCompleteAt set")
    }

    func updateProfile(userId: String, displayName: String, profilePhotoUrl: String) async throws {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw UserServiceError.emptyDisplayName
        }
        AppDebugLog.log("UserService.updateProfile: update profiles/\(userId)")
        let now = Timestamp(date: Date())
        try await AppFirestore.db()
            .collection("profiles")
            .document(userId)
            .updateData([
                "displayName": trimmed,
                "profilePhotoUrl": profilePhotoUrl,
                "updatedAt": now
            ])
        AppDebugLog.log("UserService.updateProfile: OK")
    }

    private static func parseDate(from value: Any?) -> Date? {
        if let timestamp = value as? Timestamp {
            return timestamp.dateValue()
        }
        if let date = value as? Date {
            return date
        }
        if let string = value as? String {
            return ISO8601DateFormatter().date(from: string)
        }
        return nil
    }
}

enum CommunityServiceError: LocalizedError {
    case emptyName
    case emptyInviteCode
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Enter a league name."
        case .emptyInviteCode:
            return "Enter an invite code."
        case .invalidResponse:
            return "Unexpected response from server."
        }
    }
}

final class CommunityService: CommunityServiceProtocol {
    /// Matches `createCommunity` / `joinCommunity` in Cloud Functions (`functions/src/communities.ts`).
    private static let functionsRegion = "us-central1"

    func fetchCommunities() async throws -> [CommunityListItem] {
        var all: [CommunityListItem] = []
        var cursor: CommunitiesPageCursor?
        let pageSize = 25

        while true {
            let page = try await fetchCommunitiesPage(cursor: cursor, pageSize: pageSize)
            all.append(contentsOf: page.items)
            guard page.hasMore, let next = page.nextCursor else { break }
            cursor = next
        }
        return all
    }

    func fetchCommunitiesPage(
        cursor: CommunitiesPageCursor?,
        pageSize: Int
    ) async throws -> PagedResponse<[CommunityListItem], CommunitiesPageCursor> {
        guard let userId = Auth.auth().currentUser?.uid else {
            return PagedResponse(items: [], nextCursor: nil, hasMore: false)
        }

        let db = AppFirestore.db()
        var query: Query = db
            .collection("memberships")
            .whereField("profileId", isEqualTo: userId)
            .order(by: FieldPath.documentID())
            .limit(to: pageSize)

        if let cursor {
            query = query.start(after: [cursor.membershipDocumentId])
        }

        let memberships = try await query.getDocuments()

        let orderedCommunityIds: [String] = memberships.documents.compactMap {
            $0.data()["communityId"] as? String
        }
        let uniqueCommunityIds = Array(Set(orderedCommunityIds))

        struct CommunityDocSnapshot {
            let name: String
            let hiddenFromMembers: Bool
            let createdByProfileId: String
        }
        var byCommunityId: [String: CommunityDocSnapshot] = [:]
        await withTaskGroup(of: (String, CommunityDocSnapshot?).self) { group in
            for communityId in uniqueCommunityIds {
                group.addTask {
                    do {
                        let communityDoc = try await db.collection("communities").document(communityId).getDocument()
                        guard let data = communityDoc.data(),
                              let name = data["name"] as? String, !name.isEmpty,
                              let createdBy = data["createdByProfileId"] as? String
                        else {
                            return (communityId, nil)
                        }
                        let hidden = (data["hiddenFromMembers"] as? Bool) ?? false
                        return (communityId, CommunityDocSnapshot(
                            name: name,
                            hiddenFromMembers: hidden,
                            createdByProfileId: createdBy
                        ))
                    } catch {
                        return (communityId, nil)
                    }
                }
            }
            for await (communityId, snapshot) in group {
                if let snapshot {
                    byCommunityId[communityId] = snapshot
                }
            }
        }

        var communities: [CommunityListItem] = []
        communities.reserveCapacity(orderedCommunityIds.count)
        var seen = Set<String>()
        for communityId in orderedCommunityIds where seen.insert(communityId).inserted {
            if let s = byCommunityId[communityId] {
                communities.append(
                    CommunityListItem(
                        communityId: communityId,
                        name: s.name,
                        hiddenFromMembers: s.hiddenFromMembers,
                        createdByProfileId: s.createdByProfileId
                    )
                )
            }
        }

        let hasMore = memberships.documents.count == pageSize
        let nextCursor = memberships.documents.last.map {
            CommunitiesPageCursor(membershipDocumentId: $0.documentID)
        }
        return PagedResponse(items: communities, nextCursor: hasMore ? nextCursor : nil, hasMore: hasMore)
    }
    func fetchMembers(communityId: String) async throws -> [CommunityMemberRosterRow] {
        guard let currentUserId = Auth.auth().currentUser?.uid else { return [] }
        let db = AppFirestore.db()
        let memberships = try await db
            .collection("memberships")
            .whereField("communityId", isEqualTo: communityId)
            .getDocuments()

        var members: [CommunityMemberRosterRow] = []
        for doc in memberships.documents {
            let membershipData = doc.data()
            guard let profileId = membershipData["profileId"] as? String else { continue }

            let communityOdds = (membershipData["communityOdds"] as? Double)
                ?? (membershipData["communityOdds"] as? Int).map(Double.init)
                ?? 0.0
            let communityGamesPlayed = (membershipData["communityGamesPlayed"] as? Int)
                ?? (membershipData["communityGamesPlayed"] as? Double).map(Int.init)
                ?? 0
            let communityOddsByGameType = FirestoreStringKeyMaps.stringToDouble(membershipData["communityOddsByGameType"])
            let communityGamesPlayedByGameType = FirestoreStringKeyMaps.stringToInt(membershipData["communityGamesPlayedByGameType"])

            let displayNameFromMembership = membershipData["displayName"] as? String
            let profilePhotoUrlFromMembership = membershipData["profilePhotoUrl"] as? String
            if let displayNameFromMembership, !displayNameFromMembership.isEmpty {
                members.append(CommunityMemberRosterRow(
                    profileId: profileId,
                    displayName: displayNameFromMembership,
                    profilePhotoUrl: profilePhotoUrlFromMembership,
                    communityOdds: communityOdds,
                    communityGamesPlayed: communityGamesPlayed,
                    communityOddsByGameType: communityOddsByGameType,
                    communityGamesPlayedByGameType: communityGamesPlayedByGameType
                ))
                continue
            }

            // Legacy fallback: only read your own profile (allowed by rules).
            if profileId == currentUserId {
                let profileDoc = try await db
                    .collection("profiles")
                    .document(profileId)
                    .getDocument()
                let displayName = profileDoc.data()?["displayName"] as? String ?? ""
                let profilePhotoUrl = profileDoc.data()?["profilePhotoUrl"] as? String
                members.append(CommunityMemberRosterRow(
                    profileId: profileId,
                    displayName: displayName,
                    profilePhotoUrl: profilePhotoUrl,
                    communityOdds: communityOdds,
                    communityGamesPlayed: communityGamesPlayed,
                    communityOddsByGameType: communityOddsByGameType,
                    communityGamesPlayedByGameType: communityGamesPlayedByGameType
                ))
            } else {
                members.append(CommunityMemberRosterRow(
                    profileId: profileId,
                    displayName: "",
                    profilePhotoUrl: profilePhotoUrlFromMembership,
                    communityOdds: communityOdds,
                    communityGamesPlayed: communityGamesPlayed,
                    communityOddsByGameType: communityOddsByGameType,
                    communityGamesPlayedByGameType: communityGamesPlayedByGameType
                ))
            }
        }
        return members
    }

    func fetchBrackets(communityId: String) async throws -> [BracketListItem] {
        let db = AppFirestore.db()
        let snapshot = try await db
            .collection("brackets")
            .whereField("communityId", isEqualTo: communityId)
            .order(by: "createdAt", descending: true)
            .getDocuments()

        return snapshot.documents.compactMap { doc in
            let d = doc.data()
            guard let seedMethodRaw = d["seedMethod"] as? String,
                  let seedMethod = SeedMethod(rawValue: seedMethodRaw),
                  let status = d["status"] as? String
            else {
                return nil
            }

            let teamSize = (d["teamSize"] as? Int)
                ?? (d["teamSize"] as? Double).map(Int.init)
                ?? 1
            let gameTypeRaw = (d["gameType"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let gameType = gameTypeRaw.isEmpty ? "PONG" : gameTypeRaw
            let customIdRaw = (d["customGameDefinitionId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let customDefId = customIdRaw.isEmpty ? nil : customIdRaw
            let customNameRaw = (d["customGameDefinitionName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let customDefName = customNameRaw.isEmpty ? nil : customNameRaw
            let createdAt = (d["createdAt"] as? Timestamp)?.dateValue()
            return BracketListItem(
                bracketId: doc.documentID,
                communityId: communityId,
                seedMethod: seedMethod,
                status: status,
                teamSize: teamSize,
                gameType: gameType,
                customGameDefinitionId: customDefId,
                customGameDefinitionName: customDefName,
                createdAt: createdAt
            )
        }
    }

    func createCommunity(name: String) async throws -> (communityId: String, inviteCode: String, inviteLink: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CommunityServiceError.emptyName }
        AppDebugLog.log("createCommunity: calling with name=\(trimmed)")
        do {
            let result = try await CallableTransport.post(functionName: "createCommunity", payload: ["name": trimmed])
            let data = try CallableTransport.unwrapEnvelope(result)
            guard let communityId = data["communityId"] as? String,
                  let inviteCode = data["inviteCode"] as? String,
                  let inviteLink = data["inviteLink"] as? String
            else {
                throw CommunityServiceError.invalidResponse
            }
            return (communityId, inviteCode, inviteLink)
        } catch {
            throw CallableTransport.mapCallableNetworkError(error)
        }
    }

    func joinCommunity(inviteCode: String) async throws -> String {
        let trimmed = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { throw CommunityServiceError.emptyInviteCode }
        do {
            let result = try await CallableTransport.post(functionName: "joinCommunity", payload: ["inviteCode": trimmed])
            let data = try CallableTransport.unwrapEnvelope(result)
            guard let communityId = data["communityId"] as? String else {
                throw CommunityServiceError.invalidResponse
            }
            return communityId
        } catch {
            throw CallableTransport.mapCallableNetworkError(error)
        }
    }

    func previewJoinCommunity(inviteCode: String) async throws -> CommunityJoinPreview {
        let trimmed = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { throw CommunityServiceError.emptyInviteCode }
        do {
            let result = try await CallableTransport.post(
                functionName: "previewJoinCommunity",
                payload: ["inviteCode": trimmed]
            )
            let data = try CallableTransport.unwrapEnvelope(result)
            guard let communityId = data["communityId"] as? String,
                  let name = data["name"] as? String
            else {
                throw CommunityServiceError.invalidResponse
            }

            let memberCount: Int
            if let i = data["memberCount"] as? Int {
                memberCount = i
            } else if let d = data["memberCount"] as? Double {
                memberCount = Int(d)
            } else {
                throw CommunityServiceError.invalidResponse
            }

            return CommunityJoinPreview(communityId: communityId, name: name, memberCount: memberCount)
        } catch {
            throw CallableTransport.mapCallableNetworkError(error)
        }
    }

    func setCommunityHidden(communityId: String, hidden: Bool) async throws {
        let trimmed = communityId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CommunityServiceError.invalidResponse }
        do {
            let result = try await CallableTransport.post(
                functionName: "setCommunityHidden",
                payload: ["communityId": trimmed, "hidden": hidden]
            )
            let data = try CallableTransport.unwrapEnvelope(result)
            guard data["communityId"] as? String != nil else {
                throw CommunityServiceError.invalidResponse
            }
        } catch {
            throw CallableTransport.mapCallableNetworkError(error)
        }
    }

    func resolveBoardAuthorDisplayNames(communityId: String, profileIds: [String]) async -> [String: String] {
        await Self.leagueBoardFetchAuthorNamesFromMemberships(
            db: AppFirestore.db(),
            communityId: communityId,
            profileIds: profileIds
        )
    }

    func postLeagueBoardMessage(communityId: String, text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(
                domain: "CommunityService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Message cannot be empty."]
            )
        }
        guard trimmed.count <= 4_000 else {
            throw NSError(
                domain: "CommunityService",
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Message is too long (max 4000 characters)."]
            )
        }
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(
                domain: "CommunityService",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Sign in to post."]
            )
        }
        let cid = communityId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cid.isEmpty else { throw CommunityServiceError.invalidResponse }
        let db = AppFirestore.db()
        let coll = db.collection("communities").document(cid).collection("messages")
        let doc = coll.document()
        try await doc.setData([
            "id": doc.documentID,
            "communityId": cid,
            "authorProfileId": uid,
            "text": trimmed,
            "deleted": false,
            "createdAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }

    func fetchLeagueBoardMessagesOlderThan(
        communityId: String,
        startAfter: DocumentSnapshot,
        limit: Int
    ) async throws -> [QueryDocumentSnapshot] {
        let cid = communityId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cid.isEmpty else { return [] }
        let db = AppFirestore.db()
        let snap = try await db.collection("communities").document(cid).collection("messages")
            .whereField("deleted", isEqualTo: false)
            .order(by: "createdAt", descending: true)
            .order(by: FieldPath.documentID(), descending: true)
            .limit(to: limit)
            .start(afterDocument: startAfter)
            .getDocuments()
        return snap.documents
    }

    func listGameDefinitions(communityId: String) async throws -> [GameDefinitionRecord] {
        let cid = communityId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cid.isEmpty else { throw CommunityServiceError.invalidResponse }
        do {
            let result = try await CallableTransport.post(
                functionName: "listGameDefinitions",
                payload: ["communityId": cid]
            )
            let data = try CallableTransport.unwrapEnvelope(result)
            let rawItems = data["items"] as? [[String: Any]] ?? []
            return rawItems.compactMap { row in
                guard let id = row["gameDefinitionId"] as? String else { return nil }
                let rulesRaw = row["rulesText"] as? String
                let createdMillis = (row["createdAtMillis"] as? NSNumber)?.doubleValue
                    ?? (row["createdAtMillis"] as? Double)
                    ?? (row["createdAtMillis"] as? Int).map(Double.init)
                let updatedMillis = (row["updatedAtMillis"] as? NSNumber)?.doubleValue
                    ?? (row["updatedAtMillis"] as? Double)
                    ?? (row["updatedAtMillis"] as? Int).map(Double.init)
                return GameDefinitionRecord(
                    gameDefinitionId: id,
                    communityId: row["communityId"] as? String ?? cid,
                    name: row["name"] as? String ?? "",
                    rulesText: rulesRaw?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? rulesRaw : nil,
                    createdByProfileId: row["createdByProfileId"] as? String ?? "",
                    createdAt: createdMillis.map { Date(timeIntervalSince1970: $0 / 1000.0) },
                    updatedAt: updatedMillis.map { Date(timeIntervalSince1970: $0 / 1000.0) }
                )
            }
        } catch {
            throw CallableTransport.mapCallableNetworkError(error)
        }
    }

    func createGameDefinition(communityId: String, name: String, rulesText: String?) async throws -> String {
        let cid = communityId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cid.isEmpty, !trimmedName.isEmpty else { throw CommunityServiceError.invalidResponse }
        let rulesPayload = rulesText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rulesValue: Any = (rulesPayload?.isEmpty == false) ? (rulesPayload as Any) : NSNull()
        do {
            let result = try await CallableTransport.post(
                functionName: "createGameDefinition",
                payload: [
                    "communityId": cid,
                    "name": trimmedName,
                    "rulesText": rulesValue
                ]
            )
            let data = try CallableTransport.unwrapEnvelope(result)
            guard let id = data["gameDefinitionId"] as? String else {
                throw CommunityServiceError.invalidResponse
            }
            return id
        } catch {
            throw CallableTransport.mapCallableNetworkError(error)
        }
    }

    func updateGameDefinition(communityId: String, gameDefinitionId: String, name: String, rulesText: String?) async throws {
        let cid = communityId.trimmingCharacters(in: .whitespacesAndNewlines)
        let gid = gameDefinitionId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cid.isEmpty, !gid.isEmpty, !trimmedName.isEmpty else { throw CommunityServiceError.invalidResponse }
        let rulesPayload = rulesText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rulesValue: Any = (rulesPayload?.isEmpty == false) ? (rulesPayload as Any) : NSNull()
        do {
            let result = try await CallableTransport.post(
                functionName: "updateGameDefinition",
                payload: [
                    "communityId": cid,
                    "gameDefinitionId": gid,
                    "name": trimmedName,
                    "rulesText": rulesValue
                ]
            )
            _ = try CallableTransport.unwrapEnvelope(result)
        } catch {
            throw CallableTransport.mapCallableNetworkError(error)
        }
    }

    func deleteGameDefinition(communityId: String, gameDefinitionId: String) async throws {
        let cid = communityId.trimmingCharacters(in: .whitespacesAndNewlines)
        let gid = gameDefinitionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cid.isEmpty, !gid.isEmpty else { throw CommunityServiceError.invalidResponse }
        do {
            let result = try await CallableTransport.post(
                functionName: "deleteGameDefinition",
                payload: ["communityId": cid, "gameDefinitionId": gid]
            )
            _ = try CallableTransport.unwrapEnvelope(result)
        } catch {
            throw CallableTransport.mapCallableNetworkError(error)
        }
    }

    /// Loads denormalized `displayName` from `memberships` for a league (allowed for fellow members per rules).
    private static func leagueBoardFetchAuthorNamesFromMemberships(
        db: Firestore,
        communityId: String,
        profileIds: [String]
    ) async -> [String: String] {
        let cid = communityId.trimmingCharacters(in: .whitespacesAndNewlines)
        let wanted = Set(profileIds)
        guard !cid.isEmpty, !wanted.isEmpty else { return [:] }
        do {
            let snapshot = try await db.collection("memberships")
                .whereField("communityId", isEqualTo: cid)
                .getDocuments()
            var map: [String: String] = [:]
            for doc in snapshot.documents {
                let data = doc.data()
                guard let profileId = data["profileId"] as? String, wanted.contains(profileId) else { continue }
                if let displayName = data["displayName"] as? String, !displayName.isEmpty {
                    map[profileId] = displayName
                }
            }
            return map
        } catch {
            return [:]
        }
    }
}

final class GameLogService: GameLogServiceProtocol {
    func fetchLogs(communityId: String) async throws {}

    func canCurrentUserEditDelete(createdByProfileId: String) -> Bool {
        Auth.auth().currentUser?.uid == createdByProfileId
    }

    func uploadGamePhoto(
        communityId: String,
        gameLogId: String,
        side: String,
        data: Data,
        contentType: String
    ) async throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(
                domain: "GameLogService",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Sign in again, then try submitting."]
            )
        }
        let filename = "\(side)_\(UUID().uuidString).jpg"
        let path = "gamePhotos/\(communityId)/\(gameLogId)/\(filename)"
        AppDebugLog.log("GameLogService.uploadGamePhoto: start path=\(path) bytes=\(data.count) uidPresent=\(!uid.isEmpty)")
        let ref = Storage.storage().reference().child(path)
        let metadata = StorageMetadata()
        metadata.contentType = contentType
        metadata.cacheControl = "public,max-age=31536000,immutable"
        metadata.customMetadata = ["createdByProfileId": uid]
        _ = try await ref.putDataAsync(data, metadata: metadata)
        AppDebugLog.log("GameLogService.uploadGamePhoto: putDataAsync OK path=\(path)")
        let url = try await ref.downloadURL()
        AppDebugLog.log("GameLogService.uploadGamePhoto: downloadURL OK host=\(url.host ?? "nil")")
        return url.absoluteString
    }

    func createGameLog(payload: GameLogCreatePayload) async throws {
        AppDebugLog.log(
            "GameLogService.createGameLog: start gameLogId=\(payload.gameLogId) communityId=\(payload.communityId) bracketId=\(payload.bracketId ?? "nil") bracketMatchId=\(payload.bracketMatchId ?? "nil") participants=\(payload.participantProfileIds.count) winners=\(payload.winnerProfileIds.count) losers=\(payload.loserProfileIds.count) photos=\(payload.photoUrls.count)"
        )
        let now = Timestamp(date: Date())
        var data: [String: Any] = [
            "id": payload.gameLogId,
            "communityId": payload.communityId,
            "gameType": payload.gameType,
            "createdByProfileId": payload.createdByProfileId,
            "participantProfileIds": payload.participantProfileIds,
            "winnerProfileIds": payload.winnerProfileIds,
            "loserProfileIds": payload.loserProfileIds,
            "mvpProfileId": payload.mvpProfileId ?? NSNull(),
            "lvpProfileId": payload.lvpProfileId ?? NSNull(),
            "photoUrls": payload.photoUrls,
            "notes": payload.notes ?? NSNull(),
            "createdAt": now,
            "updatedAt": now
        ]
        if let bracketId = payload.bracketId {
            data["bracketId"] = bracketId
        }
        if let bracketMatchId = payload.bracketMatchId {
            data["bracketMatchId"] = bracketMatchId
        }
        if let defId = payload.customGameDefinitionId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !defId.isEmpty {
            data["customGameDefinitionId"] = defId
        }
        if let rawName = payload.customGameDefinitionName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawName.isEmpty {
            data["customGameDefinitionName"] = String(rawName.prefix(80))
        }
        if let pongStats = payload.pongStats {
            data["pongStats"] = pongStats
        } else {
            data["pongStats"] = NSNull()
        }
        data["beerBallStats"] = payload.beerBallStats ?? NSNull()
        data["battlePongStats"] = payload.battlePongStats ?? NSNull()
        data["baseballStats"] = payload.baseballStats ?? NSNull()
        data["crossfireStats"] = payload.crossfireStats ?? NSNull()
        try await AppFirestore.db()
            .collection("gameLogs")
            .document(payload.gameLogId)
            .setData(data)
        AppDebugLog.log("GameLogService.createGameLog: setData OK gameLogId=\(payload.gameLogId)")
    }

    func updateGameLog(payload: GameLogUpdatePayload) async throws {
        let now = Timestamp(date: Date())
        var data: [String: Any] = [
            "participantProfileIds": payload.participantProfileIds,
            "winnerProfileIds": payload.winnerProfileIds,
            "loserProfileIds": payload.loserProfileIds,
            "mvpProfileId": payload.mvpProfileId ?? NSNull(),
            "lvpProfileId": payload.lvpProfileId ?? NSNull(),
            "photoUrls": payload.photoUrls,
            "notes": payload.notes ?? NSNull(),
            "pongStats": payload.pongStats ?? NSNull(),
            "updatedAt": now
        ]
        if let beerBallStats = payload.beerBallStats {
            data["beerBallStats"] = beerBallStats
        } else {
            data["beerBallStats"] = NSNull()
        }
        if let battlePongStats = payload.battlePongStats {
            data["battlePongStats"] = battlePongStats
        } else {
            data["battlePongStats"] = NSNull()
        }
        if let baseballStats = payload.baseballStats {
            data["baseballStats"] = baseballStats
        } else {
            data["baseballStats"] = NSNull()
        }
        if let crossfireStats = payload.crossfireStats {
            data["crossfireStats"] = crossfireStats
        } else {
            data["crossfireStats"] = NSNull()
        }
        do {
            try await AppFirestore.db()
                .collection("gameLogs")
                .document(payload.gameLogId)
                .updateData(data)
        } catch {
            throw Self.mapGameLogWriteError(error)
        }
    }

    func fetchGameLogForEditing(gameLogId: String) async throws -> GameLogEditableSnapshot {
        let snap = try await AppFirestore.db().collection("gameLogs").document(gameLogId).getDocument()
        guard let d = snap.data() else {
            throw NSError(
                domain: "GameLogService",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Game log not found."]
            )
        }
        guard let communityId = d["communityId"] as? String,
              let createdByProfileId = d["createdByProfileId"] as? String,
              let gameType = d["gameType"] as? String
        else {
            throw NSError(
                domain: "GameLogService",
                code: 0,
                userInfo: [NSLocalizedDescriptionKey: "This game log is missing required fields."]
            )
        }
        let notesRaw = d["notes"]
        let notesString: String?
        if let s = notesRaw as? String {
            notesString = s
        } else {
            notesString = nil
        }
        let customDefRaw = d["customGameDefinitionId"]
        let customGameDefinitionId: String?
        if let s = customDefRaw as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            customGameDefinitionId = t.isEmpty ? nil : t
        } else {
            customGameDefinitionId = nil
        }
        let customNameRaw = d["customGameDefinitionName"]
        let customGameDefinitionName: String?
        if let s = customNameRaw as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            customGameDefinitionName = t.isEmpty ? nil : t
        } else {
            customGameDefinitionName = nil
        }
        return GameLogEditableSnapshot(
            gameLogId: gameLogId,
            communityId: communityId,
            createdByProfileId: createdByProfileId,
            gameType: gameType,
            customGameDefinitionId: customGameDefinitionId,
            customGameDefinitionName: customGameDefinitionName,
            participantProfileIds: Self.gameLogStringArrayField(d["participantProfileIds"]),
            winnerProfileIds: Self.gameLogStringArrayField(d["winnerProfileIds"]),
            loserProfileIds: Self.gameLogStringArrayField(d["loserProfileIds"]),
            mvpProfileId: d["mvpProfileId"] as? String,
            lvpProfileId: d["lvpProfileId"] as? String,
            photoUrls: d["photoUrls"] as? [String] ?? [],
            notes: notesString,
            pongStats: d["pongStats"] as? [String: Any],
            beerBallStats: d["beerBallStats"] as? [String: Any],
            battlePongStats: d["battlePongStats"] as? [String: Any],
            baseballStats: d["baseballStats"] as? [String: Any],
            crossfireStats: d["crossfireStats"] as? [String: Any]
        )
    }

    func deleteGameLog(gameLogId: String) async throws {
        do {
            try await AppFirestore.db()
                .collection("gameLogs")
                .document(gameLogId)
                .delete()
        } catch {
            throw Self.mapGameLogWriteError(error)
        }
    }

    /// Decodes `participantProfileIds` / `winnerProfileIds` / `loserProfileIds` from Firestore (handles `[Any]` bridging).
    private static func gameLogStringArrayField(_ value: Any?) -> [String] {
        if let direct = value as? [String] { return direct }
        guard let anyArr = value as? [Any] else { return [] }
        return anyArr.compactMap { element in
            if let s = element as? String { return s }
            if let s = element as? NSString { return s as String }
            return nil
        }
    }

    private static func mapGameLogWriteError(_ error: Error) -> Error {
        let ns = error as NSError
        if ns.domain == FirestoreErrorDomain,
           ns.code == FirestoreErrorCode.permissionDenied.rawValue {
            return NSError(
                domain: "GameLogService",
                code: ns.code,
                userInfo: [NSLocalizedDescriptionKey: "Only the creator can edit or delete this log."]
            )
        }
        return error
    }
}
extension GameLogService: FeedServiceProtocol {
    private static let feedPageSize = 50
    private static let whereInChunkSize = 10   // Firestore whereIn hard limit

    /// Loads `communities/{id}.name` for feed labels (parallel reads). Skips leagues the user cannot read.
    private static func fetchCommunityNamesMap(db: Firestore, communityIds: [String]) async -> [String: String] {
        let unique = Array(Set(communityIds))
        guard !unique.isEmpty else { return [:] }
        var map: [String: String] = [:]
        await withTaskGroup(of: (String, String?).self) { group in
            for id in unique {
                group.addTask {
                    let snap = try? await db.collection("communities").document(id).getDocument()
                    let name = snap?.data()?["name"] as? String
                    return (id, name)
                }
            }
            for await (id, name) in group {
                if let name, !name.isEmpty {
                    map[id] = name
                }
            }
        }
        return map
    }

    /// Profile ids needed to resolve names on the feed row (winners, losers, participants, awards, creator, stats).
    private static func profileIdsReferencedInGameLog(data: [String: Any]) -> [String] {
        var ids: [String] = []
        if let w = data["winnerProfileIds"] as? [String] { ids.append(contentsOf: w) }
        if let l = data["loserProfileIds"] as? [String] { ids.append(contentsOf: l) }
        if let m = data["mvpProfileId"] as? String, !m.isEmpty { ids.append(m) }
        if let l = data["lvpProfileId"] as? String, !l.isEmpty { ids.append(l) }
        appendStatsProfileIds(from: data, into: &ids)
        return ids
    }

    private static func appendStatsProfileIds(from data: [String: Any], into ids: inout [String]) {
        if let pong = data["pongStats"] as? [String: Any] {
            if let m = pong["playerCupsHit"] as? [String: Any] { ids.append(contentsOf: m.keys) }
            if let last = pong["lastCupByProfileId"] as? String, !last.isEmpty { ids.append(last) }
        }
        if let bb = data["beerBallStats"] as? [String: Any] {
            if let m = bb["newCanCountByProfileId"] as? [String: Any] { ids.append(contentsOf: m.keys) }
            if let f = bb["firstFinishedByProfileId"] as? String, !f.isEmpty { ids.append(f) }
        }
        if let bp = data["battlePongStats"] as? [String: Any] {
            if let m = bp["playerCupsHit"] as? [String: Any] { ids.append(contentsOf: m.keys) }
        }
        if let b = data["baseballStats"] as? [String: Any] {
            if let m = b["hitsByProfileId"] as? [String: Any] { ids.append(contentsOf: m.keys) }
        }
        if let cf = data["crossfireStats"] as? [String: Any] {
            if let m = cf["playerCupsHit"] as? [String: Any] { ids.append(contentsOf: m.keys) }
            if let last = cf["lastCupByProfileId"] as? String, !last.isEmpty { ids.append(last) }
        }
    }

    private static func stringIntMap(from value: Any?) -> [String: Int] {
        guard let dict = value as? [String: Any] else { return [:] }
        var out: [String: Int] = [:]
        for (k, v) in dict {
            if let i = v as? Int {
                out[k] = i
            } else if let n = v as? NSNumber {
                out[k] = n.intValue
            }
        }
        return out
    }

    private static func formatGameLogStats(
        gameType: String,
        data: [String: Any],
        resolveName: (String) -> String
    ) -> String? {
        switch gameType {
        case "PONG":
            guard let pong = data["pongStats"] as? [String: Any], !pong.isEmpty else { return nil }
            return formatPongStats(pong, resolveName: resolveName)
        case "BEER_BALL":
            guard let bb = data["beerBallStats"] as? [String: Any], !bb.isEmpty else { return nil }
            return formatBeerBallStats(bb, resolveName: resolveName)
        case "BATTLE_PONG":
            guard let bp = data["battlePongStats"] as? [String: Any], !bp.isEmpty else { return nil }
            return formatBattlePongStats(bp, resolveName: resolveName)
        case "BASEBALL":
            guard let b = data["baseballStats"] as? [String: Any], !b.isEmpty else { return nil }
            return formatBaseballStats(b, resolveName: resolveName)
        case "CROSSFIRE":
            guard let cf = data["crossfireStats"] as? [String: Any], !cf.isEmpty else { return nil }
            return formatCrossfireStats(cf, resolveName: resolveName)
        case "CUSTOM":
            return nil
        default:
            return nil
        }
    }

    private static func formatPongStats(_ pong: [String: Any], resolveName: (String) -> String) -> String? {
        var lines: [String] = []
        if let mode = pong["cupMode"] as? Int {
            lines.append("Playing \(mode)-cup pong")
        } else if let n = pong["cupMode"] as? NSNumber {
            lines.append("Playing \(n.intValue)-cup pong")
        }
        let cups = stringIntMap(from: pong["playerCupsHit"])
        if !cups.isEmpty {
            for id in cups.keys.sorted(by: { resolveName($0) < resolveName($1) }) {
                lines.append("\(resolveName(id)) made \(cups[id] ?? 0) shots")
            }
        }
        if let last = pong["lastCupByProfileId"] as? String, !last.isEmpty {
            lines.append("\(resolveName(last)) hit the last cup!")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private static func formatBeerBallStats(_ bb: [String: Any], resolveName: (String) -> String) -> String? {
        var lines: [String] = []
        let cans = stringIntMap(from: bb["newCanCountByProfileId"])
        if !cans.isEmpty {
            for id in cans.keys.sorted(by: { resolveName($0) < resolveName($1) }) {
                lines.append("\(resolveName(id)) had to drink \(cans[id] ?? 0) extra drinks")
            }
        }
        if let first = bb["firstFinishedByProfileId"] as? String, !first.isEmpty {
            lines.append("\(resolveName(first)) finished their drink first!")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private static func formatBattlePongStats(_ bp: [String: Any], resolveName: (String) -> String) -> String? {
        let cups = stringIntMap(from: bp["playerCupsHit"])
        guard !cups.isEmpty else { return nil }
        var lines: [String] = []
        for id in cups.keys.sorted(by: { resolveName($0) < resolveName($1) }) {
            lines.append("\(resolveName(id)) made \(cups[id] ?? 0) shots!")
        }
        return lines.joined(separator: "\n")
    }

    private static func formatBaseballStats(_ b: [String: Any], resolveName: (String) -> String) -> String? {
        let hits = stringIntMap(from: b["hitsByProfileId"])
        guard !hits.isEmpty else { return nil }
        var lines: [String] = []
        for id in hits.keys.sorted(by: { resolveName($0) < resolveName($1) }) {
            lines.append("\(resolveName(id)) had \(hits[id] ?? 0) hits!")
        }
        return lines.joined(separator: "\n")
    }

    private static func formatCrossfireStats(_ cf: [String: Any], resolveName: (String) -> String) -> String? {
        var detailLines: [String] = []
        let cups = stringIntMap(from: cf["playerCupsHit"])
        for id in cups.keys.sorted(by: { resolveName($0) < resolveName($1) }) {
            let n = cups[id] ?? 0
            if n > 0 {
                detailLines.append("\(resolveName(id)) made \(n) cups")
            }
        }
        if let last = cf["lastCupByProfileId"] as? String, !last.isEmpty {
            detailLines.append("\(resolveName(last)) hit the last cup!")
        }
        guard !detailLines.isEmpty else { return nil }
        return (["Crossfire"] + detailLines).joined(separator: "\n")
    }

    /// Maps a `gameLogs` document to `FeedRow` (shared by home feed and community-scoped feed).
    private static func feedRow(
        document: QueryDocumentSnapshot,
        communityNameById: [String: String],
        membershipDisplayNamesByCommunityId: [String: [String: String]],
        profileDisplayNameById: [String: String]
    ) -> FeedRow? {
        let d = document.data()
        guard
            let communityId = d["communityId"] as? String,
            let gameType = d["gameType"] as? String,
            let createdAtTs = d["createdAt"] as? Timestamp
        else { return nil }

        let winnerIds = d["winnerProfileIds"] as? [String] ?? []
        let loserIds = d["loserProfileIds"] as? [String] ?? []
        let participantNames = d["participantDisplayNames"] as? [String: String] ?? [:]
        let membershipNames = membershipDisplayNamesByCommunityId[communityId] ?? [:]
        let mvpProfileId = d["mvpProfileId"] as? String
        let lvpProfileId = d["lvpProfileId"] as? String

        let resolveName: (String) -> String = { id in
            participantNames[id] ?? membershipNames[id] ?? profileDisplayNameById[id] ?? id
        }

        let mvpDisplayName: String? = mvpProfileId.flatMap { id in
            id.isEmpty ? nil : resolveName(id)
        }
        let lvpDisplayName: String? = lvpProfileId.flatMap { id in
            id.isEmpty ? nil : resolveName(id)
        }

        let statsSummary = formatGameLogStats(gameType: gameType, data: d, resolveName: resolveName)

        let notesFromDoc = d["notes"] as? String
        let notesTrimmed = notesFromDoc?.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes: String? = (notesTrimmed?.isEmpty == false) ? notesTrimmed : nil

        let participantIds = d["participantProfileIds"] as? [String] ?? []
        let createdBy = d["createdByProfileId"] as? String ?? ""
        let customDefNameRaw = d["customGameDefinitionName"] as? String
        let customGameDefinitionName: String? = {
            guard let s = customDefNameRaw else { return nil }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }()

        return FeedRow(
            gameLogId: document.documentID,
            communityId: communityId,
            communityName: communityNameById[communityId],
            createdByProfileId: createdBy,
            participantProfileIds: participantIds,
            gameType: gameType,
            customGameDefinitionName: customGameDefinitionName,
            winnerProfileIds: winnerIds,
            loserProfileIds: loserIds,
            winnerNames: winnerIds.compactMap { participantNames[$0] ?? membershipNames[$0] ?? profileDisplayNameById[$0] },
            loserNames: loserIds.compactMap { participantNames[$0] ?? membershipNames[$0] ?? profileDisplayNameById[$0] },
            mvpProfileId: mvpProfileId,
            lvpProfileId: lvpProfileId,
            mvpDisplayName: mvpDisplayName,
            lvpDisplayName: lvpDisplayName,
            statsSummary: statsSummary,
            notes: notes,
            photoUrls: d["photoUrls"] as? [String] ?? [],
            createdAt: createdAtTs.dateValue()
        )
    }

    /// Loads `memberships` display names for each community in feed scope. Returns empty map for communities the user cannot roster-read.
    private static func fetchMembershipDisplayNamesByCommunityId(
        db: Firestore,
        communityIds: [String]
    ) async -> [String: [String: String]] {
        let uniqueCommunityIds = Array(Set(communityIds))
        guard !uniqueCommunityIds.isEmpty else { return [:] }

        var result: [String: [String: String]] = [:]
        await withTaskGroup(of: (String, [String: String]).self) { group in
            for communityId in uniqueCommunityIds {
                group.addTask {
                    do {
                        let snapshot = try await db
                            .collection("memberships")
                            .whereField("communityId", isEqualTo: communityId)
                            .getDocuments()
                        var names: [String: String] = [:]
                        for doc in snapshot.documents {
                            let data = doc.data()
                            guard let profileId = data["profileId"] as? String else { continue }
                            guard let displayName = data["displayName"] as? String, !displayName.isEmpty else { continue }
                            names[profileId] = displayName
                        }
                        return (communityId, names)
                    } catch {
                        return (communityId, [:])
                    }
                }
            }
            for await (communityId, names) in group {
                result[communityId] = names
            }
        }
        return result
    }

    /// Loads `profiles/{id}.displayName` for winner/loser labels in feed rows.
    private static func fetchProfileDisplayNamesMap(db: Firestore, profileIds: [String]) async -> [String: String] {
        let unique = Array(Set(profileIds))
        guard !unique.isEmpty else { return [:] }
        var map: [String: String] = [:]
        await withTaskGroup(of: (String, String?).self) { group in
            for id in unique {
                group.addTask {
                    let snap = try? await db.collection("profiles").document(id).getDocument()
                    let name = snap?.data()?["displayName"] as? String
                    return (id, name)
                }
            }
            for await (id, name) in group {
                if let name, !name.isEmpty {
                    map[id] = name
                }
            }
        }
        return map
    }

    func fetchFeed() async throws -> [FeedRow] {
        let page = try await fetchFeedPage(cursor: nil, pageSize: Self.feedPageSize)
        return page.items
    }

    func fetchFeed(forCommunityId communityId: String) async throws -> [FeedRow] {
        let page = try await fetchFeedPage(forCommunityId: communityId, cursor: nil, pageSize: Self.feedPageSize)
        return page.items
    }

    func fetchFeedPage(
        cursor: HomeFeedPageCursor?,
        pageSize: Int
    ) async throws -> PagedResponse<[FeedRow], HomeFeedPageCursor> {
        guard let userId = Auth.auth().currentUser?.uid else {
            AppDebugLog.log("FeedService.fetchFeedPage: no signed-in user — returning empty")
            return PagedResponse(items: [], nextCursor: nil, hasMore: false)
        }

        let db = AppFirestore.db()
        let membershipDocs = try await db
            .collection("memberships")
            .whereField("profileId", isEqualTo: userId)
            .getDocuments()

        let communityIds: [String] = membershipDocs.documents.compactMap { doc in
            let data = doc.data()
            guard let cid = data["communityId"] as? String else { return nil }
            if (data["leagueHiddenForMember"] as? Bool) == true {
                return nil
            }
            return cid
        }
        guard !communityIds.isEmpty else {
            return PagedResponse(items: [], nextCursor: nil, hasMore: false)
        }

        let communityNameById = await Self.fetchCommunityNamesMap(db: db, communityIds: communityIds)
        let membershipDisplayNamesByCommunityId = await Self.fetchMembershipDisplayNamesByCommunityId(
            db: db,
            communityIds: communityIds
        )
        let chunks = stride(from: 0, to: communityIds.count, by: Self.whereInChunkSize).map {
            Array(communityIds[$0 ..< min($0 + Self.whereInChunkSize, communityIds.count)])
        }

        struct HomeFeedCandidate {
            let row: FeedRow
            let createdAt: Timestamp
            let documentId: String
        }

        var allCandidates: [HomeFeedCandidate] = []
        var allDocuments: [QueryDocumentSnapshot] = []
        var anyChunkHasMore = false
        for chunk in chunks {
            var query: Query = db
                .collection("gameLogs")
                .whereField("communityId", in: chunk)
                .order(by: "createdAt", descending: true)
                .order(by: FieldPath.documentID(), descending: true)
                .limit(to: pageSize)

            if let cursor {
                query = query.start(after: [cursor.createdAt, cursor.documentId])
            }

            let snapshot = try await query.getDocuments()
            allDocuments.append(contentsOf: snapshot.documents)
            if snapshot.documents.count == pageSize {
                anyChunkHasMore = true
            }
        }

        let allProfileIds = allDocuments.flatMap { Self.profileIdsReferencedInGameLog(data: $0.data()) }
        let profileDisplayNameById = await Self.fetchProfileDisplayNamesMap(db: db, profileIds: allProfileIds)

        for document in allDocuments {
            guard let createdAtTs = document.data()["createdAt"] as? Timestamp else { continue }
            guard let row = Self.feedRow(
                document: document,
                communityNameById: communityNameById,
                membershipDisplayNamesByCommunityId: membershipDisplayNamesByCommunityId,
                profileDisplayNameById: profileDisplayNameById
            ) else { continue }
                allCandidates.append(
                    HomeFeedCandidate(
                        row: row,
                        createdAt: createdAtTs,
                        documentId: document.documentID
                    )
                )
        }

        let deduped = Dictionary(grouping: allCandidates, by: \.documentId).compactMap { $0.value.first }
        let sorted = deduped.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.documentId > rhs.documentId
            }
            return lhs.createdAt.dateValue() > rhs.createdAt.dateValue()
        }
        let items = Array(sorted.prefix(pageSize))
        let rows = items.map(\.row)
        let nextCursor = items.last.map {
            HomeFeedPageCursor(createdAt: $0.createdAt, documentId: $0.documentId)
        }
        let canAdvance = nextCursor != nil
        let hasMore = canAdvance && (anyChunkHasMore || sorted.count > pageSize)
        return PagedResponse(items: rows, nextCursor: hasMore ? nextCursor : nil, hasMore: hasMore)
    }

    func fetchFeedPage(
        forCommunityId communityId: String,
        cursor: FeedPageCursor?,
        pageSize: Int
    ) async throws -> PagedResponse<[FeedRow], FeedPageCursor> {
        guard Auth.auth().currentUser != nil else {
            AppDebugLog.log("FeedService.fetchFeedPage(forCommunityId:): no signed-in user — returning empty")
            return PagedResponse(items: [], nextCursor: nil, hasMore: false)
        }

        let db = AppFirestore.db()
        let communityNameById = await Self.fetchCommunityNamesMap(db: db, communityIds: [communityId])
        let membershipDisplayNamesByCommunityId = await Self.fetchMembershipDisplayNamesByCommunityId(
            db: db,
            communityIds: [communityId]
        )

        var query: Query = db
            .collection("gameLogs")
            .whereField("communityId", isEqualTo: communityId)
            .order(by: "createdAt", descending: true)
            .order(by: FieldPath.documentID(), descending: true)
            .limit(to: pageSize)

        if let cursor {
            query = query.start(after: [cursor.createdAt, cursor.documentId])
        }

        let snapshot = try await query.getDocuments()
        let allProfileIds = snapshot.documents.flatMap { Self.profileIdsReferencedInGameLog(data: $0.data()) }
        let profileDisplayNameById = await Self.fetchProfileDisplayNamesMap(db: db, profileIds: allProfileIds)
        let items = snapshot.documents.compactMap { doc in
            Self.feedRow(
                document: doc,
                communityNameById: communityNameById,
                membershipDisplayNamesByCommunityId: membershipDisplayNamesByCommunityId,
                profileDisplayNameById: profileDisplayNameById
            )
        }
        let hasMore = items.count == pageSize
        let nextCursor = snapshot.documents.last.flatMap { lastDoc -> FeedPageCursor? in
            guard let createdAtTs = lastDoc.data()["createdAt"] as? Timestamp else { return nil }
            return FeedPageCursor(createdAt: createdAtTs, documentId: lastDoc.documentID)
        }
        AppDebugLog.log("FeedService.fetchFeedPage(forCommunityId:): communityId=\(communityId) logs=\(items.count)")
        return PagedResponse(items: items, nextCursor: hasMore ? nextCursor : nil, hasMore: hasMore)
    }
}
// MARK: - BracketService

extension CommunityService: BracketServiceProtocol {
    func createBracket(
        communityId: String,
        seedMethod: SeedMethod,
        teamSize: Int,
        gameType: String,
        customGameDefinitionId: String?
    ) async throws -> String {
        do {
            var payload: [String: Any] = [
                "communityId": communityId,
                "seedMethod": seedMethod.rawValue,
                "teamSize": teamSize,
                "gameType": gameType,
            ]
            if let cid = customGameDefinitionId?.trimmingCharacters(in: .whitespacesAndNewlines), !cid.isEmpty {
                payload["customGameDefinitionId"] = cid
            }
            let result = try await CallableTransport.post(
                functionName: "createLeagueBracket",
                payload: payload
            )
            let data = try CallableTransport.unwrapEnvelope(result)
            guard let bracketId = data["bracketId"] as? String else {
                throw BracketServiceError.invalidResponse
            }
            return bracketId
        } catch {
            throw Self.mapBracketError(error)
        }
    }

    private static func mapBracketError(_ error: Error) -> Error {
        let ns = error as NSError
        if ns.domain == "CommunityService" { return error }
        if ns.domain == "BracketService" { return error }
        if ns.code == 401 {
            return BracketServiceError.notAMember
        }
        if ns.domain == NSURLErrorDomain {
            return NSError(
                domain: ns.domain,
                code: ns.code,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Network error. Check your connection and try again.",
                ]
            )
        }
        return error
    }
    func finalizeManualBracket(
        bracketId: String,
        teams: [[String]]
    ) async throws {
        do {
            let result = try await CallableTransport.post(
                functionName: "finalizeManualBracket",
                payload: [
                    "bracketId": bracketId,
                    "teams": teams,
                ]
            )
            _ = try CallableTransport.unwrapEnvelope(result)
        } catch {
            throw Self.mapBracketError(error)
        }
    }
}