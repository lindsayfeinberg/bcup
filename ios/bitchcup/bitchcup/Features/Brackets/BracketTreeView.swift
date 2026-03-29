import SwiftUI
import FirebaseAuth

// MARK: - Match id suffix `_r{n}_m{i}`

private enum BracketMatchIdParse {
    static func roundAndMatchIndex(_ matchId: String) -> (round: Int, index: Int)? {
        guard let regex = try? NSRegularExpression(pattern: "_r(\\d+)_m(\\d+)$") else { return nil }
        let ns = matchId as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let result = regex.firstMatch(in: matchId, range: full),
              result.numberOfRanges == 3,
              let rRange = Range(result.range(at: 1), in: matchId),
              let mRange = Range(result.range(at: 2), in: matchId),
              let r = Int(matchId[rRange]),
              let m = Int(matchId[mRange])
        else { return nil }
        return (r, m)
    }
}

// MARK: - Layout

private final class BracketLayoutCache {
    let matchById: [String: BracketMatchSnapshot]
    let rowStride: CGFloat
    private var yCache: [String: CGFloat] = [:]

    init(matchById: [String: BracketMatchSnapshot], rowStride: CGFloat) {
        self.matchById = matchById
        self.rowStride = rowStride
    }

    func yCenter(for matchId: String) -> CGFloat {
        if let y = yCache[matchId] { return y }

        let y: CGFloat
        if let m = matchById[matchId] {
            if let feeders = m.feederMatchIds, feeders.count == 2 {
                let ys = feeders.map { yCenter(for: $0) }
                y = ys.reduce(0, +) / CGFloat(ys.count)
            } else if let parts = BracketMatchIdParse.roundAndMatchIndex(matchId), parts.round == 1 {
                y = CGFloat(parts.index) * rowStride + rowStride * 0.5
            } else {
                y = rowStride * 0.5
            }
        } else if let parts = BracketMatchIdParse.roundAndMatchIndex(matchId), parts.round == 1 {
            y = CGFloat(parts.index) * rowStride + rowStride * 0.5
        } else {
            y = rowStride * 0.5
        }

        yCache[matchId] = y
        return y
    }
}

private struct BracketConnectorSegments {
    static func segments(
        matches: [BracketMatchSnapshot],
        layout: BracketLayoutCache,
        colForRound: [Int: Int],
        cardWidth: CGFloat,
        columnGap: CGFloat,
        leftPad: CGFloat
    ) -> [(CGPoint, CGPoint)] {
        var out: [(CGPoint, CGPoint)] = []
        func xCardLeft(col: Int) -> CGFloat {
            leftPad + CGFloat(col) * (cardWidth + columnGap)
        }
        func xCardRight(col: Int) -> CGFloat {
            xCardLeft(col: col) + cardWidth
        }

        for m in matches {
            guard let feeders = m.feederMatchIds, feeders.count == 2,
                  let col = colForRound[m.roundNumber], col > 0
            else { continue }

            let yM = layout.yCenter(for: m.matchId)
            let y1 = layout.yCenter(for: feeders[0])
            let y2 = layout.yCenter(for: feeders[1])
            let mergeX = (xCardRight(col: col - 1) + xCardLeft(col: col)) * 0.5

            let rightPrev = xCardRight(col: col - 1)
            let leftSelf = xCardLeft(col: col)

            out.append((CGPoint(x: rightPrev, y: y1), CGPoint(x: mergeX, y: y1)))
            out.append((CGPoint(x: rightPrev, y: y2), CGPoint(x: mergeX, y: y2)))
            out.append((CGPoint(x: mergeX, y: y1), CGPoint(x: mergeX, y: y2)))
            out.append((CGPoint(x: mergeX, y: yM), CGPoint(x: leftSelf, y: yM)))
        }
        return out
    }
}

// MARK: - Pair card

private struct BracketMatchPairCard: View {
    let match: BracketMatchSnapshot
    let ui: BracketMatchUIState
    let members: [CommunityMemberRosterRow]
    let cardWidth: CGFloat
    /// When true, show a compact champion line inside the card footer (avoids a floating label overlapping the border).
    let showChampionFooter: Bool
    let onLogResult: () -> Void

    var body: some View {
        Group {
            if ui.isAutoAdvancedBye {
                compactByeCard
            } else {
                standardCard
            }
        }
        .frame(width: cardWidth, alignment: .leading)
    }

