import SwiftUI

struct OnboardingAgeConfirmationView: View {
    let onConfirmed: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("Age confirmation")
                .font(.title2)
                .fontWeight(.semibold)

            Text("You must be 21 or older to use bcup. By continuing, you confirm that you are at least 21 years old.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button {
                onConfirmed()
            } label: {
                Text("I am 21 or older")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
