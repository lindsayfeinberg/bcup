import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import UIKit

/// Insets for the white stroked “widget” behind list rows — slightly larger horizontal inset reads better on narrow devices and TestFlight builds.
private enum GameLogFormLayout {
    static let widgetOutlineHorizontalPadding: CGFloat = 12
    static let widgetOutlineVerticalPadding: CGFloat = 6
    /// Insets around the game-type grid (replaces segmented control padding).
    static let gameTypeSegmentedInnerHorizontalPadding: CGFloat = 6
    static let gameTypeSegmentedInnerVerticalPadding: CGFloat = 4
    static let gameTypeGridSpacing: CGFloat = 8
}

/// Brand colors for the game log form.
private enum GameLogBrandColor {
    static let red = Color.black
    static let formLightRed = Color.black
    static let pillDark = Color(red: 8.0 / 255.0, green: 56.0 / 255.0, blue: 84.0 / 255.0)
    static let pillBackground = Color(red: 62.0 / 255.0, green: 132.0 / 255.0, blue: 173.0 / 255.0)
    static let wonGreen = Color(red: 0.0, green: 128.0 / 255.0, blue: 0.0)
    static let lostRed = Color(red: 180.0 / 255.0, green: 61.0 / 255.0, blue: 37.0 / 255.0)
}

/// When non-nil, `NewGameLogFormView` is driven by a specific bracket match.
/// The UI locks league + team size and restricts participant pickers to the match’s participants.
struct GameLogBracketContext {
    let bracketId: String
    let bracketMatchId: String
    let communityId: String
    let participantProfileIds: [String]
    let teamSize: Int
    /// From `brackets/{bracketId}.gameType` — locks the log form when bracket-linked.
    let bracketGameType: String
    let bracketCustomGameDefinitionId: String?
    let bracketCustomGameDefinitionName: String?

    init(
        bracketId: String,
        bracketMatchId: String,
        communityId: String,
        participantProfileIds: [String],
        teamSize: Int,
        bracketGameType: String = "PONG",
        bracketCustomGameDefinitionId: String? = nil,
        bracketCustomGameDefinitionName: String? = nil
    ) {
        self.bracketId = bracketId
        self.bracketMatchId = bracketMatchId
        self.communityId = communityId
        self.participantProfileIds = participantProfileIds
        self.teamSize = teamSize
        self.bracketGameType = bracketGameType
        self.bracketCustomGameDefinitionId = bracketCustomGameDefinitionId
        self.bracketCustomGameDefinitionName = bracketCustomGameDefinitionName
    }
}

struct NewGameLogFormView: View {
    /// `FeedCardView` photo section height; form preview uses the same layout at a smaller scale.
    private static let feedCardPhotoHeight: CGFloat = 500
    private static var gameLogPhotoPreviewHeight: CGFloat { feedCardPhotoHeight * 0.6 }

    /// Teammate/opponent picker list; previously a fixed 260pt — that remains the cap when many people are available.
    private static let participantPickerListMaxHeight: CGFloat = 260
    private static let participantPickerListRowStride: CGFloat = 56
    private static let participantPickerListMinHeight: CGFloat = 56
    private static let autoPeekTeamSizeAnchor = "gamelog.anchor.teamSize"
    private static let autoPeekPostSelectionAnchor = "gamelog.anchor.postSelection"
    private static let autoPeekTeammatesAnchor = "gamelog.anchor.teammates"
    private static let autoPeekOpponentsAnchor = "gamelog.anchor.opponents"
    private static let autoPeekChooseGameAnchor = "gamelog.anchor.chooseGame"
    private static let widgetTitleFont = Font.custom("NeueHaasDisplay-Bold", size: 16)
    /// Matches league “Rank by” chip section (`CommunityDetailView`).
    private static let gameTypeSectionTitleFont = Font.custom("NeueHaasDisplay-Bold", size: 15)
    private static let gameTypeChipLabelFont = Font.custom("NeueHaasDisplay-Mediu", size: 14)
    /// One point larger than `AppFont.body` (17), medium weight — teammate/opponent picker rows.
    private static let participantPickerRowNameFont = Font.custom("NeueHaasDisplay-Mediu", size: 18)

    /// Background behind the form.
    private static let formBackgroundSoftRed = Color.white
    private static let widgetOutlineColor = Color(.systemGray4)

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var container: DependencyContainer
    @EnvironmentObject private var sessionManager: AppSessionManager
    @State private var frontPhotoData: Data?
    @State private var backPhotoData: Data?
    @State private var showDualCapture = false

    let bracketContext: GameLogBracketContext?
    /// When set, the form loads that `gameLogs` doc and **Save** runs `updateGameLog` instead of create.
    private let editingGameLogId: String?

    private var isEditingExistingLog: Bool { editingGameLogId != nil }

    /// Operator correcting another user’s log: adjust winner/loser sides only — not framed as the operator’s win/loss.
    private var isOperatorNeutralEdit: Bool { isEditingExistingLog && sessionManager.isPlatformAdmin }

    private var isBracketLinked: Bool { bracketContext != nil }
    private var bracketParticipantProfileIdsInOrder: [String] {
        bracketContext?.participantProfileIds ?? []
    }
    private var bracketScopedParticipantProfileIds: Set<String> {
        Set(bracketContext?.participantProfileIds ?? [])
    }

    /// Bracket match defines the full roster; pickers stay read-only and teams follow outcome only.
    private var bracketTeamsAreFixed: Bool {
        isBracketLinked &&
            BracketMatchDisplay.bracketMatchHasValidTwoSides(
                n: bracketParticipantProfileIdsInOrder.count,
                teamSize: teamSize
            )
    }

    /// Winner/loser set sizes must match the two sides derived from stored participant order (supports uneven sides).
    private var bracketSelectionMatchesSideSizes: Bool {
        guard isBracketLinked else { return true }
        let ids = bracketParticipantProfileIdsInOrder
        let n = ids.count
        guard n >= 2,
              BracketMatchDisplay.bracketMatchHasValidTwoSides(n: n, teamSize: teamSize)
        else { return false }
        let firstCount = BracketMatchDisplay.splitIndexFirstTeam(n: n, teamSize: teamSize)
        let secondCount = n - firstCount
        let w = selectedWinnerProfileIds.count
        let l = selectedLoserProfileIds.count
        guard w + l == n,
              Set(ids) == selectedWinnerProfileIds.union(selectedLoserProfileIds)
        else { return false }
        return (w == firstCount && l == secondCount) || (w == secondCount && l == firstCount)
    }

    private var participantSelectionMatchesExpectedTeamSizes: Bool {
        if isOperatorNeutralEdit {
            return operatorRecordedParticipantSelectionValid
        }
        if isBracketLinked { return bracketSelectionMatchesSideSizes }
        return selectedWinnerProfileIds.count == teamSize &&
            selectedLoserProfileIds.count == teamSize
    }

    /// Operator edit: trust stored winner/loser sets (allows uneven sides, e.g. 2v3); still validate bracket shape when bracket-linked.
    private var operatorRecordedParticipantSelectionValid: Bool {
        let w = selectedWinnerProfileIds
        let l = selectedLoserProfileIds
        guard !w.isEmpty, !l.isEmpty else { return false }
        guard w.isDisjoint(with: l) else { return false }
        if isBracketLinked { return bracketSelectionMatchesSideSizes }
        return true
    }

    /// Roster rows for everyone in the bracket match (order preserved). Unknown ids get a placeholder row so pickers and counts stay correct when the league fetch is incomplete.
    private var bracketParticipantPoolMembers: [CommunityMemberRosterRow] {
        let byId = Dictionary(uniqueKeysWithValues: members.map { ($0.profileId, $0) })
        return bracketParticipantProfileIdsInOrder.map { id in
            byId[id] ?? CommunityMemberRosterRow(
                profileId: id,
                displayName: "Unknown",
                profilePhotoUrl: nil,
                communityOdds: 0,
                communityGamesPlayed: 0
            )
        }
    }