    private var compactByeCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Advanced (bye)")
                .font(AppFont.caption)
                .foregroundStyle(BracketBrandColor.accent)
            if !ui.topParticipantIds.isEmpty {
                Text(names(ui.topParticipantIds))
                    .font(AppFont.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            } else if let w = match.winnerProfileIds, !w.isEmpty {
                Text(names(w))
                    .font(AppFont.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.tertiarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(BracketBrandColor.accent.opacity(0.28), lineWidth: 1)
        )
    }

    private var standardCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            slotRow(ids: ui.topParticipantIds, isWinner: ui.winningSide == .top)
            Rectangle()
                .fill(BracketBrandColor.accent.opacity(0.22))
                .frame(height: 1)
            slotRow(ids: ui.bottomParticipantIds, isWinner: ui.winningSide == .bottom)

            if ui.isPlayed {
                VStack(alignment: .trailing, spacing: 6) {
                    Text("Final")
                        .font(AppFont.caption)
                        .foregroundStyle(BracketBrandColor.accent.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    if showChampionFooter {
                        Text("Champion")
                            .font(AppFont.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(BracketBrandColor.accent)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .padding(.top, 6)
            } else if ui.isWaitingOnFeeders {
                Text("Waiting…")
                    .font(AppFont.caption)
                    .foregroundStyle(BracketBrandColor.accent.opacity(0.55))
                    .padding(.top, 6)
            }

            if ui.canLogResult {
                Button(action: onLogResult) {
                    Text("Log game")
                        .font(AppFont.buttonProminent)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(BracketBrandColor.accent)
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(BracketBrandColor.accent.opacity(0.4), lineWidth: 1.5)
        )
    }

    @ViewBuilder
    private func slotRow(ids: [String], isWinner: Bool) -> some View {
        let text = ids.isEmpty ? "TBD" : names(ids)
        Text(text)
            .font(AppFont.bodyMedium)
            .foregroundStyle(
                isWinner ? BracketBrandColor.winnerGreen : (ids.isEmpty ? Color.secondary : Color.primary)
            )
            .fontWeight(isWinner ? .semibold : .regular)
            .lineLimit(2)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    private func names(_ ids: [String]) -> String {
        let mapped = members
            .filter { ids.contains($0.profileId) }
            .map { $0.displayName.isEmpty ? "Unknown" : $0.displayName }
        return mapped.isEmpty ? "—" : mapped.joined(separator: ", ")
    }
}

// MARK: - Tree

struct BracketTreeView: View {
    let rounds: [BracketRoundSnapshot]
    let matchById: [String: BracketMatchSnapshot]
    let members: [CommunityMemberRosterRow]
    let teamSize: Int
    let onLogResult: (BracketMatchSnapshot, [String]) -> Void

    private let cardWidth: CGFloat = 158
    private let columnGap: CGFloat = 28
    private let leftPad: CGFloat = 16
    private let topPad: CGFloat = 12
    private let rowStride: CGFloat = 122
    /// Half of a tall pair card (slots + divider + footer + optional Log game); avoids clipping when using `.position` centers.
    private let estimatedPairCardHalfHeight: CGFloat = 96
    private let treeContentBottomInset: CGFloat = 20

    private var sortedRounds: [BracketRoundSnapshot] {
        rounds.sorted { $0.roundNumber < $1.roundNumber }
    }

    private var flatMatches: [BracketMatchSnapshot] {
        sortedRounds.flatMap(\.matches)
    }

    private var colForRound: [Int: Int] {
        Dictionary(uniqueKeysWithValues: sortedRounds.enumerated().map { ($0.element.roundNumber, $0.offset) })
    }

    private var currentUserId: String? {
        Auth.auth().currentUser?.uid ?? UITestRuntime.currentUserIdFallback
    }

    private var viewerProfileIds: Set<String> {
        Set([currentUserId].compactMap { $0 })
    }

    var body: some View {
        let layout = BracketLayoutCache(matchById: matchById, rowStride: rowStride)
        let maxY = flatMatches.map { layout.yCenter(for: $0.matchId) }.max() ?? rowStride
        let contentHeight = topPad + maxY + estimatedPairCardHalfHeight + treeContentBottomInset
        let colCount = max(sortedRounds.count, 1)
        let contentWidth = leftPad + CGFloat(colCount) * cardWidth + CGFloat(max(0, colCount - 1)) * columnGap + leftPad
        let segments = BracketConnectorSegments.segments(
            matches: flatMatches,
            layout: layout,
            colForRound: colForRound,
            cardWidth: cardWidth,
            columnGap: columnGap,
            leftPad: leftPad
        )

        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for (a, b) in segments {
                        var p = Path()
                        p.move(to: a)
                        p.addLine(to: b)
                        context.stroke(p, with: .color(BracketBrandColor.accent.opacity(0.38)), lineWidth: 1.5)
                    }
                }
                .frame(width: contentWidth, height: contentHeight)
                .allowsHitTesting(false)

                ForEach(flatMatches) { match in
                    let col = colForRound[match.roundNumber] ?? 0
                    let xCenter = leftPad + CGFloat(col) * (cardWidth + columnGap) + cardWidth * 0.5
                    let y = topPad + layout.yCenter(for: match.matchId)
                    let ui = BracketMatchDisplay.uiState(
                        match: match,
                        matchById: matchById,
                        teamSize: teamSize,
                        currentUserId: currentUserId,
                        viewerProfileIds: viewerProfileIds
                    )
                    let isLoneFinalMatch = sortedRounds.last.map {
                        $0.matches.count == 1 && $0.matches.first?.matchId == match.matchId
                    } ?? false
                    let showChampionFooter = isLoneFinalMatch && ui.isPlayed
                    BracketMatchPairCard(
                        match: match,
                        ui: ui,
                        members: members,
                        cardWidth: cardWidth,
                        showChampionFooter: showChampionFooter,
                        onLogResult: {
                            onLogResult(match, ui.effectiveParticipantProfileIds)
                        }
                    )
                    .position(x: xCenter, y: y)
                }
            }
            .frame(width: contentWidth, height: contentHeight, alignment: .topLeading)
        }
        .accessibilityIdentifier("bracket.tree.scroll")
    }
}
