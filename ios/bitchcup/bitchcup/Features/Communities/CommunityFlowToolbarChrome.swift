import SwiftUI

/// Shared styling for text toolbar controls in the leagues / create-join flow.
enum CommunityFlowToolbarChrome {
    /// Dark red used for "Home" and "Back" in the full-screen communities flow.
    static let accentRed = Color(red: 41.0 / 255.0, green: 0.0 / 255.0, blue: 3.0 / 255.0)
}

@ViewBuilder
private func communityFlowToolbarLabelStyle(_ title: String) -> some View {
    Text(title)
        .font(.custom("NeueHaasDisplay-Mediu", size: 16))
        .foregroundStyle(CommunityFlowToolbarChrome.accentRed)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .fixedSize(horizontal: true, vertical: false)
}

/// Accent-styled toolbar text (Cancel, etc.) matching `CommunityFlowBackToolbarButton` typography.
struct CommunityFlowAccentToolbarButton: View {
    let title: String
    let action: () -> Void
    var disabled: Bool = false

    var body: some View {
        Button(action: action) {
            communityFlowToolbarLabelStyle(title)
        }
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

/// Leading toolbar control for pushed league screens (Your Leagues, league detail).
struct CommunityFlowBackToolbarButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            dismiss()
        } label: {
            communityFlowToolbarLabelStyle("Back")
        }
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .accessibilityIdentifier("leagues.toolbar.back")
    }
}

/// Same typography as `CommunityFlowBackToolbarButton`, for sheet dismissals (“Close”).
struct CommunityFlowCloseToolbarButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            communityFlowToolbarLabelStyle("Close")
        }
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .accessibilityIdentifier("leagues.toolbar.close")
    }
}

private struct CommunityFlowNavigationBarChromeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbarBackground(Color.white, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

extension View {
    /// Hides the system chevron and applies the white nav bar used across the leagues flow.
    func communityFlowNavigationBarChrome() -> some View {
        modifier(CommunityFlowNavigationBarChromeModifier())
    }
}
