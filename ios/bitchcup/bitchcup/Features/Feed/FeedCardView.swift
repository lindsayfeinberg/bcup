import SwiftUI

private enum FeedCardLayout {
    /// Matches `NewGameLogFormView.feedCardPhotoHeight` — max height for the feed photo slot (crop-to-fill uses this cap).
    static let photoMaxHeight: CGFloat = 500
    /// Until the strip width is measured, avoid a zero-width layout pass.
    static let assumedStripWidth: CGFloat = 360
    /// Inner corners for the photo panel (card outer radius is 14).
    static let photoClipCornerRadius: CGFloat = 10
    /// Space between the game-type/time header row and the flippable card.
    static let headerToFlipSpacing: CGFloat = 8
    /// Space between footer sections (winners vs losers).
    static let footerSectionSpacing: CGFloat = 16
    /// Extra space between lines in the multi-line Stats block on the card back.
    static let statsSummaryLineSpacing: CGFloat = 7
    /// Caption sits in a fixed-height strip under the flip card; text scales down to fit.
    static let captionMaxHeight: CGFloat = 88
    /// Vertical padding around the caption below the photo.
    static let captionVerticalPadding: CGFloat = 4
    static let cardCornerRadius: CGFloat = 14
    /// Protect against long league names / payloads pushing content outside the card.
    static let backHeaderLineLimit = 2
    /// Slightly below `AppFont.bodyMedium` (17) — back-of-card title line.
    static let backHeaderTitleFont = Font.custom("NeueHaasDisplay-Mediu", size: 16)
    /// Photo slot height uses **landscape** 4:3 (`width * 3/4`) capped by `photoMaxHeight` so loading, error, and loaded (crop-to-fill) states share the same frame.
    static func feedPhotoPlaceholderHeight(width: CGFloat, maxHeight: CGFloat) -> CGFloat {
        min(maxHeight, width * 3 / 4)
    }
}

private struct FeedPhotoAreaWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Shared card for home feed and community detail; hide league row on detail where the title already names the league.
struct FeedCardView: View {
    let row: FeedRow
    var showCommunityLabel: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    @State private var photoAreaWidth: CGFloat = FeedCardLayout.assumedStripWidth
    @State private var isBackVisible = false

    private static let dateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    /// Short relative time (e.g. “1d”) for the header row next to game type.
    private static let abbreviatedRelativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    /// Same height as the photo slot (front face); flip container does not grow with back-face text.
    private var fixedFlipCardHeight: CGFloat {
        FeedCardLayout.feedPhotoPlaceholderHeight(width: max(photoAreaWidth, 1), maxHeight: FeedCardLayout.photoMaxHeight)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: FeedCardLayout.cardCornerRadius, style: .continuous)

        VStack(alignment: .leading, spacing: 0) {
            gameTypeTimeHeaderRow
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, FeedCardLayout.headerToFlipSpacing)

            flippableGameCard

