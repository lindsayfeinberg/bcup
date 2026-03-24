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
}

struct ProfileRecord {
    let userId: String
    let displayName: String?
    let profilePhotoUrl: String?
    let overallOdds: Double
    let overallGamesPlayed: Int
    let ageConfirmed21PlusAt: Date?
    let onboardingCompleteAt: Date?
}

protocol UserServiceProtocol {
    func fetchProfile(userId: String) async throws -> ProfileRecord?
    /// Creates `profiles/{uid}` after 21+ confirmation (no `onboardingCompleteAt` yet).
    func createProfileAfterAgeConfirmation(userId: String) async throws
    /// Uploads image to `profilePhotos/{uid}/{fileName}` and returns download URL string.
    func uploadProfilePhoto(userId: String, data: Data, contentType: String, fileName: String) async throws -> String
    /// Sets display name, photo URL, and `onboardingCompleteAt`.
    func completeProfileOnboarding(userId: String, displayName: String, profilePhotoUrl: String) async throws
}
struct CommunityMemberRosterRow: Identifiable {
    let profileId: String
    let displayName: String
    let communityOdds: Double
    let communityGamesPlayed: Int
    var id: String { profileId }
}

protocol CommunityServiceProtocol {
    func fetchCommunities() async throws -> [(communityId: String, name: String)]
    func fetchCommunitiesPage(
        cursor: CommunitiesPageCursor?,
        pageSize: Int
    ) async throws -> PagedResponse<[(communityId: String, name: String)], CommunitiesPageCursor>
    func fetchMembers(communityId: String) async throws -> [CommunityMemberRosterRow]
    func createCommunity(name: String) async throws -> (communityId: String, inviteCode: String, inviteLink: String)
    func joinCommunity(inviteCode: String) async throws -> String
    func previewJoinCommunity(inviteCode: String) async throws -> CommunityJoinPreview
}

protocol GameLogServiceProtocol {
    func fetchLogs(communityId: String) async throws
    func canCurrentUserEditDelete(createdByProfileId: String) -> Bool
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
    let gameType: String
    let winnerProfileIds: [String]
    let loserProfileIds: [String]
    let winnerNames: [String]
    let loserNames: [String]
    let mvpProfileId: String?
    let lvpProfileId: String?
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

// MARK: - Container

@MainActor
final class DependencyContainer: ObservableObject {
    let authService: AuthServiceProtocol
    let userService: UserServiceProtocol
    let communityService: CommunityServiceProtocol
    let gameLogService: GameLogServiceProtocol
    let feedService: FeedServiceProtocol

    init() {
        self.authService = GoogleAuthService()
        self.userService = UserService()
        self.communityService = CommunityService()
        let gls = GameLogService()
        self.gameLogService = gls
        self.feedService = gls
    }

