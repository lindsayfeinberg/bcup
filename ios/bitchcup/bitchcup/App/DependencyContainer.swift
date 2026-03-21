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
        AppDebugLog.log("UserService.fetchProfile: GET profiles/\(userId)")
        let snapshot = try await Firestore.firestore()
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
        try await Firestore.firestore()
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
        try await Firestore.firestore()
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

final class CommunityService: CommunityServiceProtocol {
    func fetchCommunities() async throws {}
}

final class GameLogService: GameLogServiceProtocol {
    func fetchLogs(communityId: String) async throws {}
}
