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

protocol CommunityServiceProtocol {
    func fetchCommunities() async throws
    func createCommunity(name: String) async throws -> (communityId: String, inviteCode: String, inviteLink: String)
    func joinCommunity(inviteCode: String) async throws -> String
}

protocol GameLogServiceProtocol {
    func fetchLogs(communityId: String) async throws
}

// MARK: - Container

@MainActor
final class DependencyContainer: ObservableObject {
    let authService: AuthServiceProtocol
    let userService: UserServiceProtocol
    let communityService: CommunityServiceProtocol
    let gameLogService: GameLogServiceProtocol

    init() {
        self.authService = GoogleAuthService()
        self.userService = UserService()
        self.communityService = CommunityService()
        self.gameLogService = GameLogService()
    }

    init(
        authService: AuthServiceProtocol,
        userService: UserServiceProtocol,
        communityService: CommunityServiceProtocol,
        gameLogService: GameLogServiceProtocol
    ) {
        self.authService = authService
        self.userService = userService
        self.communityService = communityService
        self.gameLogService = gameLogService
    }
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
        AppDebugLog.log("UserService.fetchProfile: exists onboardingCompleteAt=\(onboardingCompleteAt != nil) age21=\(ageConfirmed21PlusAt != nil)")
        return ProfileRecord(
            userId: userId,
            displayName: displayName,
            profilePhotoUrl: profilePhotoUrl,
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
            return "Enter a community name."
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

    func fetchCommunities() async throws {}

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
                userInfo: [NSLocalizedDescriptionKey: "This community is full (max 350 members)."]
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
                userInfo: [NSLocalizedDescriptionKey: "You are already in this community."]
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
}
