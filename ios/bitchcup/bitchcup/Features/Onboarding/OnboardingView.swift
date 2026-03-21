import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var router: AppRouter
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    private let authService = GoogleAuthService()

    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome to bcup")
                .font(.title2)
                .fontWeight(.semibold)

            Button {
                Task {
                    await signInWithGoogle()
                }
            } label: {
                HStack {
                    if isSigningIn {
                        ProgressView()
                            .progressViewStyle(.circular)
                    }
                    Text(isSigningIn ? "Signing in..." : "Continue with Google")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSigningIn)

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }

    @MainActor
    private func signInWithGoogle() async {
        isSigningIn = true
        errorMessage = nil

        do {
            try await authService.signIn()
            router.route = .home
        } catch {
            errorMessage = error.localizedDescription
        }

        isSigningIn = false
    }
}