import SwiftUI

struct GameLogView: View {
    let frontPhotoData: Data?
    let backPhotoData: Data?

    init(frontPhotoData: Data? = nil, backPhotoData: Data? = nil) {
        self.frontPhotoData = frontPhotoData
        self.backPhotoData = backPhotoData
    }

    var body: some View {
        NewGameLogFormView(frontPhotoData: frontPhotoData, backPhotoData: backPhotoData)
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