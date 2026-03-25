import SwiftUI

struct OnboardingAgeConfirmationView: View {
    let onConfirmed: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("Age Confirmation")
                .font(.custom("NeueHaasDisplay-Bold", size: 42))

            Text("Bcup is only available to users aged 21 and older. By continuing, you confirm that you meet this requirement.")
                .font(.custom("NeueHaasDisplay-Roman", size: 25))
                .multilineTextAlignment(.center)
                .foregroundStyle(.black)
                .padding(.horizontal)

            Spacer()

            Button {
                onConfirmed()
            } label: {
                Text("I am 21 or older")
                    .font(.custom("NeueHaasDisplay-Bold", size: 42))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(AgeConfirmationPrimaryTextButtonStyle())
            .padding(.horizontal)

            Spacer()
        }
        .padding(.top, 150)
    }
}

private struct AgeConfirmationPrimaryTextButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 180.0 / 255.0, green: 61.0 / 255.0, blue: 37.0 / 255.0))
            )
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
