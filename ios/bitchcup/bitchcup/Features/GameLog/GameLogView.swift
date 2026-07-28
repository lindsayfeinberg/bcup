import SwiftUI

struct GameLogView: View {
    let frontPhotoData: Data?
    let backPhotoData: Data?
    let preselectedCommunityId: String?

    init(frontPhotoData: Data? = nil, backPhotoData: Data? = nil, preselectedCommunityId: String? = nil) {
        self.frontPhotoData = frontPhotoData
        self.backPhotoData = backPhotoData
        self.preselectedCommunityId = preselectedCommunityId
    }

    var body: some View {
        NewGameLogFormView(
            frontPhotoData: frontPhotoData,
            backPhotoData: backPhotoData,
            preselectedCommunityId: preselectedCommunityId
        )
            .navigationTitle("Log game")
            .navigationBarTitleDisplayMode(.inline)
            .communityFlowNavigationBarChrome()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    CommunityFlowBackToolbarButton()
                }
            }
    }
}