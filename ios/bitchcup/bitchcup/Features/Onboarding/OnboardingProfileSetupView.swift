import PhotosUI
import SwiftUI
import UIKit

struct OnboardingProfileSetupView: View {
    @Binding var displayName: String
    @Binding var selectedPhotoItem: PhotosPickerItem?
    let isSaving: Bool
    let errorMessage: String?
    let onSubmit: () -> Void
    @State private var previewUIImage: UIImage?

    private var fieldAccentColor: Color {
        Color(red: 180.0 / 255.0, green: 61.0 / 255.0, blue: 37.0 / 255.0)
    }

    private var fieldPlaceholderColor: Color {
        Color(red: 207.0 / 255.0, green: 106.0 / 255.0, blue: 84.0 / 255.0)
    }

    private var isDisplayNameValid: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var profilePreviewAvatar: some View {
        Group {
            if let previewUIImage {
                Image(uiImage: previewUIImage)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle()
                        .fill(fieldPlaceholderColor.opacity(0.35))
                    Image(systemName: "person.fill")
                        .foregroundStyle(fieldAccentColor)
                }
            }
        }
        .frame(width: 168, height: 168)
        .clipShape(Circle())
        .overlay(Circle().stroke(fieldAccentColor, lineWidth: 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Your profile")
                .font(.custom("NeueHaasDisplay-Bold", size: 42))
                .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                Spacer()
                profilePreviewAvatar
                Spacer()
            }

            Text("Choose a display name and profile. Please choose wisely because you cannot update them later on in this version :/")
                .font(.custom("NeueHaasDisplay-Light", size: 17))
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)

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
                .accessibilityIdentifier("onboarding.profile.displayName")

            PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                HStack {
                    Image(systemName: "photo.on.rectangle.angled")
                    Text("Choose Profile Photo")
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

            if let errorMessage {
                Text(errorMessage)
                    .font(.custom("NeueHaasDisplay-Light", size: 13))
                    .foregroundStyle(fieldAccentColor)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            Button(isSaving ? "Saving..." : "Finish") {
                onSubmit()
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
            .accessibilityIdentifier("onboarding.profile.finish")
        }
        .padding(.horizontal, 20)
        .onChange(of: selectedPhotoItem) { _, newValue in
            Task { await updatePreviewImage(from: newValue) }
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
}
