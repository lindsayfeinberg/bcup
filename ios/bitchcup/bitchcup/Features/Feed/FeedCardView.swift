import SwiftUI

/// Shared card for home feed and community detail; hide league row on detail where the title already names the league.
struct FeedCardView: View {
    let row: FeedRow
    var showCommunityLabel: Bool = true

    private static let dateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            photoSection

            VStack(alignment: .leading, spacing: 10) {

                HStack(alignment: .firstTextBaseline) {
                    Text(gameTypeDisplay)
                        .font(.headline)
                        .accessibilityLabel("Game type: \(gameTypeDisplay)")
                    Spacer()
                    Text(Self.dateFormatter.localizedString(for: row.createdAt, relativeTo: Date()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Posted \(Self.dateFormatter.localizedString(for: row.createdAt, relativeTo: Date()))")
                }

                Divider()

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "trophy.fill")
                        .foregroundStyle(.yellow)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Winners")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(row.winnersText)
                            .font(.subheadline)
                            .lineLimit(2)
                            .accessibilityLabel("Winners: \(row.winnersText)")
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "figure.walk")
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Losers")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(row.losersText)
                            .font(.subheadline)
                            .lineLimit(2)
                            .accessibilityLabel("Losers: \(row.losersText)")
                    }
                }

                if showCommunityLabel {
                    HStack(spacing: 4) {
                        Image(systemName: "person.3")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(row.communityName ?? row.communityId)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .accessibilityLabel("League: \(row.communityName ?? row.communityId)")
                    }
                }
            }
            .padding(12)
        }
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var photoSection: some View {
        let urls = row.photoUrls.compactMap { URL(string: $0) }
        if !urls.isEmpty {
            GeometryReader { geo in
                let photoWidth = max(geo.size.width, 1)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(Array(urls.enumerated()), id: \.element.absoluteString) { index, url in
                            RetryingPhotoView(
                                originalURL: url,
                                variant: .feedThumb,
                                imageID: "\(row.gameLogId)#\(index)",
                                surface: "feed",
                                width: photoWidth,
                                placeholder: { isLoading in
                                    photoPlaceholder(isLoading: isLoading)
                                }
                            )
                        }
                    }
                }
                .task {
                    await prefetchCardPhotos(urls: urls)
                }
                .frame(height: 500)
                .clipShape(UnevenRoundedRectangle(
                    topLeadingRadius: 14,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 14
                ))
            }
            .frame(height: 500)
        }
    }

    @ViewBuilder
    private func photoPlaceholder(isLoading: Bool) -> some View {
        ZStack {
            Color(.systemGray5)
            if isLoading {
                ProgressView()
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("Photo unavailable")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 500)
        .accessibilityLabel(isLoading ? "Loading photo" : "Photo unavailable")
    }

    private var gameTypeDisplay: String {
        row.gameType
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private func prefetchCardPhotos(urls originalURLs: [URL]) async {
        let limited = Array(originalURLs.prefix(3))
        guard !limited.isEmpty else { return }

        var prefetchTargets: [URL] = []
        for originalURL in limited {
            if ImageDeliveryConfig.isTransformedDeliveryEnabled {
                prefetchTargets.append(ImageVariantURLBuilder.variantURL(from: originalURL, variant: .feedThumb))
            } else {
                prefetchTargets.append(originalURL)
            }
        }
        await ImagePrefetcher.shared.prefetch(urls: prefetchTargets, limit: 3)
    }
}

private struct RetryingPhotoView<Placeholder: View>: View {
    let originalURL: URL
    let variant: ImageVariant
    let imageID: String
    let surface: String
    let width: CGFloat
    @ViewBuilder let placeholder: (Bool) -> Placeholder

    @State private var activeURL: URL
    @State private var reloadID = UUID()
    @State private var retryAttempt = 0
    @State private var exhaustedRetries = false
    @State private var hasSwitchedToOriginal = false
    @State private var firstOutcomeRecorded = false
    @State private var hasObservedFailure = false
    @State private var successRecorded = false
    @State private var startedAt: Date?

    private let maxAutoRetries = 2
    private let retryDelayNanoseconds: UInt64 = 500_000_000

    init(
        originalURL: URL,
        variant: ImageVariant,
        imageID: String,
        surface: String,
        width: CGFloat,
        @ViewBuilder placeholder: @escaping (Bool) -> Placeholder
    ) {
        self.originalURL = originalURL
        self.variant = variant
        self.imageID = imageID
        self.surface = surface
        self.width = width
        self.placeholder = placeholder
        _activeURL = State(initialValue: ImageVariantURLBuilder.variantURL(from: originalURL, variant: variant))
    }

    var body: some View {
        AsyncImage(url: activeURL) { phase in
            switch phase {
            case .empty:
                placeholder(true)
                    .frame(width: width, height: 500)
                    .onAppear {
                        if startedAt == nil {
                            startedAt = Date()
                        }
                    }
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
                    .frame(width: width, height: 500)
                    .accessibilityLabel("Game photo")
                    .onAppear {
                        onImageSuccess()
                    }
            case .failure:
                failureView
                    .frame(width: width, height: 500)
                    .onAppear {
                        onImageFailure()
                    }
            @unknown default:
                failureView
                    .frame(width: width, height: 500)
                    .onAppear {
                        onImageFailure()
                    }
            }
        }
        .id(reloadID)
    }

    @ViewBuilder
    private var failureView: some View {
        if exhaustedRetries {
            Button {
                retryAttempt = 0
                exhaustedRetries = false
                activeURL = originalURL
                hasSwitchedToOriginal = true
                reloadID = UUID()
            } label: {
                placeholder(false)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Photo unavailable. Tap to retry")
        } else {
            placeholder(true)
                .task {
                    await scheduleRetry()
                }
        }
    }

    @MainActor
    private func scheduleRetry() async {
        guard !exhaustedRetries else { return }
        if retryAttempt >= maxAutoRetries {
            exhaustedRetries = true
            Task {
                await ImageLoadTelemetry.shared.recordEvent(
                    .finalFailure,
                    surface: surface,
                    imageID: imageID,
                    attemptCount: retryAttempt + 1,
                    urlHost: activeURL.host
                )
            }
            return
        }

        retryAttempt += 1
        try? await Task.sleep(nanoseconds: retryDelayNanoseconds)
        reloadID = UUID()
    }

    private func onImageFailure() {
        if !hasSwitchedToOriginal && activeURL != originalURL {
            hasSwitchedToOriginal = true
            activeURL = originalURL
            retryAttempt = 0
            reloadID = UUID()
            return
        }

        hasObservedFailure = true
        guard !firstOutcomeRecorded else { return }
        firstOutcomeRecorded = true
        Task {
            await ImageLoadTelemetry.shared.recordEvent(
                .firstLoadFailure,
                surface: surface,
                imageID: imageID,
                attemptCount: retryAttempt + 1,
                urlHost: activeURL.host
            )
        }
    }

    private func onImageSuccess() {
        if !firstOutcomeRecorded {
            firstOutcomeRecorded = true
            Task {
                await ImageLoadTelemetry.shared.recordEvent(
                    .firstLoadSuccess,
                    surface: surface,
                    imageID: imageID,
                    attemptCount: retryAttempt + 1,
                    urlHost: activeURL.host
                )
            }
        } else if hasObservedFailure {
            Task {
                await ImageLoadTelemetry.shared.recordEvent(
                    .retrySuccess,
                    surface: surface,
                    imageID: imageID,
                    attemptCount: retryAttempt + 1,
                    urlHost: activeURL.host
                )
            }
        }

        guard !successRecorded else { return }
        successRecorded = true
        if let startedAt {
            let ms = Int(Date().timeIntervalSince(startedAt) * 1000.0)
            Task {
                await ImageLoadTelemetry.shared.recordTimeToVisible(
                    surface: surface,
                    imageID: imageID,
                    attemptCount: retryAttempt + 1,
                    urlHost: activeURL.host,
                    milliseconds: ms
                )
            }
        }
    }
}
