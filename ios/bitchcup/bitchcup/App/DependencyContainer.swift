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

// MARK: - Container

class DependencyContainer {
    static let shared = DependencyContainer()
    private init() {}

    // Services wired here when implemented in T05+
    // var authService: AuthServiceProtocol = AuthService()
    // var userService: UserServiceProtocol = UserService()
    // var communityService: CommunityServiceProtocol = CommunityService()
}