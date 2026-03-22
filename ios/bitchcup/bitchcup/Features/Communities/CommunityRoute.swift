import Foundation

/// Navigation destinations inside the “Your Communities” flow (create / join → detail).
enum CommunityRoute: Hashable {
    case create
    case join
    case detail(communityId: String)
}