    init(
        authService: AuthServiceProtocol,
        userService: UserServiceProtocol,
        communityService: CommunityServiceProtocol,
        gameLogService: GameLogServiceProtocol,
        feedService: FeedServiceProtocol
    ) {
        self.authService = authService
        self.userService = userService
        self.communityService = communityService
        self.gameLogService = gameLogService
        self.feedService = feedService
    }
}

struct CommunityJoinPreview {
    let communityId: String
    let name: String
    let memberCount: Int
}

struct GameLogCreatePayload {
    let gameLogId: String
    let communityId: String
    let gameType: String
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
}

struct GameLogUpdatePayload {
    let gameLogId: String
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
}

// MARK: - Default Service Implementations

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
        AppDebugLog.log("UserService.fetchProfile: exists onboardingCompleteAt=\(onboardingCompleteAt != nil) age21=\(ageConfirmed21PlusAt != nil)")
        return ProfileRecord(
            userId: userId,
            displayName: displayName,
            profilePhotoUrl: profilePhotoUrl,
            overallOdds: overallOdds,
            overallGamesPlayed: overallGamesPlayed,
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

    func fetchCommunities() async throws -> [(communityId: String, name: String)] {
        var all: [(communityId: String, name: String)] = []
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
    ) async throws -> PagedResponse<[(communityId: String, name: String)], CommunitiesPageCursor> {
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

        var namesByCommunityId: [String: String] = [:]
        try await withThrowingTaskGroup(of: (String, String?).self) { group in
            for communityId in uniqueCommunityIds {
                group.addTask {
                    let communityDoc = try await db.collection("communities").document(communityId).getDocument()
                    let name = communityDoc.data()?["name"] as? String
                    return (communityId, name)
                }
            }
            for try await (communityId, name) in group {
                if let name, !name.isEmpty {
                    namesByCommunityId[communityId] = name
                }
            }
        }

        var communities: [(communityId: String, name: String)] = []
        communities.reserveCapacity(orderedCommunityIds.count)
        var seen = Set<String>()
        for communityId in orderedCommunityIds where seen.insert(communityId).inserted {
            if let name = namesByCommunityId[communityId] {
                communities.append((communityId: communityId, name: name))
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

            let displayNameFromMembership = membershipData["displayName"] as? String
            if let displayNameFromMembership, !displayNameFromMembership.isEmpty {
                members.append(CommunityMemberRosterRow(
                    profileId: profileId,
                    displayName: displayNameFromMembership,
                    communityOdds: communityOdds,
                    communityGamesPlayed: communityGamesPlayed
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
                members.append(CommunityMemberRosterRow(
                    profileId: profileId,
                    displayName: displayName,
                    communityOdds: communityOdds,
                    communityGamesPlayed: communityGamesPlayed
                ))
            } else {
                members.append(CommunityMemberRosterRow(
                    profileId: profileId,
                    displayName: "",
                    communityOdds: communityOdds,
                    communityGamesPlayed: communityGamesPlayed
                ))
            }
        }
        return members
    }

    func createCommunity(name: String) async throws -> (communityId: String, inviteCode: String, inviteLink: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CommunityServiceError.emptyName }
        AppDebugLog.log("createCommunity: calling with name=\(trimmed)")
        do {
            let result = try await Self.postCallable(functionName: "createCommunity", payload: ["name": trimmed])
            let data = try Self.unwrapEnvelope(result)
            guard let communityId = data["communityId"] as? String,
                  let inviteCode = data["inviteCode"] as? String,
                  let inviteLink = data["inviteLink"] as? String
            else {
                throw CommunityServiceError.invalidResponse
            }
            return (communityId, inviteCode, inviteLink)
        } catch {
            throw Self.mapCallableError(error)
        }
    }

    func joinCommunity(inviteCode: String) async throws -> String {
        let trimmed = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { throw CommunityServiceError.emptyInviteCode }
        do {
            let result = try await Self.postCallable(functionName: "joinCommunity", payload: ["inviteCode": trimmed])
            let data = try Self.unwrapEnvelope(result)
            guard let communityId = data["communityId"] as? String else {
                throw CommunityServiceError.invalidResponse
            }
            return communityId
        } catch {
            throw Self.mapCallableError(error)
        }
    }

    func previewJoinCommunity(inviteCode: String) async throws -> CommunityJoinPreview {
        let trimmed = inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { throw CommunityServiceError.emptyInviteCode }
        do {
            let result = try await Self.postCallable(
                functionName: "previewJoinCommunity",
                payload: ["inviteCode": trimmed]
            )
            let data = try Self.unwrapEnvelope(result)
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
            throw Self.mapCallableError(error)
        }
    }

    /// HTTPS callable wire format (same as Firebase iOS `FirebaseFunctions`, without that SPM module).
    private static func postCallable(functionName: String, payload: [String: Any]) async throws -> Any {
        guard let projectID = FirebaseApp.app()?.options.projectID else {
            throw CommunityServiceError.invalidResponse
        }
        guard let user = Auth.auth().currentUser else {
            throw NSError(
                domain: "CommunityService",
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Sign in again, then try joining."]
            )
        }
        let token = try await user.getIDToken()
        let urlString = "https://\(functionName.lowercased())-d7ygproeda-uc.a.run.app"
        AppDebugLog.log("postCallable: got token, sending to \(urlString)")
        guard let url = URL(string: urlString) else {
            throw CommunityServiceError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["data": payload])

        let (data, response) = try await URLSession.shared.data(for: request)
        AppDebugLog.log("postCallable: raw response=\(String(data: data, encoding: .utf8) ?? "nil")")
        guard let http = response as? HTTPURLResponse else {
            throw CommunityServiceError.invalidResponse
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let err = json?["error"] as? [String: Any] {
            throw errorFromCallablePayload(err)
        }
        if !(200 ... 299).contains(http.statusCode) {
            throw CommunityServiceError.invalidResponse
        }
        guard let result = json?["result"] else {
            throw CommunityServiceError.invalidResponse
        }
        return result
    }

    private static func unwrapEnvelope(_ data: Any?) throws -> [String: Any] {
        guard let dict = data as? [String: Any],
              let ok = dict["ok"] as? Bool,
              ok,
              let inner = dict["data"] as? [String: Any]
        else {
            throw CommunityServiceError.invalidResponse
        }
        return inner
    }

    private static func errorFromCallablePayload(_ err: [String: Any]) -> NSError {
        let status = (err["status"] as? String ?? "").uppercased()
        let message = err["message"] as? String ?? "Request failed"
        let domain = "CommunityService"
        switch status {
        case "FAILED_PRECONDITION":
            return NSError(
                domain: domain,
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "This league is full (max 350 members)."]
            )
        case "NOT_FOUND":
            return NSError(
                domain: domain,
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "That invite code is not valid."]
            )
        case "ALREADY_EXISTS":
            return NSError(
                domain: domain,
                code: 409,
                userInfo: [NSLocalizedDescriptionKey: "You are already in this league."]
            )
        case "INVALID_ARGUMENT":
            return NSError(
                domain: domain,
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: "Check the information you entered and try again."]
            )
        case "UNAUTHENTICATED":
            return NSError(
                domain: domain,
                code: 401,
                userInfo: [NSLocalizedDescriptionKey: "Sign in again, then try joining."]
            )
        default:
            return NSError(
                domain: domain,
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }

    private static func mapCallableError(_ error: Error) -> Error {
        let ns = error as NSError
        if ns.domain == "CommunityService" { return error }
        if ns.domain == NSURLErrorDomain {
            return NSError(
                domain: ns.domain,
                code: ns.code,
                userInfo: [NSLocalizedDescriptionKey: "Network error. Check your connection and try again."]
            )
        }
        return error
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
        let ref = Storage.storage().reference().child(path)
        let metadata = StorageMetadata()
        metadata.contentType = contentType
        metadata.cacheControl = "public,max-age=31536000,immutable"
        metadata.customMetadata = ["createdByProfileId": uid]
        _ = try await ref.putDataAsync(data, metadata: metadata)
        let url = try await ref.downloadURL()
        return url.absoluteString
    }

    func createGameLog(payload: GameLogCreatePayload) async throws {
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
        if let pongStats = payload.pongStats {
            data["pongStats"] = pongStats
        } else {
            data["pongStats"] = NSNull()
        }
        if let beerBallStats = payload.beerBallStats {
            data["beerBallStats"] = beerBallStats
        }
        if let battlePongStats = payload.battlePongStats {
            data["battlePongStats"] = battlePongStats
        }
        if let baseballStats = payload.baseballStats {
            data["baseballStats"] = baseballStats
        }
        try await AppFirestore.db()
            .collection("gameLogs")
            .document(payload.gameLogId)
            .setData(data)
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
        do {
            try await AppFirestore.db()
                .collection("gameLogs")
                .document(payload.gameLogId)
                .updateData(data)
        } catch {
            throw Self.mapGameLogWriteError(error)
        }
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

    /// Loads `communities/{id}.name` for feed labels (parallel reads).
    private static func fetchCommunityNamesMap(db: Firestore, communityIds: [String]) async throws -> [String: String] {
        let unique = Array(Set(communityIds))
        guard !unique.isEmpty else { return [:] }
        var map: [String: String] = [:]
        try await withThrowingTaskGroup(of: (String, String?).self) { group in
            for id in unique {
                group.addTask {
                    let snap = try await db.collection("communities").document(id).getDocument()
                    let name = snap.data()?["name"] as? String
                    return (id, name)
                }
            }
            for try await (id, name) in group {
                if let name, !name.isEmpty {
                    map[id] = name
                }
            }
        }
        return map
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

        return FeedRow(
            gameLogId: document.documentID,
            communityId: communityId,
            communityName: communityNameById[communityId],
            gameType: gameType,
            winnerProfileIds: winnerIds,
            loserProfileIds: loserIds,
            winnerNames: winnerIds.compactMap { participantNames[$0] ?? membershipNames[$0] ?? profileDisplayNameById[$0] },
            loserNames: loserIds.compactMap { participantNames[$0] ?? membershipNames[$0] ?? profileDisplayNameById[$0] },
            mvpProfileId: mvpProfileId,
            lvpProfileId: lvpProfileId,
            photoUrls: d["photoUrls"] as? [String] ?? [],
            createdAt: createdAtTs.dateValue()
        )
    }

    /// Loads `memberships` display names for each community in feed scope.
    private static func fetchMembershipDisplayNamesByCommunityId(
        db: Firestore,
        communityIds: [String]
    ) async throws -> [String: [String: String]] {
        let uniqueCommunityIds = Array(Set(communityIds))
        guard !uniqueCommunityIds.isEmpty else { return [:] }

        var result: [String: [String: String]] = [:]
        try await withThrowingTaskGroup(of: (String, [String: String]).self) { group in
            for communityId in uniqueCommunityIds {
                group.addTask {
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
                }
            }
            for try await (communityId, names) in group {
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

        let communityIds: [String] = membershipDocs.documents.compactMap {
            $0.data()["communityId"] as? String
        }
        guard !communityIds.isEmpty else {
            return PagedResponse(items: [], nextCursor: nil, hasMore: false)
        }

        let communityNameById = try await Self.fetchCommunityNamesMap(db: db, communityIds: communityIds)
        let membershipDisplayNamesByCommunityId = try await Self.fetchMembershipDisplayNamesByCommunityId(
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

        let allProfileIds = allDocuments.flatMap { document in
            let data = document.data()
            let winners = data["winnerProfileIds"] as? [String] ?? []
            let losers = data["loserProfileIds"] as? [String] ?? []
            return winners + losers
        }
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
        let communityNameById = try await Self.fetchCommunityNamesMap(db: db, communityIds: [communityId])
        let membershipDisplayNamesByCommunityId = try await Self.fetchMembershipDisplayNamesByCommunityId(
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
        let allProfileIds = snapshot.documents.flatMap { document in
            let data = document.data()
            let winners = data["winnerProfileIds"] as? [String] ?? []
            let losers = data["loserProfileIds"] as? [String] ?? []
            return winners + losers
        }
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