            captionBelowPhotoIfPresent
        }
        .background {
            shape.fill(cardBackgroundColor)
        }
        // No clipShape on the whole card: 3D flip needs to extend past the rounded rect during rotation.
        .accessibilityElement(children: .contain)
    }

    /// Game type (emphasized) • short relative time — above the flippable card, left-aligned.
    private var gameTypeTimeHeaderRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(gameTypeDisplay)
                .font(.custom("NeueHaasDisplay-Mediu", size: 22))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .multilineTextAlignment(.leading)

            Text("•")
                .font(.custom("NeueHaasDisplay-Roman", size: 15))
                .foregroundStyle(.secondary)
                .layoutPriority(1)

            Text(relativeTimeStringAbbreviated)
                .font(.custom("NeueHaasDisplay-Roman", size: 15))
                .foregroundStyle(.secondary)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(gameTypeDisplay), \(relativeTimeStringAbbreviated)")
    }

    /// Gray border on each face (photo vs details); 2pt thicker than the previous hairline.
    private var flippableCardChromeBorder: some View {
        RoundedRectangle(cornerRadius: FeedCardLayout.photoClipCornerRadius, style: .continuous)
            .strokeBorder(
                colorScheme == .dark
                    ? Color.white.opacity(0.14)
                    : Color.black.opacity(0.06),
                lineWidth: 2.5
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
    }

    /// Photo (front) vs game details (back). Caption stays outside this subtree.
    private var flippableGameCard: some View {
        ZStack {
            cardFrontFace
                .overlay { flippableCardChromeBorder }
                .offset(y: isBackVisible ? -20 : 0)
                .opacity(isBackVisible ? 0 : 1)
                .allowsHitTesting(!isBackVisible)

            cardBackFace
                .overlay { flippableCardChromeBorder }
                .offset(y: isBackVisible ? 0 : 20)
                .opacity(isBackVisible ? 1 : 0)
                .allowsHitTesting(isBackVisible)
        }
        .frame(height: fixedFlipCardHeight)
        .clipShape(RoundedRectangle(cornerRadius: FeedCardLayout.photoClipCornerRadius, style: .continuous))
        .animation(.spring(response: 0.38, dampingFraction: 0.72), value: isBackVisible)
        .contentShape(Rectangle())
        .onTapGesture {
            isBackVisible.toggle()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(flipAccessibilityLabel)
        .accessibilityHint(isBackVisible ? "Tap to return to the photo." : "Tap to show winners, losers, and league.")
        .accessibilityAddTraits(.isButton)
    }

    private var flipAccessibilityLabel: String {
        if isBackVisible {
            let details = row.backDetailRows().map { "\($0.title): \($0.value)" }.joined(separator: ". ")
            return "\(headerAccessibilitySummary) \(details)"
        }
        return "Game photo. Posted \(relativeTimeString). Tap to show game details."
    }

    @ViewBuilder
    private var cardFrontFace: some View {
        let urls = row.photoUrls.compactMap { URL(string: $0) }
        Group {
            if let photoURL = urls.first {
                photoSectionWithURL(photoURL)
            } else {
                noPhotoFrontPlaceholder
            }
        }
    }

    private var noPhotoFrontPlaceholder: some View {
        ZStack {
            Color(.systemGray5)
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: FeedCardLayout.feedPhotoPlaceholderHeight(width: max(photoAreaWidth, 1), maxHeight: FeedCardLayout.photoMaxHeight))
        .clipShape(RoundedRectangle(cornerRadius: FeedCardLayout.photoClipCornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func photoSectionWithURL(_ photoURL: URL) -> some View {
        GeometryReader { geo in
            let slotWidth = max(geo.size.width, 1)
            RetryingPhotoView(
                originalURL: photoURL,
                variant: .feedThumb,
                imageID: row.gameLogId,
                surface: "feed",
                width: slotWidth,
                maxPhotoHeight: FeedCardLayout.photoMaxHeight,
                placeholder: { isLoading in
                    photoPlaceholder(
                        isLoading: isLoading,
                        width: slotWidth,
                        maxHeight: FeedCardLayout.photoMaxHeight
                    )
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Color.clear.preference(key: FeedPhotoAreaWidthKey.self, value: geo.size.width)
            )
        }
        .frame(
            maxWidth: .infinity,
            minHeight: FeedCardLayout.feedPhotoPlaceholderHeight(width: max(photoAreaWidth, 1), maxHeight: FeedCardLayout.photoMaxHeight),
            maxHeight: FeedCardLayout.feedPhotoPlaceholderHeight(width: max(photoAreaWidth, 1), maxHeight: FeedCardLayout.photoMaxHeight)
        )
        .onPreferenceChange(FeedPhotoAreaWidthKey.self) { w in
            if w > 0, abs(w - photoAreaWidth) > 0.5 {
                photoAreaWidth = w
            }
        }
        .task {
            await prefetchCardPhoto(url: photoURL)
        }
        .clipShape(RoundedRectangle(cornerRadius: FeedCardLayout.photoClipCornerRadius, style: .continuous))
    }

    private var cardBackFace: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerTitleAbovePhoto
            ViewThatFits(in: .vertical) {
                cardBackDetailsSection(rows: row.backDetailRows(), detailValueSize: 15)
                cardBackDetailsSection(rows: row.backDetailRows(), detailValueSize: 13)
                cardBackDetailsSection(rows: row.backDetailRows(), detailValueSize: 11)
                cardBackDetailsSection(rows: row.backDetailRows(), detailValueSize: 9)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cardBackgroundColor)
    }

    /// Winners, Losers, MVP, LVP, Stats (`FeedRow.backDetailRows()`).
    private func cardBackDetailsSection(rows: [(title: String, value: String)], detailValueSize: CGFloat) -> some View {
        let detailFont = Font.custom("NeueHaasDisplay-Mediu", size: detailValueSize)
        let mvpItem = rows.first { $0.title == "MVP" }
        let lvpItem = rows.first { $0.title == "LVP" }
        let otherRows = rows.filter { $0.title != "MVP" && $0.title != "LVP" }
        return VStack(alignment: .leading, spacing: FeedCardLayout.footerSectionSpacing) {
            ForEach(Array(otherRows.enumerated()), id: \.offset) { _, item in
                let isStats = item.title == "Stats"
                VStack(alignment: .leading, spacing: isStats ? 8 : 4) {
                    Text(item.title)
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                    Text(item.value)
                        .font(detailFont)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(isStats ? FeedCardLayout.statsSummaryLineSpacing : 0)
                        .lineLimit(isStats ? 14 : 5)
                        .minimumScaleFactor(0.72)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(item.title): \(item.value)")
            }

            if let mvpItem, let lvpItem {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("MVP")
                            .font(AppFont.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("LVP")
                            .font(AppFont.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    HStack(alignment: .top, spacing: 12) {
                        Text(mvpItem.value)
                            .font(detailFont)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(4)
                            .minimumScaleFactor(0.72)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(lvpItem.value)
                            .font(detailFont)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(4)
                            .minimumScaleFactor(0.72)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("MVP: \(mvpItem.value). LVP: \(lvpItem.value)")
            } else if let mvpItem {
                backDetailCell(title: mvpItem.title, value: mvpItem.value, detailFont: detailFont)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(mvpItem.title): \(mvpItem.value)")
            } else if let lvpItem {
                backDetailCell(title: lvpItem.title, value: lvpItem.value, detailFont: detailFont)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(lvpItem.title): \(lvpItem.value)")
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private func backDetailCell(title: String, value: String, detailFont: Font) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppFont.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(detailFont)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(5)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Game type + league line (shown on the flip back).
    private var headerTitleAbovePhoto: some View {
        Text(headerTitleLine1)
            .font(FeedCardLayout.backHeaderTitleFont)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .lineLimit(FeedCardLayout.backHeaderLineLimit)
            .minimumScaleFactor(0.72)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(headerAccessibilitySummary)
            .padding(.horizontal, 12)
            .padding(.top, 12)
    }

    private var feedCaptionFromNotes: String {
        let t = row.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t
    }

    @ViewBuilder
    private var captionBelowPhotoIfPresent: some View {
        let text = feedCaptionFromNotes
        if !text.isEmpty {
            Text(text)
                .font(AppFont.body)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(5)
                .minimumScaleFactor(0.55)
                .frame(maxWidth: .infinity, maxHeight: FeedCardLayout.captionMaxHeight, alignment: .topLeading)
                .accessibilityLabel("Caption")
                .padding(.horizontal, 12)
                .padding(.top, FeedCardLayout.captionVerticalPadding)
                .padding(.bottom, FeedCardLayout.captionVerticalPadding)
        }
    }

    private var relativeTimeStringAbbreviated: String {
        Self.abbreviatedRelativeFormatter.localizedString(for: row.createdAt, relativeTo: Date())
    }

    private var headerTitleLine1: String {
        if showCommunityLabel {
            let league = row.communityName ?? row.communityId
            return "\(gameTypeDisplay) game logged in \(league)"
        }
        return "\(gameTypeDisplay) game logged"
    }

    private var headerAccessibilitySummary: String {
        let time = relativeTimeString
        if showCommunityLabel {
            let league = row.communityName ?? row.communityId
            return "Game type: \(gameTypeDisplay). League: \(league). Posted \(time)."
        }
        return "Game type: \(gameTypeDisplay). Posted \(time)."
    }

    private var relativeTimeString: String {
        Self.dateFormatter.localizedString(for: row.createdAt, relativeTo: Date())
    }

    private var cardBackgroundColor: Color {
        colorScheme == .dark
            ? Color(.secondarySystemGroupedBackground)
            : Color(.systemBackground)
    }

    @ViewBuilder
    private func photoPlaceholder(isLoading: Bool, width: CGFloat, maxHeight: CGFloat) -> some View {
        let provisionalHeight = FeedCardLayout.feedPhotoPlaceholderHeight(width: width, maxHeight: maxHeight)
        ZStack {
            Color(.systemGray5)
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("Photo unavailable")
                        .font(AppFont.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(width: width, height: provisionalHeight)
        .accessibilityLabel(isLoading ? "Loading photo" : "Photo unavailable")
    }

    private var gameTypeDisplay: String {
        row.gameType
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    private func prefetchCardPhoto(url originalURL: URL) async {
        let target = await ImageVariantURLResolver.shared.resolveURL(originalURL: originalURL, variant: .feedThumb)
        await ImagePrefetcher.shared.prefetch(urls: [target], limit: 1)
    }
}

private struct RetryingPhotoView<Placeholder: View>: View {
    let originalURL: URL
    let variant: ImageVariant
    let imageID: String
    let surface: String
    let width: CGFloat
    let maxPhotoHeight: CGFloat
    @ViewBuilder let placeholder: (Bool) -> Placeholder

    @State private var activeURL: URL?
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

    /// Same as `FeedCardLayout.feedPhotoPlaceholderHeight` — fixed slot for crop-to-fill so there are no side letterbox gaps.
    private var photoSlotHeight: CGFloat {
        min(maxPhotoHeight, width * 3 / 4)
    }

    init(
        originalURL: URL,
        variant: ImageVariant,
        imageID: String,
        surface: String,
        width: CGFloat,
        maxPhotoHeight: CGFloat,
        @ViewBuilder placeholder: @escaping (Bool) -> Placeholder
    ) {
        self.originalURL = originalURL
        self.variant = variant
        self.imageID = imageID
        self.surface = surface
        self.width = width
        self.maxPhotoHeight = maxPhotoHeight
        self.placeholder = placeholder
        _activeURL = State(initialValue: nil)
    }

    private var resolutionTaskId: String {
        "\(originalURL.absoluteString)|\(variant.rawValue)|\(imageID)"
    }

    var body: some View {
        Group {
            if let activeURL {
                AsyncImage(url: activeURL) { phase in
                    switch phase {
                    case .empty:
                        placeholder(true)
                            .onAppear {
                                if startedAt == nil {
                                    startedAt = Date()
                                }
                            }
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: width, height: photoSlotHeight)
                            .clipped()
                            .accessibilityLabel("Game photo")
                            .onAppear {
                                onImageSuccess()
                            }
                    case .failure:
                        failureView
                            .frame(maxHeight: maxPhotoHeight)
                            .onAppear {
                                onImageFailure()
                            }
                    @unknown default:
                        failureView
                            .frame(maxHeight: maxPhotoHeight)
                            .onAppear {
                                onImageFailure()
                            }
                    }
                }
                .frame(width: width)
                .id(reloadID)
            } else {
                placeholder(true)
                    .frame(width: width)
            }
        }
        .task(id: resolutionTaskId) {
            await MainActor.run {
                if startedAt == nil {
                    startedAt = Date()
                }
            }
            let url = await ImageVariantURLResolver.shared.resolveURL(originalURL: originalURL, variant: variant)
            await MainActor.run {
                activeURL = url
                reloadID = UUID()
            }
        }
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
            .contentShape(Rectangle())
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
                    urlHost: activeURL?.host
                )
            }
            return
        }

        retryAttempt += 1
        try? await Task.sleep(nanoseconds: retryDelayNanoseconds)
        reloadID = UUID()
    }

    private func onImageFailure() {
        if !hasSwitchedToOriginal, let u = activeURL, u != originalURL {
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
                urlHost: activeURL?.host
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
                    urlHost: activeURL?.host
                )
            }
        } else if hasObservedFailure {
            Task {
                await ImageLoadTelemetry.shared.recordEvent(
                    .retrySuccess,
                    surface: surface,
                    imageID: imageID,
                    attemptCount: retryAttempt + 1,
                    urlHost: activeURL?.host
                )
            }
        }

        guard !successRecorded else { return }
        successRecorded = true
        #if DEBUG
        if surface == "feed", variant == .feedThumb, let loadedURL = activeURL {
            let path = loadedURL.path.removingPercentEncoding ?? loadedURL.path
            let file = (path as NSString).lastPathComponent
            let expectedTransformed =
                ImageDeliveryConfig.isTransformedDeliveryEnabled
                && ImageVariantURLBuilder.transformedObjectPath(from: originalURL, variant: .feedThumb) != nil
            AppDebugLog.log(
                "feed_photo_delivery transformedFlag=\(ImageDeliveryConfig.isTransformedDeliveryEnabled) expectedVariantPath=\(expectedTransformed) loadedFile=\(file) is800x800Suffix=\(file.contains("_800x800")) usingOriginalURL=\(loadedURL == originalURL)"
            )
        }
        #endif
        if let startedAt {
            let ms = Int(Date().timeIntervalSince(startedAt) * 1000.0)
            Task {
                await ImageLoadTelemetry.shared.recordTimeToVisible(
                    surface: surface,
                    imageID: imageID,
                    attemptCount: retryAttempt + 1,
                    urlHost: activeURL?.host,
                    milliseconds: ms
                )
            }
        }
    }
}
