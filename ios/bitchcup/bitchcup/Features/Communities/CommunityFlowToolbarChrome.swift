import SwiftUI

/// Shared styling for text toolbar controls in the leagues / create-join flow.
enum CommunityFlowToolbarChrome {
    /// Dark red used for "Home" and "Back" in the full-screen communities flow.
    static let accentRed = Color(red: 41.0 / 255.0, green: 0.0 / 255.0, blue: 3.0 / 255.0)
}

/// Leading toolbar control for pushed league screens (Your Leagues, league detail).
struct CommunityFlowBackToolbarButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            dismiss()
        } label: {
            Text("Back")
                .font(.custom("NeueHaasDisplay-Mediu", size: 16))
                .foregroundStyle(CommunityFlowToolbarChrome.accentRed)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .fixedSize(horizontal: true, vertical: false)
        }
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .accessibilityIdentifier("leagues.toolbar.back")
    }
}
