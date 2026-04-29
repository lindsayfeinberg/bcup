import FirebaseAuth
import PhotosUI
import SwiftUI
import UIKit

/// Post-onboarding: edit display name and profile photo (Firestore `profiles/{uid}`).
struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var container: DependencyContainer
    @EnvironmentObject private var sessionManager: AppSessionManager

    let initialDisplayName: String
    let initialPhotoURL: URL?
    /// Pass non-nil when a new photo was saved so the profile can show it immediately (no network spinner).
    let onSaved: (UIImage?) -> Void

    @State private var displayName: String
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var previewUIImage: UIImage?
    @State private var isSaving = false
    @State private var localError: String?

    private let avatarSize: CGFloat = 168

    private var fieldAccentColor: Color {
        Color(red: 180.0 / 255.0, green: 61.0 / 255.0, blue: 37.0 / 255.0)
    }

    private var fieldPlaceholderColor: Color {
        Color(red: 207.0 / 255.0, green: 106.0 / 255.0, blue: 84.0 / 255.0)
    }

    private var isDisplayNameValid: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(
        initialDisplayName: String,
        initialPhotoURL: URL?,
        onSaved: @escaping (UIImage?) -> Void = { _ in }
    ) {
        self.initialDisplayName = initialDisplayName
        self.initialPhotoURL = initialPhotoURL
        self.onSaved = onSaved
        _displayName = State(initialValue: initialDisplayName)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        Spacer()
                        editAvatar
                        Spacer()
                    }

                    TextField(
                        "",
                        text: $displayName,
                        prompt: Text("Display name").foregroundStyle(fieldPlaceholderColor)
                    )
                    .font(.custom("NeueHaasDisplay-Roman", size: 24))
                    .foregroundStyle(fieldAccentColor)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, minHeight: 56, maxHeight: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(fieldAccentColor, lineWidth: 2)
                    )
                    .tint(fieldAccentColor)
                    .textContentType(.name)

                    PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                        HStack {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text("Choose profile photo")
                        }
                        .font(.custom("NeueHaasDisplay-Mediu", size: 24))
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .foregroundStyle(fieldAccentColor)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(fieldAccentColor, lineWidth: 2)
                        )
                    }
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)

                    if let localError {
                        Text(localError)
                            .font(.custom("NeueHaasDisplay-Light", size: 13))
                            .foregroundStyle(fieldAccentColor)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }

                    Button(isSaving ? "Saving..." : "Save") {
                        Task { await save() }
                    }
                    .font(.custom("NeueHaasDisplay-Bold", size: 30))
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .foregroundStyle(
                        isDisplayNameValid
                            ? .white
                            : fieldPlaceholderColor
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(fieldAccentColor)
                    )
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
                    .disabled(isSaving || !isDisplayNameValid)
                    .opacity(isSaving ? 0.65 : 1.0)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Color.white)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .communityFlowNavigationBarChrome()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    CommunityFlowAccentToolbarButton(title: "Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onChange(of: selectedPhotoItem) { _, newValue in
            Task { await updatePreviewImage(from: newValue) }
        }
    }

    @ViewBuilder
    private var editAvatar: some View {
        if let previewUIImage {
            Image(uiImage: previewUIImage)
                .resizable()
                .scaledToFill()
                .frame(width: avatarSize, height: avatarSize)
                .clipShape(Circle())
                .overlay(Circle().stroke(fieldAccentColor, lineWidth: 1))
        } else if let initialPhotoURL {
            ProfileAvatarCircleView(originalURL: initialPhotoURL, size: avatarSize)
                .overlay(Circle().stroke(fieldAccentColor, lineWidth: 1))
        } else {
            ZStack {
                Circle()
                    .fill(fieldPlaceholderColor.opacity(0.35))
                Image(systemName: "person.fill")
                    .foregroundStyle(fieldAccentColor)
            }
            .frame(width: avatarSize, height: avatarSize)
            .overlay(Circle().stroke(fieldAccentColor, lineWidth: 1))
        }
    }

    @MainActor
    private func updatePreviewImage(from item: PhotosPickerItem?) async {
        guard let item else {
            previewUIImage = nil
            return
        }
        if let data = try? await item.loadTransferable(type: Data.self),
           let uiImage = UIImage(data: data) {
            previewUIImage = uiImage
        } else {
            previewUIImage = nil
        }
    }

    @MainActor
    private func save() async {
        guard let uid = container.authService.currentUserId ?? Auth.auth().currentUser?.uid else {
            localError = "Sign in again, then try saving."
            return
        }
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            localError = "Enter a display name."
            return
        }

        isSaving = true
        localError = nil
        defer { isSaving = false }

        var photoUrlString = initialPhotoURL?.absoluteString ?? ""

        if let item = selectedPhotoItem {
            do {
                if let data = try await loadPhotoData(from: item) {
                    let url = try await container.userService.uploadProfilePhoto(
                        userId: uid,
                        data: data,
                        contentType: "image/jpeg",
                        fileName: "avatar.jpg"
                    )
                    photoUrlString = url
                }
            } catch {
                localError = FirestoreErrorMapper.userFacingMessageForFirebaseServices(for: error)
                AppDebugLog.log("EditProfileView.save upload: \(FirestoreErrorMapper.developerDebugLine(for: error))")
                return
            }
        }

        do {
            try await container.userService.updateProfile(
                userId: uid,
                displayName: trimmed,
                profilePhotoUrl: photoUrlString
            )
            await sessionManager.refreshAfterProfileSaved()
            let uploadedNewPhoto = selectedPhotoItem != nil
            onSaved(uploadedNewPhoto ? previewUIImage : nil)
            dismiss()
        } catch {
            localError = FirestoreErrorMapper.userFacingMessageForFirebaseServices(for: error)
            AppDebugLog.log("EditProfileView.save: \(FirestoreErrorMapper.developerDebugLine(for: error))")
        }
    }

    private func loadPhotoData(from item: PhotosPickerItem) async throws -> Data? {
        if let data = try await item.loadTransferable(type: Data.self) {
            return data
        }
        return nil
    }
}
