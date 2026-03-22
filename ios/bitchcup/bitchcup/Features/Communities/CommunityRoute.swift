import Foundation

/// Navigation destinations inside the "Your Communities" flow (create / join → detail).
enum CommunityRoute: Hashable {
    case create
    case join
    case list
    case invite(communityId: String, inviteCode: String, inviteLink: String)
    case detail(communityId: String)
}
