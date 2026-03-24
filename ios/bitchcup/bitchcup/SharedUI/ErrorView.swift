import SwiftUI

struct ErrorView: View {
    var message: String = "Something went wrong."
    var retryAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.red)
            Text("Error")
                .font(AppFont.headline)
            Text(message)
                .font(AppFont.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            if let retryAction {
                Button(action: retryAction) {
                    Text("Retry")
                        .font(AppFont.buttonProminent)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}