    init(
        frontPhotoData: Data? = nil,
        backPhotoData: Data? = nil,
        bracketContext: GameLogBracketContext? = nil,
        editingGameLogId: String? = nil
    ) {
        self.bracketContext = bracketContext
        self.editingGameLogId = editingGameLogId
        _frontPhotoData = State(initialValue: frontPhotoData)
        _backPhotoData = State(initialValue: backPhotoData)
        _selectedCommunityId = State(initialValue: bracketContext?.communityId ?? "")
        _teamSize = State(initialValue: bracketContext?.teamSize ?? 1)

        if let ctx = bracketContext,
           ctx.bracketGameType == "CUSTOM",
           let rawCustom = ctx.bracketCustomGameDefinitionId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawCustom.isEmpty {
            _selectedCustomDefinitionId = State(initialValue: rawCustom)
            _selectedCustomDefinitionName = State(
                initialValue: ctx.bracketCustomGameDefinitionName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
        } else if let ctx = bracketContext, let gt = GameType(rawValue: ctx.bracketGameType) {
            _selectedGameType = State(initialValue: gt)
        }
    }

    @State private var communities: [CommunityListItem] = []

    /// Leagues the user may log games in (excludes hidden leagues for non-creators).
    private var loggableCommunities: [CommunityListItem] {
        guard let uid = container.authService.currentUserId else {
            return communities.filter { !$0.hiddenFromMembers }
        }
        return communities.filter { !$0.hiddenFromMembers || $0.createdByProfileId == uid }
    }

    private var isLoggingCustomGame: Bool {
        let id = selectedCustomDefinitionId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !id.isEmpty
    }

    private var gameSummaryTitle: String {
        if isLoggingCustomGame {
            let n = selectedCustomDefinitionName.trimmingCharacters(in: .whitespacesAndNewlines)
            return n.isEmpty ? "Custom game" : n
        }
        return selectedGameType.displayName
    }

    /// Team size bounds for the current game selection (built-in vs league custom).
    private func currentTeamSizeRange() -> ClosedRange<Int> {
        if isBracketLinked, let ctx = bracketContext {
            return ctx.teamSize...ctx.teamSize
        }
        if isLoggingCustomGame {
            return LeagueRankingBasis.allGames.validTeamSizeRange(memberCount: members.count)
        }
        return validTeamSizeRange(for: selectedGameType)
    }

    @State private var isLoading = true
    @State private var errorMessage: String?

    @State private var selectedCommunityId: String = ""
    @State private var selectedGameType: GameType = .pong
    /// When set, log uses `gameType == "CUSTOM"` and `customGameDefinitionId` (Phase E3).
    @State private var selectedCustomDefinitionId: String?
    @State private var selectedCustomDefinitionName: String = ""
    @State private var customGameDefinitions: [GameDefinitionRecord] = []
    @State private var customDefinitionsError: String?
    @State private var isLoadingCustomDefinitions = false

    // Members used for winners/losers and stat entry.
    @State private var members: [CommunityMemberRosterRow] = []
    @State private var isMembersLoading = false
    @State private var membersErrorMessage: String?
    private let uiTestMembers: [CommunityMemberRosterRow] = [
        .init(profileId: "ui-test-user", displayName: "You", profilePhotoUrl: nil, communityOdds: 0.75, communityGamesPlayed: 4),
        .init(profileId: "ui-opponent-1", displayName: "Alex", profilePhotoUrl: nil, communityOdds: 0.62, communityGamesPlayed: 3),
        .init(profileId: "ui-opponent-2", displayName: "Riley", profilePhotoUrl: nil, communityOdds: 0.51, communityGamesPlayed: 2),
        .init(profileId: "ui-opponent-3", displayName: "Jordan", profilePhotoUrl: nil, communityOdds: 0.41, communityGamesPlayed: 2)
    ]

    private enum Outcome {
        case won, lost
    }

    @State private var outcome: Outcome? = nil
    @State private var isTeammateDropdownOpen = false
    @State private var isOpponentDropdownOpen = false
    @State private var teammateQuery = ""
    @State private var opponentQuery = ""

    @State private var teamSize: Int = 1
    @State private var selectedWinnerProfileIds: Set<String> = []
    @State private var selectedLoserProfileIds: Set<String> = []
    @State private var selectedMVPProfileId: String = ""
    @State private var selectedLVPProfileId: String = ""
    @State private var photoUrls: [String] = []
    @State private var participantSelectionRecency: [String: Int] = [:]
    @State private var participantSelectionCounter: Int = 0

    // T07.5 stats placeholders (persisted now).
    @State private var pongCupMode: PongCupMode = .ten
    @State private var pongCupsByProfileId: [String: Int] = [:]
    @State private var pongLastCupByProfileId: String = ""
    @State private var isPongCupBreakdownEnabled: Bool = false

    @State private var beerBallNewCansByProfileId: [String: Int] = [:]
    @State private var beerBallFirstFinishedByProfileId: String = ""

    @State private var battlePongCupsByProfileId: [String: Int] = [:]
    @State private var baseballHitsByProfileId: [String: Int] = [:]
    @State private var crossfireCupsByProfileId: [String: Int] = [:]
    @State private var crossfireLastCupByProfileId: String = ""

    @State private var gameLogNotes: String = ""

    @State private var submitErrorMessage: String?
    @State private var isSubmitting = false
    @State private var showOpenSettingsAction = false
    @State private var submitAfterCapture = false
    @State private var isLoadingEditDocument = false
    @State private var editDocumentLoadError: String?
    /// Filled for platform-admin edits when the league isn’t in `communities` / `loggableCommunities` (e.g. not a member).
    @State private var editingResolvedLeagueName: String = ""

    private var widgetOutlineBackground: some View {
        Color.clear
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Self.widgetOutlineColor, lineWidth: 2)
                    )
                    .padding(.horizontal, GameLogFormLayout.widgetOutlineHorizontalPadding)
                    .padding(.vertical, GameLogFormLayout.widgetOutlineVerticalPadding)
            )
    }

    /// Three columns (3 + 2 rows); chip styling aligned with league “Rank by” grid (`CommunityDetailView`).
    private var gameTypeGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: GameLogFormLayout.gameTypeGridSpacing),
            GridItem(.flexible(), spacing: GameLogFormLayout.gameTypeGridSpacing),
            GridItem(.flexible(), spacing: GameLogFormLayout.gameTypeGridSpacing)
        ]
        let chipAccent = GameLogBrandColor.lostRed
        return LazyVGrid(columns: columns, spacing: GameLogFormLayout.gameTypeGridSpacing) {
            ForEach(GameType.allCases) { type in
                let available = isGameTypeAvailable(type)
                let selected = !isLoggingCustomGame && selectedGameType == type
                Button {
                    guard available else { return }
                    selectedCustomDefinitionId = nil
                    selectedCustomDefinitionName = ""
                    selectedGameType = type
                } label: {
                    Text(type.displayName)
                        .font(Self.gameTypeChipLabelFont)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 6)
                        .foregroundStyle(
                            available
                                ? (selected ? chipAccent : Color.primary)
                                : Color.secondary
                        )
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selected && available ? Color.white : Color(UIColor.secondarySystemGroupedBackground))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    selected && available ? chipAccent : Color.primary.opacity(0.12),
                                    lineWidth: selected && available ? 2 : 1
                                )
                        }
                }
                .buttonStyle(.plain)
                .disabled(!available || isEditingExistingLog)
                .opacity(available ? 1.0 : 0.45)
                .accessibilityLabel(type.displayName)
                .accessibilityAddTraits(selected && available ? .isSelected : [])
            }
        }
        .disabled(isBracketLinked)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Game type")
    }

    @ViewBuilder
    private var customLeagueGameDefinitionsContent: some View {
        let chipAccent = GameLogBrandColor.lostRed
        let columns = [
            GridItem(.flexible(), spacing: GameLogFormLayout.gameTypeGridSpacing),
            GridItem(.flexible(), spacing: GameLogFormLayout.gameTypeGridSpacing),
            GridItem(.flexible(), spacing: GameLogFormLayout.gameTypeGridSpacing)
        ]
        VStack(alignment: .leading, spacing: 10) {
            Text("League custom games")
                .font(Self.gameTypeSectionTitleFont)
                .foregroundStyle(GameLogBrandColor.lostRed)
            if isLoadingCustomDefinitions {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading…")
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let defErr = customDefinitionsError {
                Text(defErr)
                    .font(AppFont.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if customGameDefinitions.isEmpty {
                Text("No custom games yet. Open this league and tap “Manage custom games” to add one.")
                .font(AppFont.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(columns: columns, spacing: GameLogFormLayout.gameTypeGridSpacing) {
                    ForEach(customGameDefinitions) { def in
                        let selected = selectedCustomDefinitionId == def.gameDefinitionId
                        Button {
                            selectedCustomDefinitionId = def.gameDefinitionId
                            selectedCustomDefinitionName = def.name
                            resetSelectionForScopeChange(preserveCustomDefinition: true)
                        } label: {
                            Text(def.name)
                                .font(Self.gameTypeChipLabelFont)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .padding(.horizontal, 6)
                                .foregroundStyle(selected ? chipAccent : Color.primary)
                                .background {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(selected ? Color.white : Color(UIColor.secondarySystemGroupedBackground))
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(
                                            selected ? chipAccent : Color.primary.opacity(0.12),
                                            lineWidth: selected ? 2 : 1
                                        )
                                }
                        }
                        .buttonStyle(.plain)
                        .disabled(isEditingExistingLog || isBracketLinked)
                        .opacity((isEditingExistingLog || isBracketLinked) ? 0.45 : 1.0)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var gameLogFormSections: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                if isEditingExistingLog,
                   frontPhotoData == nil,
                   backPhotoData == nil,
                   let urlString = photoUrls.first,
                   let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: Self.gameLogPhotoPreviewHeight * 0.5)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .frame(height: Self.gameLogPhotoPreviewHeight)
                        case .failure:
                            Text("Couldn’t load saved photo")
                                .font(AppFont.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: Self.gameLogPhotoPreviewHeight * 0.4)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    concatenatedPhotoStrip(front: frontPhotoData, back: backPhotoData)
                }

                HStack {
                    Spacer()
                    if frontPhotoData == nil && backPhotoData == nil {
                        if isEditingExistingLog, !photoUrls.isEmpty {
                            Button {
                                showDualCapture = true
                            } label: {
                                Text("Replace photos")
                                    .font(AppFont.buttonProminent)
                            }
                            .buttonStyle(BrandPrimaryButtonStyle())
                        } else {
                            Button {
                                showDualCapture = true
                            } label: {
                                Text("Capture both cameras")
                                    .font(AppFont.buttonProminent)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    } else {
                        Button {
                            showDualCapture = true
                        } label: {
                            Text("Retake")
                                .font(AppFont.buttonProminent)
                        }
                        .buttonStyle(BrandPrimaryButtonStyle())
                    }
                    Spacer()
                }
            }
        } header: {
            Text("Game Photos")
                .font(Self.widgetTitleFont)
                .foregroundStyle(.black)
        }
        .listRowBackground(widgetOutlineBackground)

        Section {
            Picker(selection: $selectedCommunityId) {
                ForEach(loggableCommunities, id: \.communityId) { community in
                    Text(community.name)
                        .font(AppFont.body)
                        .foregroundStyle(.black)
                        .tag(community.communityId)
                }
            } label: {
                Text("League")
                    .font(AppFont.headline)
            }
            .disabled(isBracketLinked || isEditingExistingLog)
        } header: {
            Text("Choose League")
                .font(Self.widgetTitleFont)
                .foregroundStyle(GameLogBrandColor.red)
        }
        .listRowBackground(widgetOutlineBackground)

        Section {
            gameTypeGrid
                .padding(.horizontal, GameLogFormLayout.gameTypeSegmentedInnerHorizontalPadding)
                .padding(.vertical, GameLogFormLayout.gameTypeSegmentedInnerVerticalPadding)

            if isEditingExistingLog, isLoggingCustomGame {
                Text("Custom game: \(gameSummaryTitle)")
                    .font(AppFont.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            } else if isBracketLinked, let ctx = bracketContext {
                Text(bracketLockedGameTypeCaption(ctx: ctx))
                    .font(AppFont.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            } else if !isBracketLinked {
                customLeagueGameDefinitionsContent
                    .padding(.top, 8)
            }
        } header: {
            Text("Choose Game Type")
                .font(Self.gameTypeSectionTitleFont)
                .foregroundStyle(GameLogBrandColor.lostRed)
        }
        .id(Self.autoPeekChooseGameAnchor)
        .listRowBackground(widgetOutlineBackground)

        Section {
            if isLoggingCustomGame || isGameTypeAvailable(selectedGameType) {
                if isOperatorNeutralEdit {
                    Text(
                        "Update which side won this logged game. This only changes the saved result for these players — it is not your personal win or loss."
                    )
                    .font(AppFont.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                    Button {
                        swapWinningAndLosingTeams()
                    } label: {
                        Text("Swap winning team")
                            .font(AppFont.buttonProminent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(BrandPrimaryButtonStyle())
                    .disabled(!participantSelectionMatchesExpectedTeamSizes)
                    .accessibilityIdentifier("gamelog.operator.swapWinningTeam")

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Winners: \(namesList(for: selectedWinnerProfileIds))")
                            .font(AppFont.subheadlineBold)
                            .foregroundStyle(.black)
                        Text("Losers: \(namesList(for: selectedLoserProfileIds))")
                            .font(AppFont.subheadlineBold)
                            .foregroundStyle(.black)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(spacing: 12) {
                        Button {
                            outcome = .won
                            lockUserIntoOutcome()
                        } label: {
                            Text("I won")
                                .font(AppFont.buttonProminent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(outcome == .won ? GameLogBrandColor.wonGreen : .white)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(GameLogBrandColor.wonGreen, lineWidth: 2)
                                )
                                .contentShape(Rectangle())
                        }
                        .foregroundStyle(outcome == .won ? .white : GameLogBrandColor.wonGreen)
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.plain)
                        .disabled(isBracketLinked && !currentUserIsGameMember && !isEditingExistingLog)
                        .accessibilityIdentifier("gamelog.outcome.won")

                        Button {
                            outcome = .lost
                            lockUserIntoOutcome()
                        } label: {
                            Text("I lost")
                                .font(AppFont.buttonProminent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(outcome == .lost ? GameLogBrandColor.lostRed : .white)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(GameLogBrandColor.lostRed, lineWidth: 2)
                                )
                                .contentShape(Rectangle())
                        }
                        .foregroundStyle(outcome == .lost ? .white : GameLogBrandColor.lostRed)
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.plain)
                        .disabled(isBracketLinked && !currentUserIsGameMember && !isEditingExistingLog)
                        .accessibilityIdentifier("gamelog.outcome.lost")
                    }
                }
            } else {
                Text(unavailableGameTypeMessage)
                    .font(AppFont.subheadline)
                    .foregroundStyle(.black)
            }
        } header: {
            Text(isOperatorNeutralEdit ? "Recorded result" : "Outcome")
                .font(Self.widgetTitleFont)
                .foregroundStyle(GameLogBrandColor.red)
        }
        .listRowBackground(widgetOutlineBackground)

        if outcome != nil {
            Section {
                let range = currentTeamSizeRange()
                Stepper(value: $teamSize, in: range, step: 1) {
                    Text("\(teamSize)")
                        .font(AppFont.headline)
                        .foregroundStyle(.black)
                }
                .disabled(isBracketLinked || isOperatorNeutralEdit)
            } header: {
                Text("Team size")
                    .font(Self.widgetTitleFont)
                    .foregroundStyle(GameLogBrandColor.red)
            }
            .id(Self.autoPeekTeamSizeAnchor)
            .listRowBackground(widgetOutlineBackground)

            fillSlotsFormSections

            if shouldShowPostSelectionSections {
                    if shouldShowDetailsSection {
                        Section {
                            statsSectionContent
                        } header: {
                            Text("Details (Optional)")
                                .font(Self.widgetTitleFont)
                                .foregroundStyle(GameLogBrandColor.red)
                        }
                        .listRowBackground(widgetOutlineBackground)
                    }

                    Section {
                        if participantProfileIds.isEmpty {
                            Text("Select winners and losers to choose MVP/LVP.")
                                .font(AppFont.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 12) {
                                Picker(selection: $selectedMVPProfileId) {
                                    Text("None")
                                        .font(AppFont.body)
                                        .tag("")
                                    ForEach(selectedParticipants, id: \.profileId) { participant in
                                        Text(displayName(for: participant.profileId))
                                            .font(AppFont.body)
                                            .tag(participant.profileId)
                                    }
                                } label: {
                                    Text("MVP   ˗ˏˋ ★ ˎˊ˗")
                                        .font(AppFont.headline)
                                }
                                .font(AppFont.body)
                                Picker(selection: $selectedLVPProfileId) {
                                    Text("None")
                                        .font(AppFont.body)
                                        .tag("")
                                    ForEach(selectedParticipants, id: \.profileId) { participant in
                                        Text(displayName(for: participant.profileId))
                                            .font(AppFont.body)
                                            .tag(participant.profileId)
                                    }
                                } label: {
                                    Text("LVP ")
                                        .font(AppFont.headline)
                                }
                                .font(AppFont.body)
                            }
                        }
                    } header: {
                        Text("Awards (Optional)")
                            .font(Self.widgetTitleFont)
                            .foregroundStyle(GameLogBrandColor.red)
                    }
                    .id(Self.autoPeekPostSelectionAnchor)
                    .listRowBackground(widgetOutlineBackground)

                    Section {
                        TextField("Add a note", text: $gameLogNotes)
                            .font(AppFont.body)
                            .textFieldStyle(.plain)
                    } header: {
                        Text("Notes (Optional)")
                            .font(Self.widgetTitleFont)
                            .foregroundStyle(GameLogBrandColor.red)
                    }
                    .listRowBackground(widgetOutlineBackground)

                    Section {
                        summaryWidgetContent
                    } header: {
                        Text("Summary")
                            .font(Self.widgetTitleFont)
                            .foregroundStyle(GameLogBrandColor.red)
                    }
                    .listRowBackground(widgetOutlineBackground)

                    Section {
                        if !submitDisableReasons.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Missing before submit:")
                                    .font(AppFont.subheadlineBold)
                                    .foregroundStyle(GameLogBrandColor.lostRed)
                                ForEach(submitDisableReasons, id: \.self) { reason in
                                    Text("• \(reason)")
                                        .font(AppFont.subheadlineBold)
                                        .foregroundStyle(GameLogBrandColor.lostRed)
                                }
                            }
                        }
                        if let submitErrorMessage {
                            Text(submitErrorMessage)
                                .foregroundStyle(.black)
                                .font(AppFont.footnote)
                            if showOpenSettingsAction {
                                Button {
                                    guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
                                    UIApplication.shared.open(settingsURL)
                                } label: {
                                    Text("Open Settings")
                                        .font(AppFont.button)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        if isSubmitting {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text(isEditingExistingLog ? "Saving…" : "Submitting game log...")
                                    .font(AppFont.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button {
                            Task { await handleSubmitTapped() }
                        } label: {
                            Text(isEditingExistingLog ? "Save changes" : "Submit Game")
                                .font(AppFont.buttonProminent)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SubmitGameButtonStyle())
                        .disabled(!canSubmitWithoutPhotos || isSubmitting)
                        .accessibilityIdentifier("gamelog.submit")
                    }
            }
        }
    }

    var body: some View {
        Group {
            if isLoadingEditDocument {
                LoadingView(message: "Loading game…")
            } else if let editDocumentLoadError {
                ErrorView(message: editDocumentLoadError) {
                    Task { await loadExistingGameLogForEditingIfNeeded() }
                }
            } else if isLoading {
                LoadingView(message: "Loading leagues...")
            } else if let errorMessage {
                ErrorView(message: errorMessage) {
                    Task { await load() }
                }
            } else if communities.isEmpty {
                EmptyStateView(
                    title: "No leagues yet",
                    message: "Create or join a league to log a game.",
                    actionLabel: nil
                )
            } else if loggableCommunities.isEmpty {
                EmptyStateView(
                    title: "No league to log in",
                    message: "Leagues hidden by the host aren't available for new logs unless you're the host.",
                    actionLabel: nil
                )
            } else {
                ScrollViewReader { proxy in
                    Form {
                        gameLogFormSections
                    }
                    .scrollContentBackground(.hidden)
                    .background(Self.formBackgroundSoftRed)
                    .onChange(of: outcome) { _, newOutcome in
                        guard newOutcome != nil else { return }
                        DispatchQueue.main.async {
                            withAnimation(.easeInOut(duration: 0.42)) {
                                proxy.scrollTo(Self.autoPeekTeamSizeAnchor, anchor: .top)
                            }
                        }
                    }
                    .onChange(of: isTeammateDropdownOpen) { _, isOpen in
                        guard isOpen else { return }
                        DispatchQueue.main.async {
                            withAnimation(.easeOut(duration: 0.32)) {
                                proxy.scrollTo(Self.autoPeekTeammatesAnchor, anchor: .top)
                            }
                        }
                    }
                    .onChange(of: isOpponentDropdownOpen) { _, isOpen in
                        guard isOpen else { return }
                        DispatchQueue.main.async {
                            withAnimation(.easeOut(duration: 0.32)) {
                                proxy.scrollTo(Self.autoPeekOpponentsAnchor, anchor: .top)
                            }
                        }
                    }
                }
            }
        }
        .task {
            await loadExistingGameLogForEditingIfNeeded()
            await loadIfNeeded()
            if !selectedCommunityId.isEmpty {
                async let defsLoaded: Void = loadCustomGameDefinitions()
                async let membersLoaded: Void = loadMembers()
                _ = await (defsLoaded, membersLoaded)
            }
            applyBracketLockedGameTypeIfNeeded()
        }
        .onChange(of: selectedCommunityId) { _, _ in
            resetSelectionForScopeChange()
            Task {
                async let defsLoaded: Void = loadCustomGameDefinitions()
                async let membersLoaded: Void = loadMembers()
                _ = await (defsLoaded, membersLoaded)
            }
        }
        .onChange(of: selectedGameType) { _, _ in
            let newRange = currentTeamSizeRange()
            teamSize = min(max(teamSize, newRange.lowerBound), newRange.upperBound)
            resetSelectionForScopeChange()
            syncStatsWithParticipants()
        }
        .onChange(of: selectedCustomDefinitionId) { _, _ in
            let newRange = currentTeamSizeRange()
            teamSize = min(max(teamSize, newRange.lowerBound), newRange.upperBound)
            syncStatsWithParticipants()
        }
        .onChange(of: teamSize) { _, newValue in
            if newValue <= 1 { isTeammateDropdownOpen = false }
            if selectedWinnerProfileIds.count > newValue || selectedLoserProfileIds.count > newValue {
                resetSelectionForScopeChange()
            }
            syncStatsWithParticipants()
        }
        .onChange(of: selectedWinnerProfileIds) { _, _ in
            syncStatsWithParticipants()
        }
        .onChange(of: selectedLoserProfileIds) { _, _ in
            syncStatsWithParticipants()
        }
        .fullScreenCover(isPresented: $showDualCapture) {
            DualCameraCaptureView(
                onCaptured: { front, back in
                    frontPhotoData = front
                    backPhotoData = back
                    showDualCapture = false
                    if submitAfterCapture {
                        submitAfterCapture = false
                        Task { await submitGameLog() }
                    }
                },
                onCancel: {
                    showDualCapture = false
                    if submitAfterCapture {
                        submitAfterCapture = false
                        submitErrorMessage = "Capture was canceled before submission."
                    }
                }
            )
            .ignoresSafeArea()
        }
    }

    /// Read-only roster for operator edits (no “your team” pickers tied to the signed-in user).
    @ViewBuilder
    private func operatorNeutralRecordedRosterContent(
        selectionPoolMembers: [CommunityMemberRosterRow],
        hasEnoughMembers: Bool
    ) -> some View {
        if !hasEnoughMembers {
            Section {
                Text(
                    isBracketLinked
                        ? "This bracket match doesn’t list a valid two-sided roster yet."
                        : "League doesn’t have enough members for a team of size \(teamSize)."
                )
                .font(AppFont.subheadline)
                .foregroundStyle(.black)
            }
            .listRowBackground(widgetOutlineBackground)
        } else if bracketTeamsAreFixed && teamSize > 1 {
            Section {
                bracketFixedTeamRosterBlock(
                    title: "Winning team",
                    profileIds: sortedProfileIdsForBracketDisplay(selectedWinnerProfileIds),
                    pool: selectionPoolMembers
                )
            }
            .listRowBackground(widgetOutlineBackground)

            Section {
                bracketFixedTeamRosterBlock(
                    title: "Losing team",
                    profileIds: sortedProfileIdsForBracketDisplay(selectedLoserProfileIds),
                    pool: selectionPoolMembers
                )
            }
            .listRowBackground(widgetOutlineBackground)
        } else {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Winning team")
                        .font(Self.widgetTitleFont)
                        .foregroundStyle(GameLogBrandColor.wonGreen)
                    ForEach(sortedProfileIds(for: selectedWinnerProfileIds), id: \.self) { profileId in
                        Text(displayName(for: profileId))
                            .font(Self.participantPickerRowNameFont)
                            .foregroundStyle(.black)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .listRowBackground(widgetOutlineBackground)

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Losing team")
                        .font(Self.widgetTitleFont)
                        .foregroundStyle(GameLogBrandColor.lostRed)
                    ForEach(sortedProfileIds(for: selectedLoserProfileIds), id: \.self) { profileId in
                        Text(displayName(for: profileId))
                            .font(Self.participantPickerRowNameFont)
                            .foregroundStyle(.black)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .listRowBackground(widgetOutlineBackground)
        }
    }

    /// Teammates + opponents; opponents use a `Section` header so the title sits outside the white widget row.
    @ViewBuilder
    private var fillSlotsFormSections: some View {
        if isMembersLoading {
            Section {
                LoadingView(message: "Loading members...")
            }
            .listRowBackground(widgetOutlineBackground)
        } else if let membersErrorMessage {
            Section {
                ErrorView(message: membersErrorMessage) {
                    Task {
                        async let defsLoaded: Void = loadCustomGameDefinitions()
                        async let membersLoaded: Void = loadMembers()
                        _ = await (defsLoaded, membersLoaded)
                    }
                }
            }
            .listRowBackground(widgetOutlineBackground)
        } else if members.isEmpty {
            Section {
                Text("No members found for this league.")
                    .font(AppFont.subheadline)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(widgetOutlineBackground)
        } else {
            let selectionPoolMembers = isBracketLinked ? bracketParticipantPoolMembers : members
            // Bracket matches already define exactly who plays; don’t require every id to appear in the league roster response.
            let hasEnoughMembers = isBracketLinked
                ? bracketTeamsAreFixed
                : (selectionPoolMembers.count >= (2 * teamSize))
            if isOperatorNeutralEdit {
                operatorNeutralRecordedRosterContent(
                    selectionPoolMembers: selectionPoolMembers,
                    hasEnoughMembers: hasEnoughMembers
                )
            } else if let outcome, let myUserId = currentUserId {
                let isMySideWinners = (outcome == .won)
                let teammateSet = isMySideWinners ? selectedWinnerProfileIds : selectedLoserProfileIds
                let opponentSet = isMySideWinners ? selectedLoserProfileIds : selectedWinnerProfileIds

                if !hasEnoughMembers {
                    Section {
                        Text(
                            isBracketLinked
                                ? "This bracket match doesn’t list a valid two-sided roster yet. Try again after the matchup is fully set, or contact a league admin."
                                : "League doesn’t have enough members for a team of size \(teamSize)."
                        )
                            .font(AppFont.subheadline)
                            .foregroundStyle(.black)
                    }
                    .listRowBackground(widgetOutlineBackground)
                }

                if bracketTeamsAreFixed && hasEnoughMembers {
                    if teamSize > 1 {
                        Section {
                            bracketFixedTeamRosterBlock(
                                title: "Your team",
                                profileIds: sortedProfileIdsForBracketDisplay(teammateSet),
                                pool: selectionPoolMembers
                            )
                        }
                        .id(Self.autoPeekTeammatesAnchor)
                        .listRowBackground(widgetOutlineBackground)
                    }

                    Section {
                        bracketFixedTeamRosterBlock(
                            title: teamSize > 1 ? "Opponents" : "Opponent",
                            profileIds: sortedProfileIdsForBracketDisplay(opponentSet),
                            pool: selectionPoolMembers
                        )
                    }
                    .id(Self.autoPeekOpponentsAnchor)
                    .listRowBackground(widgetOutlineBackground)
                } else {
                    if teamSize > 1 {
                        Section {
                            dropdownBlock(
                                title: "Choose team",
                                includeTitleAboveButton: false,
                                selectedCount: teammateSet.count,
                                query: $teammateQuery,
                                isOpen: $isTeammateDropdownOpen,
                                participants: selectionPoolMembers.filter { $0.profileId != myUserId },
                                onOpposite: opponentSet,
                                onCurrent: teammateSet,
                                oppositeLabel: "Choose Opponents",
                                hasEnoughMembers: hasEnoughMembers
                            ) { profileId, isSelected in
                                toggleTeammate(profileId: profileId, isSelected: isSelected)
                            }
                        } header: {
                            participantSectionHeaderPills(
                                selectedProfileIds: teammateSet.subtracting([myUserId]),
                                members: selectionPoolMembers.filter { $0.profileId != myUserId }
                            )
                        }
                        .id(Self.autoPeekTeammatesAnchor)
                        .listRowBackground(widgetOutlineBackground)
                    }

                    Section {
                        dropdownBlock(
                            title: "Choose opponents",
                            includeTitleAboveButton: false,
                            buttonTitleForeground: .black,
                            selectedCount: opponentSet.count,
                            query: $opponentQuery,
                            isOpen: $isOpponentDropdownOpen,
                            participants: selectionPoolMembers.filter { $0.profileId != myUserId },
                            onOpposite: teammateSet,
                            onCurrent: opponentSet,
                            oppositeLabel: "Choose Teammates",
                            hasEnoughMembers: hasEnoughMembers
                        ) { profileId, isSelected in
                            toggleOpponent(profileId: profileId, isSelected: isSelected)
                        }
                    } header: {
                        participantSectionHeaderPills(
                            selectedProfileIds: opponentSet,
                            members: selectionPoolMembers.filter { $0.profileId != myUserId }
                        )
                    }
                    .id(Self.autoPeekOpponentsAnchor)
                    .listRowBackground(widgetOutlineBackground)
                }
            }
        }
    }

    /// Height of the member list inside teammate/opponent dropdowns scales with how many rows match the search (at least one row’s worth, capped at `participantPickerListMaxHeight`).
    private func participantPickerListHeight(visibleRowCount: Int) -> CGFloat {
        let n = max(1, visibleRowCount)
        return min(
            Self.participantPickerListMaxHeight,
            max(Self.participantPickerListMinHeight, CGFloat(n) * Self.participantPickerListRowStride)
        )
    }

    /// Selected opponent chips above the white widget; title lives in the dropdown row next to the count.
    @ViewBuilder
    private func participantSectionHeaderPills(
        selectedProfileIds: Set<String>,
        members: [CommunityMemberRosterRow]
    ) -> some View {
        let headerHeight: CGFloat = 32
        let selectedParticipants = members
            .filter { selectedProfileIds.contains($0.profileId) }
            .sorted { lhs, rhs in
                let lSeq = participantSelectionRecency[lhs.profileId] ?? -1
                let rSeq = participantSelectionRecency[rhs.profileId] ?? -1
                if lSeq != rSeq { return lSeq > rSeq } // most recent first (leftmost)
                let left = lhs.displayName.isEmpty ? "Unknown" : lhs.displayName
                let right = rhs.displayName.isEmpty ? "Unknown" : rhs.displayName
                return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
            }
        Group {
            if selectedParticipants.isEmpty {
                Color.clear
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(selectedParticipants, id: \.profileId) { member in
                            Text(member.displayName.isEmpty ? "Unknown" : member.displayName)
                                .font(AppFont.subheadlineBold)
                                .foregroundStyle(GameLogBrandColor.pillDark)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(GameLogBrandColor.pillBackground.opacity(0.22))
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(GameLogBrandColor.pillDark, lineWidth: 1)
                                )
                        }
                    }
                }
            }
        }
        .frame(height: headerHeight, alignment: .leading)
        // Reduce vertical gap between pills and the dropdown row below.
        .padding(.bottom, -8)
    }

    private func sortedProfileIdsForBracketDisplay(_ ids: Set<String>) -> [String] {
        ids.sorted { lhs, rhs in
            let lSeq = participantSelectionRecency[lhs] ?? -1
            let rSeq = participantSelectionRecency[rhs] ?? -1
            if lSeq != rSeq { return lSeq > rSeq }
            return lhs < rhs
        }
    }

    @ViewBuilder
    private func bracketFixedTeamRosterBlock(title: String, profileIds: [String], pool: [CommunityMemberRosterRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Self.widgetTitleFont)
                .foregroundStyle(GameLogBrandColor.red)
            Text("Set by this bracket match.")
                .font(AppFont.footnote)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(profileIds, id: \.self) { profileId in
                        let label = pool.first { $0.profileId == profileId }
                            .map { $0.displayName.isEmpty ? "Unknown" : $0.displayName } ?? "Unknown"
                        Text(label)
                            .font(AppFont.subheadlineBold)
                            .foregroundStyle(GameLogBrandColor.pillDark)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(GameLogBrandColor.pillBackground.opacity(0.22))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(GameLogBrandColor.pillDark, lineWidth: 1)
                            )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dropdownBlock(
        title: String,
        includeTitleAboveButton: Bool = true,
        buttonTitleForeground: Color? = nil,
        selectedCount: Int,
        query: Binding<String>,
        isOpen: Binding<Bool>,
        participants: [CommunityMemberRosterRow],
        onOpposite: Set<String>,
        onCurrent: Set<String>,
        oppositeLabel: String,
        hasEnoughMembers: Bool,
        onToggle: @escaping (String, Bool) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !title.isEmpty, includeTitleAboveButton {
                Text(title)
                    .font(Self.widgetTitleFont)
                    .foregroundStyle(GameLogBrandColor.red)
            }

            Button {
                isOpen.wrappedValue.toggle()
                if isOpen.wrappedValue { query.wrappedValue = "" }
            } label: {
                HStack {
                    if !title.isEmpty, !includeTitleAboveButton {
                        Text(title)
                            .font(AppFont.headline)
                            .foregroundStyle(buttonTitleForeground ?? .primary)
                    }
                    Spacer()
                    Text("\(selectedCount)/\(teamSize)")
                        .font(AppFont.subheadline)
                        .foregroundStyle(.black)
                    Image(systemName: isOpen.wrappedValue ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.black)
                }
            }
            .disabled(!hasEnoughMembers)
            .accessibilityIdentifier("gamelog.dropdown.\(title.replacingOccurrences(of: " ", with: "_"))")

            if isOpen.wrappedValue {
                let filtered = participants.filter { member in
                    let q = query.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    guard !q.isEmpty else { return true }
                    return member.displayName.lowercased().contains(q) || member.profileId.lowercased().contains(q)
                }

                TextField("Search...", text: query)
                    .font(AppFont.body)
                    .textFieldStyle(.roundedBorder)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(filtered, id: \.profileId) { member in
                            let profileId = member.profileId
                            let isSelected = onCurrent.contains(profileId)
                            let onOppositeSide = onOpposite.contains(profileId)
                            let disablePick = !isSelected && onOppositeSide
                            let canAdd = isSelected || onCurrent.count < teamSize
                            let rowDisabled = disablePick || !canAdd

                            Button {
                                guard !rowDisabled else { return }
                                onToggle(profileId, isSelected)
                            } label: {
                                Group {
                                    if onOppositeSide {
                                        HStack(spacing: 12) {
                                            Image(systemName: "xmark.circle.fill")
                                                .foregroundStyle(.black)
                                            Text(member.displayName.isEmpty ? "Unknown" : member.displayName)
                                                .font(Self.participantPickerRowNameFont)
                                                .foregroundStyle(.primary)
                                            Text(oppositeLabel)
                                                .font(AppFont.footnote)
                                                .foregroundStyle(.secondary)
                                            Spacer(minLength: 0)
                                        }
                                    } else {
                                        Text(member.displayName.isEmpty ? "Unknown" : member.displayName)
                                            .font(Self.participantPickerRowNameFont)
                                            .foregroundStyle(isSelected ? GameLogBrandColor.pillDark : .black)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                // Make the entire rendered row hittable, including trailing whitespace.
                                .contentShape(Rectangle())
                                .background {
                                    if !onOppositeSide, isSelected {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(GameLogBrandColor.pillBackground.opacity(0.22))
                                    }
                                }
                                .overlay {
                                    if !onOppositeSide, isSelected {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(GameLogBrandColor.pillDark, lineWidth: 1)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .buttonStyle(.plain)
                            .disabled(rowDisabled)
                            .accessibilityIdentifier("gamelog.participant.\(profileId)")
                        }
                    }
                }
                .frame(height: participantPickerListHeight(visibleRowCount: filtered.count))
            }
        }
    }

    @ViewBuilder
    private var summaryWidgetContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("League: \(selectedLeagueNameForSummary)")
                .font(AppFont.subheadlineBold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Text("Game: \(gameSummaryTitle)")
                .font(AppFont.subheadlineBold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Text("Winners: \(namesList(for: selectedWinnerProfileIds))")
                .font(AppFont.subheadlineBold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Text("Losers: \(namesList(for: selectedLoserProfileIds))")
                .font(AppFont.subheadlineBold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            if !selectedMVPProfileId.isEmpty {
                Text("MVP: \(displayName(for: selectedMVPProfileId))")
                    .font(AppFont.subheadlineBold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !selectedLVPProfileId.isEmpty {
                Text("LVP: \(displayName(for: selectedLVPProfileId))")
                    .font(AppFont.subheadlineBold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            summaryStatsDetailContent
        }
        .foregroundStyle(.black)
    }

    @ViewBuilder
    private var summaryStatsDetailContent: some View {
        if isLoggingCustomGame, !participantProfileIds.isEmpty {
            Text("Add optional notes below for how this custom game went.")
                .font(AppFont.subheadlineBold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        } else if !participantProfileIds.isEmpty {
            switch selectedGameType {
            case .pong:
                if teamSize > 1 {
                    Text("Cup game: \(pongCupMode.displayName)")
                        .font(AppFont.subheadlineBold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if isPongCupBreakdownEnabled {
                        ForEach(participantProfileIds.sorted(), id: \.self) { profileId in
                            let cups = pongCupsByProfileId[profileId] ?? 0
                            if cups > 0 {
                                Text("\(displayName(for: profileId)): \(cups) cups")
                                    .font(AppFont.subheadlineBold)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    if !pongLastCupByProfileId.isEmpty {
                        Text("Last cup: \(displayName(for: pongLastCupByProfileId))")
                            .font(AppFont.subheadlineBold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if soloWinnerProfileId != nil {
                    Text("Pong: Solo \(pongCupMode.displayName)")
                        .font(AppFont.subheadlineBold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !pongLastCupByProfileId.isEmpty {
                        Text("Last cup: \(displayName(for: pongLastCupByProfileId))")
                            .font(AppFont.subheadlineBold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            case .beerBall:
                Text("Beer Ball: \(totalBeerBallNewCans) new cans")
                    .font(AppFont.subheadlineBold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                if !beerBallFirstFinishedByProfileId.isEmpty {
                    Text("Finished first: \(displayName(for: beerBallFirstFinishedByProfileId))")
                        .font(AppFont.subheadlineBold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .battlePong:
                Text("Battle Pong: \(totalBattlePongCupsMade) cups made")
                    .font(AppFont.subheadlineBold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            case .baseball:
                Text("Baseball: \(totalBaseballHits) hits")
                    .font(AppFont.subheadlineBold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            case .crossfire:
                Text("Crossfire")
                    .font(AppFont.subheadlineBold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(participantProfileIds.sorted(), id: \.self) { profileId in
                    let cups = crossfireCupsByProfileId[profileId] ?? 0
                    if cups > 0 {
                        Text("\(displayName(for: profileId)): \(cups) cups")
                            .font(AppFont.subheadlineBold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !crossfireLastCupByProfileId.isEmpty {
                    Text("Last cup: \(displayName(for: crossfireLastCupByProfileId))")
                        .font(AppFont.subheadlineBold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private var statsSectionContent: some View {
        if participantProfileIds.isEmpty {
            Text("Select winners and losers to enter game stats.")
                .font(AppFont.subheadline)
                .foregroundStyle(.secondary)
        } else if isLoggingCustomGame {
            Text("This custom game only records winners, losers, and optional notes — no extra stat fields.")
                .font(AppFont.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            switch selectedGameType {
            case .pong:
                pongStatsView
            case .beerBall:
                beerBallStatsView
            case .battlePong:
                battlePongStatsView
            case .baseball:
                baseballStatsView
            case .crossfire:
                crossfireStatsView
            }
        }
    }

    @ViewBuilder
    private var pongStatsView: some View {
        if teamSize == 1 {
            VStack(alignment: .leading, spacing: 20) {
                let winnerId = selectedWinnerProfileIds.first ?? ""
                let loserId = selectedLoserProfileIds.first ?? ""

                Text("Cup game: 10-cup")
                    .font(AppFont.subheadlineBold)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Winning player")
                        .font(AppFont.subheadlineBold)
                    Text("\(displayName(for: winnerId)): 10 cups")
                        .font(AppFont.body)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Losing player")
                        .font(AppFont.subheadlineBold)
                    HStack(spacing: 12) {
                        Text("\(displayName(for: loserId)): \(pongCupsByProfileId[loserId] ?? 0) cups")
                            .font(AppFont.body)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Picker(
                            "",
                            selection: soloPongLoserCupsBinding(for: loserId)
                        ) {
                            ForEach(0...10, id: \.self) { value in
                                Text("\(value)")
                                    .font(AppFont.body)
                                    .tag(value)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .tint(.gray)
                    }
                }

                Text("Winner is locked at 10 cups in solo Pong.")
                    .font(AppFont.footnote)
                    .foregroundStyle(.secondary)

                Text("Last cup: \(displayName(for: pongLastCupByProfileId))")
                    .font(AppFont.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Cup game", selection: $pongCupMode) {
                    ForEach(PongCupMode.allCases) { mode in
                        Text(mode.displayName)
                            .font(AppFont.body)
                            .tag(mode)
                    }
                }
                .font(AppFont.body)
                .pickerStyle(.segmented)
                .onChange(of: pongCupMode) { _, _ in
                    normalizePongCupsToMode()
                }

                Toggle(isOn: $isPongCupBreakdownEnabled) {
                    Text("Add Cup Breakdown")
                        .font(Font.custom("NeueHaasDisplay-Bold", size: 18))
                }
                .toggleStyle(.switch)
                .onChange(of: isPongCupBreakdownEnabled) { _, isEnabled in
                    if !isEnabled {
                        pongCupsByProfileId = [:]
                    } else {
                        syncStatsWithParticipants()
                        normalizePongCupsToMode()
                    }
                }

                if isPongCupBreakdownEnabled {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Winning team")
                            .font(AppFont.subheadlineBold)
                        ForEach(sortedProfileIds(for: selectedWinnerProfileIds), id: \.self) { profileId in
                            HStack(alignment: .center, spacing: 12) {
                                Text("\(displayName(for: profileId)): \(pongCupsByProfileId[profileId] ?? 0) cups")
                                    .font(AppFont.body)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                let maxAllowed = pongAllowedMax(for: profileId)
                                Picker("", selection: pongCupsBinding(for: profileId)) {
                                    ForEach(0...maxAllowed, id: \.self) { value in
                                        Text("\(value)")
                                            .font(AppFont.body)
                                            .tag(value)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .tint(.gray)
                            }
                        }
                        Text("Team total: \(pongWinnersTotalCups) / \(pongCupMode.rawValue)")
                            .font(AppFont.footnote)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Losing team")
                            .font(AppFont.subheadlineBold)
                        ForEach(sortedProfileIds(for: selectedLoserProfileIds), id: \.self) { profileId in
                            HStack(alignment: .center, spacing: 12) {
                                Text("\(displayName(for: profileId)): \(pongCupsByProfileId[profileId] ?? 0) cups")
                                    .font(AppFont.body)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                let maxAllowed = pongAllowedMax(for: profileId)
                                Picker("", selection: pongCupsBinding(for: profileId)) {
                                    ForEach(0...maxAllowed, id: \.self) { value in
                                        Text("\(value)")
                                            .font(AppFont.body)
                                            .tag(value)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .tint(.gray)
                            }
                        }
                        Text("Team total: \(pongLosersTotalCups) / \(pongCupMode.rawValue)")
                            .font(AppFont.footnote)
                            .foregroundStyle(.secondary)
                    }

                }

                Picker("Last cup by", selection: $pongLastCupByProfileId) {
                    Text("None")
                        .font(AppFont.body)
                        .tag("")
                    ForEach(Array(selectedWinnerProfileIds).sorted(), id: \.self) { winnerId in
                        Text(displayName(for: winnerId))
                            .font(AppFont.body)
                            .tag(winnerId)
                    }
                }
                .font(AppFont.body)
            }
        }
    }

    private func soloPongLoserCupsBinding(for profileId: String) -> Binding<Int> {
        Binding<Int>(
            get: { pongCupsByProfileId[profileId] ?? 0 },
            set: { newValue in
                let clamped = max(0, min(newValue, 10))
                pongCupsByProfileId[profileId] = clamped
                if let winnerId = soloWinnerProfileId {
                    pongCupsByProfileId[winnerId] = 10
                }
            }
        )
    }

    private func pongCupsBinding(for profileId: String) -> Binding<Int> {
        Binding<Int>(
            get: { pongCupsByProfileId[profileId] ?? 0 },
            set: { newValue in
                let clamped = max(0, newValue)
                let totalOther = pongTeamTotal(excluding: profileId)
                let cap = pongCupMode.rawValue
                let remaining = max(0, cap - totalOther)
                let allowedMaxForThisPlayer = min(cap, remaining)
                let finalValue = min(clamped, allowedMaxForThisPlayer)
                pongCupsByProfileId[profileId] = finalValue
            }
        )
    }

    private func pongTeamTotal(excluding profileId: String) -> Int {
        let teamIds: Set<String>
        if selectedWinnerProfileIds.contains(profileId) {
            teamIds = selectedWinnerProfileIds
        } else if selectedLoserProfileIds.contains(profileId) {
            teamIds = selectedLoserProfileIds
        } else {
            teamIds = []
        }
        return teamIds.reduce(0) { total, id in
            if id == profileId { return total }
            return total + (pongCupsByProfileId[id] ?? 0)
        }
    }

    private func pongAllowedMax(for profileId: String) -> Int {
        let cap = pongCupMode.rawValue
        let remaining = max(0, cap - pongTeamTotal(excluding: profileId))
        return min(cap, remaining)
    }

    private func normalizePongCupsToMode() {
        let cap = pongCupMode.rawValue
        // 1) Clamp each player to [0, cap]
        for id in participantProfileIds {
            pongCupsByProfileId[id] = min(max(0, pongCupsByProfileId[id] ?? 0), cap)
        }
        normalizePongTeamToMode(teamIds: selectedWinnerProfileIds, cap: cap)
        normalizePongTeamToMode(teamIds: selectedLoserProfileIds, cap: cap)
    }

    private func normalizePongTeamToMode(teamIds: Set<String>, cap: Int) {
        var total = teamIds.reduce(0) { $0 + (pongCupsByProfileId[$1] ?? 0) }
        guard total > cap else { return }
        let ids = teamIds.sorted()
        // Reduce from the end (stable, deterministic) until the team total fits.
        while total > cap {
            var reducedAny = false
            for id in ids.reversed() {
                let v = pongCupsByProfileId[id] ?? 0
                guard v > 0, total > cap else { continue }
                pongCupsByProfileId[id] = v - 1
                total -= 1
                reducedAny = true
                if total <= cap { break }
            }
            if !reducedAny { break }
        }
    }

    private func sortedProfileIds(for ids: Set<String>) -> [String] {
        ids.sorted { lhs, rhs in
            displayName(for: lhs).localizedCaseInsensitiveCompare(displayName(for: rhs)) == .orderedAscending
        }
    }

    @ViewBuilder
    private var beerBallStatsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(selectedParticipants, id: \.profileId) { participant in
                Stepper(
                    value: binding(for: participant.profileId, in: $beerBallNewCansByProfileId),
                    in: 0...99
                ) {
                    Text("\(displayName(for: participant.profileId)): \(beerBallNewCansByProfileId[participant.profileId] ?? 0) new cans")
                        .font(AppFont.body)
                }
            }

            Picker("Finished first", selection: $beerBallFirstFinishedByProfileId) {
                Text("None")
                    .font(AppFont.body)
                    .tag("")
                ForEach(selectedParticipants, id: \.profileId) { participant in
                    Text(displayName(for: participant.profileId))
                        .font(AppFont.body)
                        .tag(participant.profileId)
                }
            }
            .font(AppFont.body)
        }
    }

    @ViewBuilder
    private var battlePongStatsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(selectedParticipants, id: \.profileId) { participant in
                Stepper(
                    value: binding(for: participant.profileId, in: $battlePongCupsByProfileId),
                    in: 0...99
                ) {
                    Text("\(displayName(for: participant.profileId)): \(battlePongCupsByProfileId[participant.profileId] ?? 0) cups made")
                        .font(AppFont.body)
                }
            }
        }
    }

    @ViewBuilder
    private var baseballStatsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(selectedParticipants, id: \.profileId) { participant in
                Stepper(
                    value: binding(for: participant.profileId, in: $baseballHitsByProfileId),
                    in: 0...99
                ) {
                    Text("\(displayName(for: participant.profileId)): \(baseballHitsByProfileId[participant.profileId] ?? 0) hits")
                        .font(AppFont.body)
                }
            }
        }
    }

    @ViewBuilder
    private var crossfireStatsView: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(selectedParticipants, id: \.profileId) { participant in
                Stepper(
                    value: crossfireCupsBinding(for: participant.profileId),
                    in: 0...5
                ) {
                    Text("\(displayName(for: participant.profileId)): \(crossfireCupsByProfileId[participant.profileId] ?? 0) cups")
                        .font(AppFont.body)
                }
            }

            Picker("Last cup (optional)", selection: $crossfireLastCupByProfileId) {
                Text("None")
                    .font(AppFont.body)
                    .tag("")
                ForEach(selectedParticipants, id: \.profileId) { participant in
                    Text(displayName(for: participant.profileId))
                        .font(AppFont.body)
                        .tag(participant.profileId)
                }
            }
            .font(AppFont.body)
        }
    }

    private var canSubmitGameLog: Bool {
        !selectedCommunityId.isEmpty &&
        (outcome != nil || isEditingExistingLog) &&
        participantSelectionMatchesExpectedTeamSizes &&
        hasRequiredPhotos &&
        currentStatsValidationError == nil &&
        (!isBracketLinked || currentUserIsGameMember || isEditingExistingLog)
    }

    private var canSubmitWithoutPhotos: Bool {
        !selectedCommunityId.isEmpty &&
        (outcome != nil || isEditingExistingLog) &&
        participantSelectionMatchesExpectedTeamSizes &&
        currentStatsValidationError == nil &&
        (!isBracketLinked || currentUserIsGameMember || isEditingExistingLog)
    }

    private var submitDisableReasons: [String] {
        var reasons: [String] = []
        let needsNewCapture = frontPhotoData == nil || backPhotoData == nil
        if needsNewCapture, !isEditingExistingLog || photoUrls.isEmpty {
            reasons.append("Photos are required and will be captured when you submit")
        }
        if !participantSelectionMatchesExpectedTeamSizes {
            reasons.append(
                isBracketLinked
                    ? "Winners and losers must match the bracket matchup’s two sides"
                    : "Winners and losers must each equal team size"
            )
        }
        if !isLoggingCustomGame, selectedGameType == .pong, teamSize > 1, isPongCupBreakdownEnabled {
            let hasAnyPongCups = pongTotalCups > 0
            if hasAnyPongCups, pongWinnersTotalCups != pongCupMode.rawValue {
                reasons.append("Winning team cups must equal \(pongCupMode.rawValue)")
            }
        }
        if !selectedMVPProfileId.isEmpty &&
            !selectedLVPProfileId.isEmpty &&
            selectedMVPProfileId == selectedLVPProfileId {
            reasons.append("MVP and LVP must be different players")
        }
        return reasons
    }

    private var currentUserId: String? {
        if UITestRuntime.participatesInUiTestHarness {
            return container.authService.currentUserId ?? UITestRuntime.currentUserIdFallback ?? "ui-test-user"
        }
        return container.authService.currentUserId
            ?? UITestRuntime.currentUserIdFallback
            ?? Auth.auth().currentUser?.uid
    }

    /// In bracket-linked flows, only a user who is actually one of the match participants may submit.
    private var currentUserIsGameMember: Bool {
        guard let myUserId = currentUserId else { return false }
        guard isBracketLinked else { return true }
        return bracketParticipantProfileIdsInOrder.contains(myUserId)
    }

    private var hasRequiredPhotos: Bool {
        (frontPhotoData != nil && backPhotoData != nil) || !photoUrls.isEmpty
    }

    private var participantProfileIds: [String] {
        Array(selectedWinnerProfileIds.union(selectedLoserProfileIds)).sorted()
    }

    private var selectedParticipants: [CommunityMemberRosterRow] {
        participantProfileIds.map { id in
            members.first { $0.profileId == id }
                ?? CommunityMemberRosterRow(
                    profileId: id,
                    displayName: "Unknown",
                    profilePhotoUrl: nil,
                    communityOdds: 0,
                    communityGamesPlayed: 0
                )
        }
    }

    private var shouldShowDetailsSection: Bool {
        guard !participantProfileIds.isEmpty else { return false }
        return true
    }

    private var shouldShowPostSelectionSections: Bool {
        if isOperatorNeutralEdit {
            return participantSelectionMatchesExpectedTeamSizes
        }
        guard let outcome else { return false }
        guard !selectedOpponentSet(for: outcome).isEmpty else { return false }
        if teamSize == 1 {
            return true
        }
        if bracketTeamsAreFixed {
            return true
        }
        guard let myUserId = currentUserId else { return false }
        return selectedTeammateSet(for: outcome).contains { $0 != myUserId }
    }

    private func selectedTeammateSet(for outcome: Outcome) -> Set<String> {
        outcome == .won ? selectedWinnerProfileIds : selectedLoserProfileIds
    }

    private func selectedOpponentSet(for outcome: Outcome) -> Set<String> {
        outcome == .won ? selectedLoserProfileIds : selectedWinnerProfileIds
    }

    private var pongTotalCups: Int {
        participantProfileIds.reduce(0) { $0 + (pongCupsByProfileId[$1] ?? 0) }
    }

    private var pongWinnersTotalCups: Int {
        selectedWinnerProfileIds.reduce(0) { $0 + (pongCupsByProfileId[$1] ?? 0) }
    }

    private var pongLosersTotalCups: Int {
        selectedLoserProfileIds.reduce(0) { $0 + (pongCupsByProfileId[$1] ?? 0) }
    }

    private var currentStatsValidationError: String? {
        let participantSet = Set(participantProfileIds)
        guard !participantSet.isEmpty else { return nil }
        if isLoggingCustomGame {
            // No type-specific stat requirements; optional detail lives in Notes.
        } else {
        switch selectedGameType {
        case .pong:
            if teamSize == 1 {
                guard let soloWinnerProfileId, participantSet.contains(soloWinnerProfileId) else {
                    return "Winner must be selected for solo Pong."
                }
                // In solo mode, enforce fixed defaults.
                if pongCupMode != .ten { return "Solo Pong must use 10-cup mode." }
                if pongLastCupByProfileId != soloWinnerProfileId {
                    return "Solo Pong last cup must be the winner."
                }
                break
            }
            if isPongCupBreakdownEnabled {
                // Allow "unset" cup counts (all zeros). Once the user enters any cups,
                // require the winning team total to match the selected cup mode.
                if pongTotalCups > 0 {
                    if pongWinnersTotalCups != pongCupMode.rawValue {
                        return "Winning team cups must add up to \(pongCupMode.rawValue)."
                    }
                }
            }
            if !pongLastCupByProfileId.isEmpty && !selectedWinnerProfileIds.contains(pongLastCupByProfileId) {
                return "Last cup must be selected from the winning team."
            }
        case .beerBall:
            if !beerBallFirstFinishedByProfileId.isEmpty && !participantSet.contains(beerBallFirstFinishedByProfileId) {
                return "Finished-first player must be one of the selected participants."
            }
        case .battlePong, .baseball:
            break
        case .crossfire:
            for id in participantProfileIds {
                let n = crossfireCupsByProfileId[id] ?? 0
                if n < 0 || n > 5 {
                    return "Crossfire cups must be between 0 and 5 per player."
                }
            }
            if !crossfireLastCupByProfileId.isEmpty {
                if !participantSet.contains(crossfireLastCupByProfileId) {
                    return "Last cup must be one of the selected participants."
                }
                if (crossfireCupsByProfileId[crossfireLastCupByProfileId] ?? 0) < 1 {
                    return "Last cup player must have at least 1 cup made."
                }
            }
        }
        }
        if !selectedMVPProfileId.isEmpty && !participantSet.contains(selectedMVPProfileId) {
            return "MVP must be one of the selected participants."
        }
        if !selectedLVPProfileId.isEmpty && !participantSet.contains(selectedLVPProfileId) {
            return "LVP must be one of the selected participants."
        }
        if !selectedMVPProfileId.isEmpty &&
            !selectedLVPProfileId.isEmpty &&
            selectedMVPProfileId == selectedLVPProfileId {
            return "MVP and LVP must be different players."
        }
        return nil
    }

    private func validTeamSizeRange(for gameType: GameType) -> ClosedRange<Int> {
        gameType.leagueRankingBasis.validTeamSizeRange(memberCount: members.count)
    }

    private func isGameTypeAvailable(_ gameType: GameType) -> Bool {
        let cap = max(1, members.count / 2)
        return cap >= gameType.leagueRankingBasis.baseTeamSizeRange.lowerBound
    }

    private var unavailableGameTypeMessage: String {
        let minimumTeamSize = selectedGameType.leagueRankingBasis.baseTeamSizeRange.lowerBound
        let minimumLeagueMembers = minimumTeamSize * 2
        return "League doesn’t have enough members for \(selectedGameType.displayName). This game needs at least \(minimumLeagueMembers) league members (\(minimumTeamSize)v\(minimumTeamSize))."
    }

    private func firstAvailableGameType() -> GameType {
        GameType.allCases.first(where: isGameTypeAvailable) ?? .pong
    }

    private func resetSelectionForScopeChange(preserveCustomDefinition: Bool = false) {
        // Edit flow sets `selectedCommunityId` / `selectedGameType` from the snapshot; `onChange` would
        // otherwise run and clear restored winners/losers (empty "Winners: —" and a dead swap button).
        guard !isEditingExistingLog else { return }
        if !preserveCustomDefinition {
            selectedCustomDefinitionId = nil
            selectedCustomDefinitionName = ""
        }
        outcome = nil
        selectedWinnerProfileIds.removeAll()
        selectedLoserProfileIds.removeAll()
        participantSelectionRecency.removeAll()
        participantSelectionCounter = 0
        isTeammateDropdownOpen = false
        isOpponentDropdownOpen = false
        teammateQuery = ""
        opponentQuery = ""
        syncStatsWithParticipants()
    }

    private func markParticipantSelectedMostRecently(_ profileId: String) {
        participantSelectionCounter += 1
        participantSelectionRecency[profileId] = participantSelectionCounter
    }

    private func markParticipantDeselected(_ profileId: String) {
        participantSelectionRecency.removeValue(forKey: profileId)
    }

    /// Operator-only: exchange recorded winner and loser sides (same players, flipped result).
    private func swapWinningAndLosingTeams() {
        let w = selectedWinnerProfileIds
        selectedWinnerProfileIds = selectedLoserProfileIds
        selectedLoserProfileIds = w
        if !pongLastCupByProfileId.isEmpty && !selectedWinnerProfileIds.contains(pongLastCupByProfileId) {
            pongLastCupByProfileId = ""
        }
        syncStatsWithParticipants()
    }

    private func syncStatsWithParticipants() {
        let ids = Set(participantProfileIds)

        if !isLoggingCustomGame, selectedGameType == .pong, teamSize > 1, !isPongCupBreakdownEnabled {
            pongCupsByProfileId = [:]
        } else {
            pongCupsByProfileId = keepOnly(ids: ids, from: pongCupsByProfileId)
        }
        beerBallNewCansByProfileId = keepOnly(ids: ids, from: beerBallNewCansByProfileId)
        battlePongCupsByProfileId = keepOnly(ids: ids, from: battlePongCupsByProfileId)
        baseballHitsByProfileId = keepOnly(ids: ids, from: baseballHitsByProfileId)
        crossfireCupsByProfileId = keepOnly(ids: ids, from: crossfireCupsByProfileId).mapValues { min(5, $0) }

        if !pongLastCupByProfileId.isEmpty && !ids.contains(pongLastCupByProfileId) {
            pongLastCupByProfileId = ""
        }
        if !beerBallFirstFinishedByProfileId.isEmpty && !ids.contains(beerBallFirstFinishedByProfileId) {
            beerBallFirstFinishedByProfileId = ""
        }
        if !crossfireLastCupByProfileId.isEmpty && !ids.contains(crossfireLastCupByProfileId) {
            crossfireLastCupByProfileId = ""
        }
        if !selectedMVPProfileId.isEmpty && !ids.contains(selectedMVPProfileId) {
            selectedMVPProfileId = ""
        }
        if !selectedLVPProfileId.isEmpty && !ids.contains(selectedLVPProfileId) {
            selectedLVPProfileId = ""
        }

        // Solo Pong defaults: fixed 10-cup mode and last cup = winner.
        if !isLoggingCustomGame, selectedGameType == .pong, teamSize == 1, let winnerId = soloWinnerProfileId {
            isPongCupBreakdownEnabled = true
            pongCupMode = .ten
            pongLastCupByProfileId = winnerId
            pongCupsByProfileId[winnerId] = 10
            if let loserId = selectedLoserProfileIds.first {
                pongCupsByProfileId[loserId] = max(0, min(pongCupsByProfileId[loserId] ?? 0, 10))
            }
        }
    }

    private func prefillPongWinningTeamCupsIfEmpty() {
        guard !isLoggingCustomGame else { return }
        guard selectedGameType == .pong, teamSize > 1, isPongCupBreakdownEnabled else { return }
        guard !selectedWinnerProfileIds.isEmpty else { return }
        guard pongTotalCups == 0 else { return }

        let cap = pongCupMode.rawValue
        let winnerIds = sortedProfileIds(for: selectedWinnerProfileIds)
        guard !winnerIds.isEmpty else { return }

        let base = cap / winnerIds.count
        let remainder = cap % winnerIds.count
        for (idx, id) in winnerIds.enumerated() {
            pongCupsByProfileId[id] = base + (idx < remainder ? 1 : 0)
        }
        // Keep losing team at 0 by default.
    }

    private func keepOnly(ids: Set<String>, from map: [String: Int]) -> [String: Int] {
        var result: [String: Int] = [:]
        for id in ids {
            result[id] = max(0, map[id] ?? 0)
        }
        return result
    }

    private func binding(for profileId: String, in map: Binding<[String: Int]>) -> Binding<Int> {
        Binding<Int>(
            get: { map.wrappedValue[profileId] ?? 0 },
            set: { newValue in
                map.wrappedValue[profileId] = max(0, newValue)
            }
        )
    }

    private func crossfireCupsBinding(for profileId: String) -> Binding<Int> {
        Binding<Int>(
            get: { min(5, max(0, crossfireCupsByProfileId[profileId] ?? 0)) },
            set: { newValue in
                crossfireCupsByProfileId[profileId] = min(5, max(0, newValue))
            }
        )
    }

    private func displayName(for profileId: String) -> String {
        guard let member = members.first(where: { $0.profileId == profileId }) else {
            return "Unknown"
        }
        return member.displayName.isEmpty ? "Unknown" : member.displayName
    }

    private func namesList(for ids: Set<String>) -> String {
        guard !ids.isEmpty else { return "—" }
        // Use roster when present, but still list every id (e.g. admin before members load, or ex-members).
        return sortedProfileIds(for: ids).map { displayName(for: $0) }.joined(separator: ", ")
    }

    private var selectedLeagueNameForSummary: String {
        let resolved = editingResolvedLeagueName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !resolved.isEmpty { return resolved }
        if let name = loggableCommunities.first(where: { $0.communityId == selectedCommunityId })?.name,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        // Operators may edit logs for leagues they’re not a member of (hidden or not in “loggable” list).
        if let name = communities.first(where: { $0.communityId == selectedCommunityId })?.name,
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        return "—"
    }

    private var totalBeerBallNewCans: Int {
        beerBallNewCansByProfileId.values.reduce(0, +)
    }

    private var totalBattlePongCupsMade: Int {
        battlePongCupsByProfileId.values.reduce(0, +)
    }

    private var totalBaseballHits: Int {
        baseballHitsByProfileId.values.reduce(0, +)
    }

    /// Shown in Summary when at least one capture or linked photo exists.
    private var photosSummaryDetailText: String? {
        let hasFront = frontPhotoData != nil
        let hasBack = backPhotoData != nil
        if hasFront && hasBack { return "Photos: Front and back captured" }
        if hasFront || hasBack { return "Photos: One side captured" }
        if !photoUrls.isEmpty { return "Photos: Saved with log" }
        return nil
    }

    private var soloWinnerProfileId: String? {
        teamSize == 1 ? selectedWinnerProfileIds.first : nil
    }

    private func lockUserIntoOutcome() {
        guard let myUserId = currentUserId else { return }
        guard let outcome else { return }

        func resetParticipantSelectionState() {
            selectedWinnerProfileIds.removeAll()
            selectedLoserProfileIds.removeAll()
            participantSelectionRecency.removeAll()
            participantSelectionCounter = 0
        }

        /// Non-bracket (or bracket fallback): lock only the current user on their chosen side.
        func applySoloOutcomeLock() {
            resetParticipantSelectionState()
            switch outcome {
            case .won:
                selectedWinnerProfileIds.insert(myUserId)
            case .lost:
                selectedLoserProfileIds.insert(myUserId)
            }
            markParticipantSelectedMostRecently(myUserId)
        }

        if isBracketLinked && !bracketParticipantProfileIdsInOrder.contains(myUserId) {
            // Outcome buttons are disabled in this state; clear any stale picks if something got out of sync.
            resetParticipantSelectionState()
            return
        }

        // If bracket-linked, the match participant list already contains the full 2-team set.
        // We can deterministically split into "team A / team B" by ordering, then map them
        // onto winners/losers based on whether the user tapped "I won" or "I lost".
        if isBracketLinked, teamSize == 1 {
            let ids = bracketParticipantProfileIdsInOrder
            guard ids.count >= 2 else {
                applySoloOutcomeLock()
                return
            }
            resetParticipantSelectionState()
            let myTeam: [String]
            let otherTeam: [String]
            if ids[0] == myUserId {
                myTeam = [ids[0]]
                otherTeam = [ids[1]]
            } else if ids[1] == myUserId {
                myTeam = [ids[1]]
                otherTeam = [ids[0]]
            } else {
                myTeam = [ids[0]]
                otherTeam = [ids[1]]
            }
            switch outcome {
            case .won:
                selectedWinnerProfileIds = Set(myTeam)
                selectedLoserProfileIds = Set(otherTeam)
            case .lost:
                selectedWinnerProfileIds = Set(otherTeam)
                selectedLoserProfileIds = Set(myTeam)
            }
            for id in myTeam { markParticipantSelectedMostRecently(id) }
            for id in otherTeam { markParticipantSelectedMostRecently(id) }
            return
        }

        if isBracketLinked, teamSize > 1 {
            let ids = bracketParticipantProfileIdsInOrder
            let split = BracketMatchDisplay.splitIndexFirstTeam(n: ids.count, teamSize: teamSize)
            guard ids.count >= 2,
                  BracketMatchDisplay.bracketMatchHasValidTwoSides(n: ids.count, teamSize: teamSize)
            else {
                applySoloOutcomeLock()
                return
            }
            resetParticipantSelectionState()

            let teamA = Array(ids[0..<split])
            let teamB = Array(ids[split...])
            let myIndex = ids.firstIndex(of: myUserId)
            let myTeamIsFirstHalf = myIndex.map { $0 < split } ?? true

            let myTeam = myTeamIsFirstHalf ? teamA : teamB
            let otherTeam = myTeamIsFirstHalf ? teamB : teamA

            switch outcome {
            case .won:
                selectedWinnerProfileIds = Set(myTeam)
                selectedLoserProfileIds = Set(otherTeam)
            case .lost:
                selectedWinnerProfileIds = Set(otherTeam)
                selectedLoserProfileIds = Set(myTeam)
            }

            // Ensure no overlap even if Firestore ordering is imperfect.
            selectedWinnerProfileIds.subtract(selectedLoserProfileIds)
            selectedLoserProfileIds.subtract(selectedWinnerProfileIds)

            // Recency: treat auto-filled players as selected in order.
            for id in (outcome == .won ? myTeam : otherTeam) { markParticipantSelectedMostRecently(id) }
            for id in (outcome == .won ? otherTeam : myTeam) { markParticipantSelectedMostRecently(id) }
            return
        }

        applySoloOutcomeLock()
    }

    private func toggleTeammate(profileId: String, isSelected: Bool) {
        guard !bracketTeamsAreFixed else { return }
        guard let myUserId = currentUserId else { return }
        guard profileId != myUserId else { return }
        guard let outcome else { return }

        let isMySideWinners = (outcome == .won)
        let currentSet = isMySideWinners ? selectedWinnerProfileIds : selectedLoserProfileIds

        if isSelected {
            if isMySideWinners { selectedWinnerProfileIds.remove(profileId) }
            else { selectedLoserProfileIds.remove(profileId) }
            markParticipantDeselected(profileId)
        } else {
            guard currentSet.count < teamSize else { return }
            if isMySideWinners {
                selectedWinnerProfileIds.insert(profileId)
                selectedLoserProfileIds.remove(profileId)
            } else {
                selectedLoserProfileIds.insert(profileId)
                selectedWinnerProfileIds.remove(profileId)
            }
            markParticipantSelectedMostRecently(profileId)
        }
        selectedWinnerProfileIds.subtract(selectedLoserProfileIds)
        selectedLoserProfileIds.subtract(selectedWinnerProfileIds)

        // Keep the dropdown open even when selection reaches team size,
        // so users can immediately swap picks without reopening.
    }

    private func toggleOpponent(profileId: String, isSelected: Bool) {
        guard !bracketTeamsAreFixed else { return }
        guard let myUserId = currentUserId else { return }
        guard profileId != myUserId else { return }
        guard let outcome else { return }

        let opponentsAreLosers = (outcome == .won)
        let currentSet = opponentsAreLosers ? selectedLoserProfileIds : selectedWinnerProfileIds

        if isSelected {
            if opponentsAreLosers { selectedLoserProfileIds.remove(profileId) }
            else { selectedWinnerProfileIds.remove(profileId) }
            markParticipantDeselected(profileId)
        } else {
            guard currentSet.count < teamSize else { return }
            if opponentsAreLosers {
                selectedLoserProfileIds.insert(profileId)
                selectedWinnerProfileIds.remove(profileId)
            } else {
                selectedWinnerProfileIds.insert(profileId)
                selectedLoserProfileIds.remove(profileId)
            }
            markParticipantSelectedMostRecently(profileId)
        }
        selectedWinnerProfileIds.subtract(selectedLoserProfileIds)
        selectedLoserProfileIds.subtract(selectedWinnerProfileIds)

        // Keep the dropdown open even when selection reaches team size,
        // so users can immediately swap picks without reopening.
    }

    private func submitGameLog() async {
        let t0 = Date()
        await MainActor.run {
            submitErrorMessage = nil
            showOpenSettingsAction = false
        }
        guard canSubmitGameLog else { return }
        guard currentUserId != nil else {
            await MainActor.run {
                submitErrorMessage = "Sign in again, then try submitting."
            }
            return
        }
        let loggingCustom = isLoggingCustomGame
        AppDebugLog.log(
            "submitGameLog: start editing=\(isEditingExistingLog) bracketLinked=\(isBracketLinked) communityId=\(selectedCommunityId) teamSize=\(teamSize) gameType=\(loggingCustom ? "CUSTOM" : selectedGameType.rawValue) customDef=\(selectedCustomDefinitionId ?? "nil") bracketId=\(bracketContext?.bracketId ?? "nil") bracketMatchId=\(bracketContext?.bracketMatchId ?? "nil")"
        )
        let participants = participantProfileIds
        let winners = Array(selectedWinnerProfileIds).sorted()
        let losers = Array(selectedLoserProfileIds).sorted()
        guard !participants.isEmpty else {
            await MainActor.run {
                submitErrorMessage = "Select participants before submitting."
            }
            return
        }

        let gameLogService = container.gameLogService
        let pongStats = !loggingCustom && selectedGameType == .pong ? buildPongStats() : nil
        let beerBallStats = !loggingCustom && selectedGameType == .beerBall ? buildBeerBallStats() : nil
        let battlePongStats = !loggingCustom && selectedGameType == .battlePong ? buildBattlePongStats() : nil
        let baseballStats = !loggingCustom && selectedGameType == .baseball ? buildBaseballStats() : nil
        let crossfireStats = !loggingCustom && selectedGameType == .crossfire ? buildCrossfireStats() : nil
        let trimmedNotes = gameLogNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let notesPayload: String? = trimmedNotes.isEmpty ? nil : trimmedNotes

        if let editId = editingGameLogId {
            await MainActor.run { isSubmitting = true }
            defer { Task { @MainActor in isSubmitting = false } }
            do {
                var finalPhotoUrls = photoUrls
                if let frontData = frontPhotoData,
                   let backData = backPhotoData,
                   let combinedPhotoData = makeCombinedPhotoData(frontData: frontData, backData: backData) {
                    AppDebugLog.log("submitGameLog: edit upload gameLogId=\(editId)")
                    let combinedUrl = try await gameLogService.uploadGamePhoto(
                        communityId: selectedCommunityId,
                        gameLogId: editId,
                        side: "combined",
                        data: combinedPhotoData,
                        contentType: "image/jpeg"
                    )
                    finalPhotoUrls = [combinedUrl]
                }
                guard finalPhotoUrls.count == 1 else {
                    await MainActor.run {
                        submitErrorMessage = "Game photos must be saved as a single combined image."
                    }
                    return
                }
                let updatePayload = GameLogUpdatePayload(
                    gameLogId: editId,
                    participantProfileIds: participants,
                    winnerProfileIds: winners,
                    loserProfileIds: losers,
                    mvpProfileId: selectedMVPProfileId.isEmpty ? nil : selectedMVPProfileId,
                    lvpProfileId: selectedLVPProfileId.isEmpty ? nil : selectedLVPProfileId,
                    photoUrls: finalPhotoUrls,
                    notes: notesPayload,
                    pongStats: pongStats,
                    beerBallStats: beerBallStats,
                    battlePongStats: battlePongStats,
                    baseballStats: baseballStats,
                    crossfireStats: crossfireStats
                )
                if sessionManager.isPlatformAdmin {
                    try await container.platformAdminService.adminUpdateGameLog(payload: updatePayload)
                    AppDebugLog.log("submitGameLog: adminUpdateGameLog success ms=\(Int(Date().timeIntervalSince(t0) * 1000))")
                } else {
                    try await gameLogService.updateGameLog(payload: updatePayload)
                    AppDebugLog.log("submitGameLog: updateGameLog success ms=\(Int(Date().timeIntervalSince(t0) * 1000))")
                }
                await MainActor.run { dismiss() }
            } catch {
                await MainActor.run {
                    submitErrorMessage = error.localizedDescription
                }
                let ns = error as NSError
                AppDebugLog.log(
                    "submitGameLog update failed ms=\(Int(Date().timeIntervalSince(t0) * 1000)) domain=\(ns.domain) code=\(ns.code) message=\(ns.localizedDescription)"
                )
            }
            return
        }

        guard let frontData = frontPhotoData, let backData = backPhotoData else {
            await MainActor.run {
                submitErrorMessage = "Capture both front and back photos before submitting."
            }
            return
        }
        AppDebugLog.log(
            "submitGameLog: inputs participants=\(participants.count) winners=\(winners.count) losers=\(losers.count) frontBytes=\(frontData.count) backBytes=\(backData.count)"
        )
        guard let combinedPhotoData = makeCombinedPhotoData(frontData: frontData, backData: backData) else {
            await MainActor.run {
                submitErrorMessage = "Could not combine front and back photos. Please retake and try again."
            }
            return
        }
        if loggingCustom {
            let defId = selectedCustomDefinitionId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !defId.isEmpty else {
                await MainActor.run {
                    submitErrorMessage = "Pick a league custom game before submitting."
                }
                return
            }
        }
        AppDebugLog.log("submitGameLog: combinedPhotoBytes=\(combinedPhotoData.count)")

        let gameLogId = AppFirestore.db().collection("gameLogs").document().documentID
        let communityId = selectedCommunityId
        let gameTypeRaw = loggingCustom ? "CUSTOM" : selectedGameType.rawValue
        let customDefIdForCreate: String? = loggingCustom
            ? selectedCustomDefinitionId?.trimmingCharacters(in: .whitespacesAndNewlines)
            : nil
        let customDefNameTrimmed = selectedCustomDefinitionName.trimmingCharacters(in: .whitespacesAndNewlines)
        let customDefNameForCreate: String? = loggingCustom && !customDefNameTrimmed.isEmpty
            ? String(customDefNameTrimmed.prefix(80))
            : nil

        await MainActor.run { isSubmitting = true }
        defer { Task { @MainActor in isSubmitting = false } }

        guard let authUid = Auth.auth().currentUser?.uid else {
            await MainActor.run {
                submitErrorMessage = "Sign in again, then try submitting."
            }
            return
        }

        do {
            AppDebugLog.log("submitGameLog: upload start gameLogId=\(gameLogId) path=gamePhotos/\(communityId)/\(gameLogId)/combined_*.jpg")
            let combinedUrl = try await gameLogService.uploadGamePhoto(
                communityId: communityId,
                gameLogId: gameLogId,
                side: "combined",
                data: combinedPhotoData,
                contentType: "image/jpeg"
            )
            AppDebugLog.log(
                "submitGameLog: upload success ms=\(Int(Date().timeIntervalSince(t0) * 1000)) urlHost=\(URL(string: combinedUrl)?.host ?? "nil")"
            )

            let payload = GameLogCreatePayload(
                gameLogId: gameLogId,
                communityId: communityId,
                bracketId: bracketContext?.bracketId,
                bracketMatchId: bracketContext?.bracketMatchId,
                gameType: gameTypeRaw,
                customGameDefinitionId: customDefIdForCreate,
                customGameDefinitionName: customDefNameForCreate,
                createdByProfileId: authUid,
                participantProfileIds: participants,
                winnerProfileIds: winners,
                loserProfileIds: losers,
                mvpProfileId: selectedMVPProfileId.isEmpty ? nil : selectedMVPProfileId,
                lvpProfileId: selectedLVPProfileId.isEmpty ? nil : selectedLVPProfileId,
                photoUrls: [combinedUrl],
                notes: notesPayload,
                pongStats: pongStats,
                beerBallStats: beerBallStats,
                battlePongStats: battlePongStats,
                baseballStats: baseballStats,
                crossfireStats: crossfireStats
            )
            AppDebugLog.log(
                "submitGameLog: createGameLog start gameLogId=\(gameLogId) bracketLinked=\(isBracketLinked) bracketId=\(payload.bracketId ?? "nil") bracketMatchId=\(payload.bracketMatchId ?? "nil") photoUrls=\(payload.photoUrls.count)"
            )
            try await gameLogService.createGameLog(payload: payload)
            AppDebugLog.log("submitGameLog: createGameLog success ms=\(Int(Date().timeIntervalSince(t0) * 1000))")
            await MainActor.run {
                dismiss()
            }
        } catch {
            await MainActor.run {
                submitErrorMessage = error.localizedDescription
            }
            let ns = error as NSError
            AppDebugLog.log(
                "submitGameLog failed ms=\(Int(Date().timeIntervalSince(t0) * 1000)) domain=\(ns.domain) code=\(ns.code) message=\(ns.localizedDescription)"
            )
        }
    }

    private func handleSubmitTapped() async {
        submitErrorMessage = nil
        showOpenSettingsAction = false
        AppDebugLog.log(
            "handleSubmitTapped: bracketLinked=\(isBracketLinked) canSubmitWithoutPhotos=\(canSubmitWithoutPhotos) hasRequiredPhotos=\(hasRequiredPhotos) currentUserIsGameMember=\(currentUserIsGameMember)"
        )

        if isEditingExistingLog && hasRequiredPhotos {
            await submitGameLog()
            return
        }

        if isBracketLinked && !currentUserIsGameMember {
            submitErrorMessage = "Only participants can log this match."
            return
        }

        guard canSubmitWithoutPhotos else {
            submitErrorMessage = "Complete required game details before submitting."
            return
        }

        if !hasRequiredPhotos {
            let status = await CameraPermissionCoordinator.ensureVideoPermission()
            AppDebugLog.log("handleSubmitTapped: cameraPermission=\(status)")
            switch status {
            case .authorized:
                submitAfterCapture = true
                showDualCapture = true
            case .denied, .restricted:
                submitErrorMessage = "Camera access is required to submit a game. Enable access in Settings."
                showOpenSettingsAction = true
            case .cameraUnavailable:
                // Capture flow falls back to photo library if camera is unavailable.
                submitAfterCapture = true
                showDualCapture = true
            }
            return
        }

        await submitGameLog()
    }

    private func buildPongStats() -> [String: Any] {
        var stats: [String: Any] = [
            "cupMode": pongCupMode.rawValue,
            "playerCupsHit": isPongCupBreakdownEnabled ? pongCupsByProfileId : [:]
        ]
        if !pongLastCupByProfileId.isEmpty {
            stats["lastCupByProfileId"] = pongLastCupByProfileId
        }
        return stats
    }

    private func buildBeerBallStats() -> [String: Any] {
        var stats: [String: Any] = [
            "newCanCountByProfileId": beerBallNewCansByProfileId
        ]
        if !beerBallFirstFinishedByProfileId.isEmpty {
            stats["firstFinishedByProfileId"] = beerBallFirstFinishedByProfileId
        }
        return stats
    }

    private func buildBattlePongStats() -> [String: Any] {
        ["playerCupsHit": battlePongCupsByProfileId]
    }

    private func makeCombinedPhotoData(frontData: Data, backData: Data) -> Data? {
        guard let frontImage = UIImage(data: frontData), let backImage = UIImage(data: backData) else {
            return nil
        }

        // Normalize both images to the same height, then place side-by-side.
        let targetHeight = max(frontImage.size.height, backImage.size.height)
        let resizedFront = resized(image: frontImage, targetHeight: targetHeight)
        let resizedBack = resized(image: backImage, targetHeight: targetHeight)
        let combinedSize = CGSize(width: resizedFront.size.width + resizedBack.size.width, height: targetHeight)

        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: combinedSize, format: format)
        let combinedImage = renderer.image { _ in
            UIColor.black.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: combinedSize)).fill()
            resizedFront.draw(in: CGRect(origin: .zero, size: resizedFront.size))
            resizedBack.draw(in: CGRect(
                x: resizedFront.size.width,
                y: 0,
                width: resizedBack.size.width,
                height: resizedBack.size.height
            ))
        }
        return combinedImage.jpegData(compressionQuality: 0.85)
    }

    private func resized(image: UIImage, targetHeight: CGFloat) -> UIImage {
        guard image.size.height > 0, image.size.height != targetHeight else { return image }
        let scale = targetHeight / image.size.height
        let targetSize = CGSize(width: image.size.width * scale, height: targetHeight)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private func buildBaseballStats() -> [String: Any] {
        ["hitsByProfileId": baseballHitsByProfileId]
    }

    private func buildCrossfireStats() -> [String: Any] {
        var stats: [String: Any] = ["playerCupsHit": crossfireCupsByProfileId]
        if !crossfireLastCupByProfileId.isEmpty {
            stats["lastCupByProfileId"] = crossfireLastCupByProfileId
        }
        return stats
    }

    /// Full width × fixed height (scaled from feed card photo height); rectangular, no corner radius.
    @ViewBuilder
    private func concatenatedPhotoStrip(front: Data?, back: Data?) -> some View {
        ZStack {
            HStack(spacing: 0) {
                photoStripHalf(data: front)
                photoStripHalf(data: back)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.gameLogPhotoPreviewHeight)

            if front == nil && back == nil {
                Text("No photo")
                    .font(AppFont.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.gameLogPhotoPreviewHeight)
    }

    @ViewBuilder
    private func photoStripHalf(data: Data?) -> some View {
        Group {
            if let data, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .frame(maxHeight: .infinity)
            } else {
                Color(.systemGray5)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
    }

    private func loadExistingGameLogForEditingIfNeeded() async {
        guard let gameLogId = editingGameLogId else { return }
        isLoadingEditDocument = true
        editDocumentLoadError = nil
        editingResolvedLeagueName = ""
        defer { isLoadingEditDocument = false }
        do {
            let snap = try await container.gameLogService.fetchGameLogForEditing(gameLogId: gameLogId)
            let isCreator = container.gameLogService.canCurrentUserEditDelete(createdByProfileId: snap.createdByProfileId)
            guard isCreator || sessionManager.isPlatformAdmin else {
                editDocumentLoadError = "You can only edit games that you logged."
                return
            }
            applyEditableSnapshot(snap)
            if sessionManager.isPlatformAdmin {
                await fetchLeagueNameForOperatorEditSummary(communityId: snap.communityId)
            }
        } catch {
            editDocumentLoadError = error.localizedDescription
        }
    }

    private func fetchLeagueNameForOperatorEditSummary(communityId: String) async {
        let cid = communityId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cid.isEmpty else { return }
        let snap = try? await AppFirestore.db().collection("communities").document(cid).getDocument()
        guard let raw = snap?.data()?["name"] as? String else { return }
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        await MainActor.run { editingResolvedLeagueName = name }
    }

    private func applyEditableSnapshot(_ snap: GameLogEditableSnapshot) {
        selectedCommunityId = snap.communityId
        if snap.gameType == "CUSTOM" {
            selectedCustomDefinitionId = snap.customGameDefinitionId
            let fromDoc = snap.customGameDefinitionName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            selectedCustomDefinitionName = fromDoc
            selectedGameType = .pong
        } else {
            selectedCustomDefinitionId = nil
            selectedCustomDefinitionName = ""
            if let gt = GameType(rawValue: snap.gameType) {
                selectedGameType = gt
            }
        }
        selectedWinnerProfileIds = Set(snap.winnerProfileIds)
        selectedLoserProfileIds = Set(snap.loserProfileIds)
        let w = snap.winnerProfileIds.count
        let l = snap.loserProfileIds.count
        if w > 0, w == l {
            teamSize = w
        } else if w > 0 {
            teamSize = max(1, w)
        }
        selectedMVPProfileId = snap.mvpProfileId ?? ""
        selectedLVPProfileId = snap.lvpProfileId ?? ""
        photoUrls = snap.photoUrls
        gameLogNotes = snap.notes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if isOperatorNeutralEdit {
            // Sentinel for form gates; operator UI does not frame this as the operator’s win/loss.
            outcome = .won
        } else if let uid = currentUserId {
            if snap.winnerProfileIds.contains(uid) {
                outcome = .won
            } else if snap.loserProfileIds.contains(uid) {
                outcome = .lost
            }
        }
        hydrateStatsFromSnapshot(snap)
    }

    private func hydrateStatsFromSnapshot(_ snap: GameLogEditableSnapshot) {
        if let p = snap.pongStats {
            if let mode = p["cupMode"] as? Int, let m = PongCupMode(rawValue: mode) {
                pongCupMode = m
            }
            if let cups = p["playerCupsHit"] as? [String: Int] {
                pongCupsByProfileId = cups
                isPongCupBreakdownEnabled = !cups.isEmpty
            }
            if let last = p["lastCupByProfileId"] as? String {
                pongLastCupByProfileId = last
            }
        }
        if let bb = snap.beerBallStats {
            if let cans = bb["newCanCountByProfileId"] as? [String: Int] {
                beerBallNewCansByProfileId = cans
            }
            if let first = bb["firstFinishedByProfileId"] as? String {
                beerBallFirstFinishedByProfileId = first
            }
        }
        if let bp = snap.battlePongStats, let cups = bp["playerCupsHit"] as? [String: Int] {
            battlePongCupsByProfileId = cups
        }
        if let b = snap.baseballStats, let hits = b["hitsByProfileId"] as? [String: Int] {
            baseballHitsByProfileId = hits
        }
        if let cf = snap.crossfireStats {
            if let cups = cf["playerCupsHit"] as? [String: Int] {
                crossfireCupsByProfileId = cups
            }
            if let last = cf["lastCupByProfileId"] as? String {
                crossfireLastCupByProfileId = last
            }
        }
    }

    private func loadIfNeeded() async {
        guard communities.isEmpty && isLoading else { return }
        await load()
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let page = try await container.communityService.fetchCommunitiesPage(cursor: nil, pageSize: 25)
            communities = page.items
            let loggable = communities.filter { item in
                guard let uid = container.authService.currentUserId else { return !item.hiddenFromMembers }
                return !item.hiddenFromMembers || item.createdByProfileId == uid
            }
            let leagueMissingOrForbidden =
                selectedCommunityId.isEmpty
                || !loggable.contains(where: { $0.communityId == selectedCommunityId })
            // Bracket-linked logs must stay on `bracketContext.communityId` even if that league isn’t in the first page of `fetchCommunitiesPage`.
            if leagueMissingOrForbidden, !isEditingExistingLog, bracketContext == nil {
                selectedCommunityId = loggable.first?.communityId ?? ""
            }
            isLoading = false
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func bracketLockedGameTypeCaption(ctx: GameLogBracketContext) -> String {
        if ctx.bracketGameType == "CUSTOM" {
            let name = ctx.bracketCustomGameDefinitionName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty
                ? "This bracket uses a league custom game."
                : "This bracket uses \(name)."
        }
        if let gt = GameType(rawValue: ctx.bracketGameType) {
            return "This bracket uses \(gt.displayName)."
        }
        return "This bracket uses \(ctx.bracketGameType)."
    }

    /// When logging from a bracket, match type + optional custom definition are fixed by the bracket document.
    private func applyBracketLockedGameTypeIfNeeded() {
        guard let ctx = bracketContext else { return }
        if ctx.bracketGameType == "CUSTOM",
           let cid = ctx.bracketCustomGameDefinitionId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cid.isEmpty {
            selectedCustomDefinitionId = cid
            let n = ctx.bracketCustomGameDefinitionName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            selectedCustomDefinitionName = n
            selectedGameType = .pong
        } else if let gt = GameType(rawValue: ctx.bracketGameType) {
            selectedCustomDefinitionId = nil
            selectedCustomDefinitionName = ""
            selectedGameType = gt
        }
    }

    private func loadCustomGameDefinitions() async {
        let cid = await MainActor.run {
            selectedCommunityId.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !cid.isEmpty else {
            await MainActor.run {
                customGameDefinitions = []
                customDefinitionsError = nil
                isLoadingCustomDefinitions = false
            }
            return
        }
        await MainActor.run {
            isLoadingCustomDefinitions = true
            customDefinitionsError = nil
        }
        do {
            let rows = try await container.communityService.listGameDefinitions(communityId: cid)
            await MainActor.run {
                customGameDefinitions = rows
                isLoadingCustomDefinitions = false
                if let sid = selectedCustomDefinitionId?.trimmingCharacters(in: .whitespacesAndNewlines), !sid.isEmpty,
                   let match = rows.first(where: { $0.gameDefinitionId == sid }) {
                    selectedCustomDefinitionName = match.name
                }
            }
        } catch {
            await MainActor.run {
                customDefinitionsError = error.localizedDescription
                customGameDefinitions = []
                isLoadingCustomDefinitions = false
            }
        }
    }

    private func loadMembers() async {
        guard !selectedCommunityId.isEmpty else { return }
        isMembersLoading = true
        membersErrorMessage = nil
        if UITestRuntime.participatesInUiTestHarness {
            members = uiTestMembers
            if !isLoggingCustomGame, !isGameTypeAvailable(selectedGameType) {
                selectedGameType = firstAvailableGameType()
            }
            let range = currentTeamSizeRange()
            if isBracketLinked, let ctx = bracketContext {
                teamSize = ctx.teamSize
            } else {
                teamSize = min(max(teamSize, range.lowerBound), range.upperBound)
            }
            syncStatsWithParticipants()
            isMembersLoading = false
            if isBracketLinked, outcome != nil {
                lockUserIntoOutcome()
            }
            applyBracketLockedGameTypeIfNeeded()
            return
        }
        do {
            members = try await container.communityService.fetchMembers(communityId: selectedCommunityId)
            if !isLoggingCustomGame, !isGameTypeAvailable(selectedGameType) {
                selectedGameType = firstAvailableGameType()
            }
            let range = currentTeamSizeRange()
            if isBracketLinked, let ctx = bracketContext {
                teamSize = ctx.teamSize
            } else {
                teamSize = min(max(teamSize, range.lowerBound), range.upperBound)
            }
            syncStatsWithParticipants()
        } catch {
            membersErrorMessage = error.localizedDescription
            members = []
        }
        isMembersLoading = false
        if isBracketLinked, outcome != nil {
            lockUserIntoOutcome()
        }
        applyBracketLockedGameTypeIfNeeded()
    }
}

/// White fill, red label and border — primary action on the game log form.
private struct SubmitGameButtonStyle: ButtonStyle {
    private static let submitRed = Color(red: 180.0 / 255.0, green: 61.0 / 255.0, blue: 37.0 / 255.0)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Self.submitRed)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Self.submitRed, lineWidth: 2)
            )
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Same treatment as `FeedPrimaryActionButtonStyle` (feed bottom actions).
private struct BrandPrimaryButtonStyle: ButtonStyle {
    private static let retakeRed = Color(red: 180.0 / 255.0, green: 61.0 / 255.0, blue: 37.0 / 255.0)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Self.retakeRed)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Self.retakeRed, lineWidth: 2)
            )
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private enum PongCupMode: Int, CaseIterable, Identifiable {
    case ten = 10
    case six = 6

    var id: Int { rawValue }

    var displayName: String {
        "\(rawValue)-cup"
    }
}

