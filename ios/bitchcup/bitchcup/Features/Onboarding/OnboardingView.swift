import FirebaseAuth
import PhotosUI
import SwiftUI

/// T05.1–T05.4: Google Sign-In, 21+ gate, profile setup, Firestore persistence → home feed. T05.6: `OnboardingAnalytics`.
struct OnboardingView: View {
    @EnvironmentObject private var sessionManager: AppSessionManager
    @EnvironmentObject private var container: DependencyContainer

    @State private var phase: OnboardingPhase = .signInWithGoogle
    @State private var isBusy = false
    @State private var localError: String?
    @State private var displayName = ""
    @State private var selectedPhotoItem: PhotosPickerItem?

    private let signInTitleFont = Font.custom("NeueHaasDisplay-Bold", size: 48)
    private let signInButtonFont = Font.custom("NeueHaasDisplay-Mediu", size: 30)
    private let signInErrorFont = Font.custom("NeueHaasDisplay-Light", size: 13)
    private let brandTextColor = Color(red: 112.0 / 255.0, green: 28.0 / 255.0, blue: 21.0 / 255.0)
    private let surfaceColor = Color(red: 254.0 / 255.0, green: 254.0 / 255.0, blue: 254.0 / 255.0)

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
        .onAppear {
            OnboardingAnalytics.logOnboardingScreen(phase)
        }
        .onChange(of: phase) { _, newPhase in
            OnboardingAnalytics.logOnboardingScreen(newPhase)
        }
        .task {
            await syncPhaseFromFirestore()
        }
        .onChange(of: sessionManager.currentUserId) { _, _ in
            Task { await syncPhaseFromFirestore() }
        }
    }

    private var signInStep: some View {
        ZStack {
            Image("signin_background")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text("Welcome to bcup")
                    .font(signInTitleFont)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                    .padding(.top, 28)

                Spacer()

                if let errorMessage = sessionManager.errorMessage {
                    Text(errorMessage)
                        .font(signInErrorFont)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }

                Button {
                    Task {
                        AppDebugLog.log("OnboardingView: Continue with Google tapped")
                        OnboardingAnalytics.logSignInButtonTapped()
                        await signInWithGoogle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isBusy {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(brandTextColor)
                        }
                        Text(isBusy ? "Signing in..." : "Sign in with Google")
                            .font(signInButtonFont)
                            .foregroundStyle(brandTextColor)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .background(surfaceColor)
                    .clipShape(Capsule())
                }
                .disabled(isBusy)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 20)
        }
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
            localError = FirestoreErrorMapper.userFacingMessage(for: error)
            AppDebugLog.log("OnboardingView.syncPhase: error \(FirestoreErrorMapper.developerDebugLine(for: error))")
        }
    }

    private func confirmAge() async {
        guard let uid = Auth.auth().currentUser?.uid ?? sessionManager.currentUserId ?? UITestRuntime.currentUserIdFallback else { return }
        isBusy = true
        localError = nil
        do {
            try await container.userService.createProfileAfterAgeConfirmation(userId: uid)
            AppDebugLog.log("OnboardingView: age confirmation profile created")
            OnboardingAnalytics.logAgeConfirmed()
            phase = .profileSetup
        } catch {
            localError = FirestoreErrorMapper.userFacingMessageForFirebaseServices(for: error)
            AppDebugLog.log("OnboardingView.confirmAge: \(FirestoreErrorMapper.developerDebugLine(for: error))")
            OnboardingAnalytics.logAgeConfirmFailed()
        }
        isBusy = false
    }

    private func submitProfile() async {
        guard let uid = Auth.auth().currentUser?.uid ?? sessionManager.currentUserId ?? UITestRuntime.currentUserIdFallback else { return }
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
            let photoAdded = selectedPhotoItem != nil
            await sessionManager.refreshAfterProfileSaved()
            OnboardingAnalytics.logProfileSubmitted(photoAdded: photoAdded)
            OnboardingAnalytics.logOnboardingFunnelComplete()
        } catch {
            localError = FirestoreErrorMapper.userFacingMessageForFirebaseServices(for: error)
            AppDebugLog.log("OnboardingView.submitProfile: \(FirestoreErrorMapper.developerDebugLine(for: error))")
            OnboardingAnalytics.logProfileSubmitFailed()
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
