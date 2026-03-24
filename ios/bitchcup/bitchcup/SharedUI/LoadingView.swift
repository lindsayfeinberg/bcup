import SwiftUI

struct LoadingView: View {
    var message: String = "Loading..."

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text(message)
                .foregroundColor(.secondary)
                .font(AppFont.subheadline)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}