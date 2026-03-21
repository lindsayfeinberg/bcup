import PhotosUI
import SwiftUI

struct OnboardingProfileSetupView: View {
    @Binding var displayName: String
    @Binding var selectedPhotoItem: PhotosPickerItem?
    let isSaving: Bool
    let errorMessage: String?
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Your profile")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Choose a display name. You can add a profile photo now or skip.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("Display name", text: $displayName)
                .textFieldStyle(.roundedBorder)
                .textContentType(.name)

            PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                Label("Choose profile photo (optional)", systemImage: "photo.on.rectangle.angled")
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button {
                onSubmit()
            } label: {
                HStack {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(.circular)
                    }
                    Text(isSaving ? "Saving…" : "Finish")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
    }
}
