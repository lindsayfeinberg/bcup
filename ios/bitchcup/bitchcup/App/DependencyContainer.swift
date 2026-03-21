import Foundation

// MARK: - Service Protocols

protocol AuthServiceProtocol {
    func signIn() async throws
    func signOut() throws
}

protocol UserServiceProtocol {
    func fetchProfile(userId: String) async throws
}

protocol CommunityServiceProtocol {
    func fetchCommunities() async throws
}

protocol GameLogServiceProtocol {
    func fetchLogs(communityId: String) async throws
}

// MARK: - Container

class DependencyContainer: ObservableObject {
    static let shared = DependencyContainer()
    private init() {}

    // Wired when implemented in T05+
    // var authService: AuthServiceProtocol = AuthService()
    // var userService: UserServiceProtocol = UserService()
    // var communityService: CommunityServiceProtocol = CommunityService()
    // var gameLogService: GameLogServiceProtocol = GameLogService()
}