import SwiftUI

private enum FeedCardLayout {
    /// Matches `NewGameLogFormView.feedCardPhotoHeight` — max height for a fitted photo (no cropping).
    static let photoMaxHeight: CGFloat = 500
    /// Until the strip width is measured, avoid a zero-width layout pass.
    static let assumedStripWidth: CGFloat = 360
    /// Inner corners for the photo panel (card outer radius is 14).
    static let photoClipCornerRadius: CGFloat = 10
    /// Space between the game-type/time header row and the flippable card.
    static let headerToFlipSpacing: CGFloat = 8
    /// Space between footer sections (winners vs losers).
    static let footerSectionSpacing: CGFloat = 16
    /// Vertical padding around the caption below the photo.
    static let captionVerticalPadding: CGFloat = 4
    static let cardCornerRadius: CGFloat = 14
    /// When the back face exceeds its allotted height, fields are omitted in this order (Stats first, Winners last).
    static let backDetailOverflowDropOrder: [String] = ["Stats", "LVP", "MVP", "Losers", "Winners"]
    /// Placeholder height uses **landscape** 4:3 (`width * 3/4`) so loading/error states match `scaledToFit` feed photos (wide combined shots). A portrait `4:3` box (`width * 4/3`) was much taller than typical images.
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

private struct FeedFlipFrontHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct FeedBackFaceIntrinsicHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Shared card for home feed and community detail; hide league row on detail where the title already names the league.
struct FeedCardView: View {
    let row: FeedRow
    var showCommunityLabel: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    @State private var photoAreaWidth: CGFloat = FeedCardLayout.assumedStripWidth
    @State private var isBackVisible = false
    @State private var flipFrontMeasuredHeight: CGFloat = 0
    /// Fields hidden on the back face when intrinsic content height exceeds the flip area (see `FeedCardLayout.backDetailOverflowDropOrder`).
    @State private var droppedBackFieldTitles: Set<String> = []

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
        .onChange(of: row.gameLogId) { _, _ in
            droppedBackFieldTitles = []
        }
        .onChange(of: flipFrontMeasuredHeight) { old, new in
            if new > old + 0.5 {
                droppedBackFieldTitles = []
            }
        }
    }

    /// Game type (emphasized) • short relative time — above the flippable card, left-aligned.
    private var gameTypeTimeHeaderRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(gameTypeDisplay)
                .font(AppFont.bodyMedium)
                .foregroundStyle(.primary)

            Text("•")
                .font(.custom("NeueHaasDisplay-Roman", size: 15))
                .foregroundStyle(.secondary)

            Text(relativeTimeStringAbbreviated)
                .font(.custom("NeueHaasDisplay-Roman", size: 15))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(gameTypeDisplay), \(relativeTimeStringAbbreviated)")
    }

    /// Thin gray border on each face (photo vs details).
    private var flippableCardChromeBorder: some View {
        RoundedRectangle(cornerRadius: FeedCardLayout.photoClipCornerRadius, style: .continuous)
            .strokeBorder(
                colorScheme == .dark
                    ? Color.white.opacity(0.14)
                    : Color.black.opacity(0.06),
                lineWidth: 0.5
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
        .frame(height: flipFrontMeasuredHeight > 0 ? flipFrontMeasuredHeight : nil)
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
            let details = displayedBackDetailRows.map { "\($0.title): \($0.value)" }.joined(separator: ". ")
            return "\(headerAccessibilitySummary) \(details)"
        }
        return "Game photo. Posted \(relativeTimeString). Tap to show game details."
    }

    private var displayedBackDetailRows: [(title: String, value: String)] {
        row.backDetailRows().filter { !droppedBackFieldTitles.contains($0.title) }
    }

    private func trimBackFaceForOverflowIfNeeded(intrinsicHeight: CGFloat, allottedHeight: CGFloat) {
        guard allottedHeight > 0, intrinsicHeight > 0, intrinsicHeight > allottedHeight + 0.5 else { return }
        let allTitles = Set(row.backDetailRows().map(\.title))
        let visibleTitles = Set(displayedBackDetailRows.map(\.title))
        for title in FeedCardLayout.backDetailOverflowDropOrder where allTitles.contains(title) {
            if droppedBackFieldTitles.contains(title) { continue }
            if visibleTitles.count == 1, visibleTitles.contains(title) { return }
            droppedBackFieldTitles.insert(title)
            return
        }
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
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: FeedFlipFrontHeightKey.self, value: geo.size.height)
            }
        )
        .onPreferenceChange(FeedFlipFrontHeightKey.self) { height in
            if height > 0, abs(height - flipFrontMeasuredHeight) > 0.5 {
                flipFrontMeasuredHeight = height
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
        let slotWidth = max(photoAreaWidth, 1)
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
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: FeedPhotoAreaWidthKey.self, value: geo.size.width)
            }
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
        GeometryReader { outer in
            let allotted = outer.size.height
            VStack(alignment: .leading, spacing: 0) {
                headerTitleAbovePhoto
                cardBackDetailsSection(rows: displayedBackDetailRows)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .background(cardBackgroundColor)
            .background(
                GeometryReader { inner in
                    Color.clear.preference(key: FeedBackFaceIntrinsicHeightKey.self, value: inner.size.height)
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .onPreferenceChange(FeedBackFaceIntrinsicHeightKey.self) { intrinsic in
                guard flipFrontMeasuredHeight > 1 else { return }
                trimBackFaceForOverflowIfNeeded(intrinsicHeight: intrinsic, allottedHeight: allotted)
            }
        }
    }

    /// Winners, Losers, MVP, LVP, Stats (`FeedRow.backDetailRows()`, minus any `droppedBackFieldTitles`).
    private func cardBackDetailsSection(rows: [(title: String, value: String)]) -> some View {
        VStack(alignment: .leading, spacing: FeedCardLayout.footerSectionSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                    Text(item.value)
                        .font(AppFont.bodyMedium)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(item.title): \(item.value)")
            }
        }
        .padding(12)
    }

    /// Game type + league line (shown on the flip back).
    private var headerTitleAbovePhoto: some View {
        Text(headerTitleLine1)
            .font(AppFont.bodyMedium)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
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
                .frame(maxWidth: .infinity, alignment: .leading)
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
        let target: URL
        if ImageDeliveryConfig.isTransformedDeliveryEnabled {
            target = ImageVariantURLBuilder.variantURL(from: originalURL, variant: .feedThumb)
        } else {
            target = originalURL
        }
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
        _activeURL = State(initialValue: ImageVariantURLBuilder.variantURL(from: originalURL, variant: variant))
    }

    var body: some View {
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
                    .scaledToFit()
                    .frame(width: width)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxHeight: maxPhotoHeight)
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
