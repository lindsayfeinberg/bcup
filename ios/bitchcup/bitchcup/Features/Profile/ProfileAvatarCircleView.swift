import SwiftUI

/// Loads the `400x400` Storage variant via `downloadURL()` so the token matches the resized object.
struct ProfileAvatarCircleView: View {
    let originalURL: URL
    let size: CGFloat

    private static let placeholderFill = Color(red: 232.0 / 255.0, green: 162.0 / 255.0, blue: 145.0 / 255.0).opacity(0.35)
    private static let ink = Color.black

    @State private var loadURL: URL?

    var body: some View {
        Group {
            if let loadURL {
                AsyncImage(url: loadURL) { phase in
                    switch phase {
                    case .empty:
                        Circle()
                            .fill(Self.placeholderFill)
                            .frame(width: size, height: size)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        AsyncImage(url: originalURL) { fallbackPhase in
                            switch fallbackPhase {
                            case .success(let fallbackImage):
                                fallbackImage
                                    .resizable()
                                    .scaledToFill()
                            default:
                                avatarFailurePlaceholder
                            }
                        }
                    @unknown default:
                        avatarFailurePlaceholder
                    }
                }
            } else {
                Circle()
                    .fill(Self.placeholderFill)
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: originalURL) {
            await MainActor.run {
                loadURL = originalURL
            }
            let resolved = await ImageVariantURLResolver.shared.resolveURL(
                originalURL: originalURL,
                variant: .avatar
            )
            await MainActor.run {
                loadURL = resolved
            }
        }
    }

    private var avatarFailurePlaceholder: some View {
        ZStack {
            Circle()
                .fill(Self.placeholderFill)
            Image(systemName: "person.fill")
                .foregroundStyle(Self.ink)
        }
    }
}
