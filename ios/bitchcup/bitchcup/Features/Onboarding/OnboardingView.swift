import FirebaseAuth
import PhotosUI
import SwiftUI

/// T05.1–T05.4: Google Sign-In, 21+ gate, profile setup, Firestore persistence → home feed.
struct OnboardingView: View {
    @EnvironmentObject private var sessionManager: AppSessionManager
    @EnvironmentObject private var container: DependencyContainer

    @State private var phase: OnboardingPhase = .signInWithGoogle
    @State private var isBusy = false
    @State private var localError: String?
    @State private var displayName = ""
    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        Group {
            switch phase {
            case .signInWithGoogle:
                signInStep
            case .ageConfirmation:
                OnboardingAgeConfirmationView {
                    Task { await confirmAge() }
                }
            case .profileSetup:
                OnboardingProfileSetupView(
                    displayName: $displayName,
                    selectedPhotoItem: $selectedPhotoItem,
                    isSaving: isBusy,
                    errorMessage: localError ?? sessionManager.errorMessage
                ) {
                    Task { await submitProfile() }
                }
            }
        }
        .task {
            await syncPhaseFromFirestore()
        }
        .onChange(of: sessionManager.currentUserId) { _, _ in
            Task { await syncPhaseFromFirestore() }
        }
    }

    private var signInStep: some View {
        VStack(spacing: 20) {
            Text("Welcome to bcup")
                .font(.title2)
                .fontWeight(.semibold)

            Button {
                Task {
                    AppDebugLog.log("OnboardingView: Continue with Google tapped")
                    await signInWithGoogle()
                }
            } label: {
                HStack {
                    if isBusy {
                        ProgressView()
                            .progressViewStyle(.circular)
                    }
                    Text(isBusy ? "Signing in..." : "Continue with Google")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy)

            if let errorMessage = sessionManager.errorMessage {
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
        isBusy = true
        localError = nil
        AppDebugLog.log("OnboardingView.signInWithGoogle: calling sessionManager")
        await sessionManager.signInWithGoogle()
        AppDebugLog.log("OnboardingView.signInWithGoogle: done")
        isBusy = false
        await syncPhaseFromFirestore()
    }

    /// Align UI step with Firestore profile (T05.2 / T05.3 / T05.4).
    private func syncPhaseFromFirestore() async {
        guard let uid = Auth.auth().currentUser?.uid ?? sessionManager.currentUserId else {
            phase = .signInWithGoogle
            return
        }
        do {
            let profile = try await container.userService.fetchProfile(userId: uid)
            if profile?.onboardingCompleteAt != nil {
                AppDebugLog.log("OnboardingView.syncPhase: onboarding already complete — expecting router home")
                return
            }
            if profile == nil || profile?.ageConfirmed21PlusAt == nil {
                phase = .ageConfirmation
            } else {
                phase = .profileSetup
                if displayName.isEmpty, let name = profile?.displayName, !name.isEmpty {
                    displayName = name
                }
            }
        } catch {
            localError = error.localizedDescription
            AppDebugLog.log("OnboardingView.syncPhase: error \(error.localizedDescription)")
        }
    }

    private func confirmAge() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isBusy = true
        localError = nil
        do {
            try await container.userService.createProfileAfterAgeConfirmation(userId: uid)
            AppDebugLog.log("OnboardingView: age confirmation profile created")
            phase = .profileSetup
        } catch {
            localError = error.localizedDescription
            AppDebugLog.log("OnboardingView.confirmAge: \(error.localizedDescription)")
        }
        isBusy = false
    }

    private func submitProfile() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        isBusy = true
        localError = nil
        do {
            var photoUrl = ""
            if let item = selectedPhotoItem {
                if let data = try await loadPhotoData(from: item) {
                    photoUrl = try await container.userService.uploadProfilePhoto(
                        userId: uid,
                        data: data,
                        contentType: "image/jpeg",
                        fileName: "avatar.jpg"
                    )
                }
            }
            try await container.userService.completeProfileOnboarding(
                userId: uid,
                displayName: name,
                profilePhotoUrl: photoUrl
            )
            await sessionManager.refreshAfterProfileSaved()
        } catch {
            localError = error.localizedDescription
            AppDebugLog.log("OnboardingView.submitProfile: \(error.localizedDescription)")
        }
        isBusy = false
    }

    private func loadPhotoData(from item: PhotosPickerItem) async throws -> Data? {
        // Prefer raw image bytes when the system provides them.
        if let data = try await item.loadTransferable(type: Data.self) {
            return data
        }
        return nil
    }
}
