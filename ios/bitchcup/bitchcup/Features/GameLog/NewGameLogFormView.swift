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
    /// One point larger than `AppFont.body` (17), medium weight — teammate/opponent picker rows.
    private static let participantPickerRowNameFont = Font.custom("NeueHaasDisplay-Mediu", size: 18)

    /// Background behind the form.
    private static let formBackgroundSoftRed = Color.white
    private static let widgetOutlineColor = Color(.systemGray4)

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var container: DependencyContainer
    @State private var frontPhotoData: Data?
    @State private var backPhotoData: Data?
    @State private var showDualCapture = false

    let bracketContext: GameLogBracketContext?

    private var isBracketLinked: Bool { bracketContext != nil }
    private var bracketParticipantProfileIdsInOrder: [String] {
        bracketContext?.participantProfileIds ?? []
    }
    private var bracketScopedParticipantProfileIds: Set<String> {
        Set(bracketContext?.participantProfileIds ?? [])
    }

    init(
        frontPhotoData: Data? = nil,
        backPhotoData: Data? = nil,
        bracketContext: GameLogBracketContext? = nil
    ) {
        self.bracketContext = bracketContext
        _frontPhotoData = State(initialValue: frontPhotoData)
        _backPhotoData = State(initialValue: backPhotoData)
        _selectedCommunityId = State(initialValue: bracketContext?.communityId ?? "")
        _teamSize = State(initialValue: bracketContext?.teamSize ?? 1)
    }

    @State private var communities: [(communityId: String, name: String)] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    @State private var selectedCommunityId: String = ""
    @State private var selectedGameType: GameType = .pong

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

    /// Three columns so five game types lay out as two rows (3 + 2); avoids single-row segmented truncation.
    private var gameTypeGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: GameLogFormLayout.gameTypeGridSpacing),
            GridItem(.flexible(), spacing: GameLogFormLayout.gameTypeGridSpacing),
            GridItem(.flexible(), spacing: GameLogFormLayout.gameTypeGridSpacing)
        ]
        return LazyVGrid(columns: columns, spacing: GameLogFormLayout.gameTypeGridSpacing) {
            ForEach(GameType.allCases) { type in
                let available = isGameTypeAvailable(type)
                let selected = selectedGameType == type
                Button {
                    guard available else { return }
                    selectedGameType = type
                } label: {
                    Text(type.displayName)
                        .font(AppFont.body)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 6)
                        .foregroundStyle(available ? (selected ? GameLogBrandColor.pillDark : Color.primary) : Color.secondary)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selected && available ? Color.white : Color(UIColor.secondarySystemGroupedBackground))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    selected && available ? GameLogBrandColor.pillDark : Color.primary.opacity(0.12),
                                    lineWidth: 1
                                )
                        }
                }
                .buttonStyle(.plain)
                .disabled(!available)
                .opacity(available ? 1.0 : 0.45)
                .accessibilityLabel(type.displayName)
                .accessibilityAddTraits(selected && available ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Game type")
    }

    @ViewBuilder
    private var gameLogFormSections: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                concatenatedPhotoStrip(front: frontPhotoData, back: backPhotoData)

                HStack {
                    Spacer()
                    if frontPhotoData == nil && backPhotoData == nil {
                        Button {
                            showDualCapture = true
                        } label: {
                            Text("Capture both cameras")
                                .font(AppFont.buttonProminent)
                        }
                        .buttonStyle(.borderedProminent)
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
                ForEach(communities, id: \.communityId) { community in
                    Text(community.name)
                        .font(AppFont.body)
                        .foregroundStyle(.black)
                        .tag(community.communityId)
                }
            } label: {
                Text("League")
                    .font(AppFont.headline)
            }
            .disabled(isBracketLinked)
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
        } header: {
            Text("Choose Game Type")
                .font(Self.widgetTitleFont)
                .foregroundStyle(GameLogBrandColor.red)
        }
        .id(Self.autoPeekChooseGameAnchor)
        .listRowBackground(widgetOutlineBackground)

        Section {
            if isGameTypeAvailable(selectedGameType) {
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
                    .disabled(isBracketLinked && !currentUserIsGameMember)
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
                    .disabled(isBracketLinked && !currentUserIsGameMember)
                    .accessibilityIdentifier("gamelog.outcome.lost")
                }
            } else {
                Text(unavailableGameTypeMessage)
                    .font(AppFont.subheadline)
                    .foregroundStyle(.black)
            }
        } header: {
            Text("Outcome")
                .font(Self.widgetTitleFont)
                .foregroundStyle(GameLogBrandColor.red)
        }
        .listRowBackground(widgetOutlineBackground)

        if outcome != nil {
            Section {
                let range = validTeamSizeRange(for: selectedGameType)
                Stepper(value: $teamSize, in: range, step: 1) {
                    Text("\(teamSize)")
                        .font(AppFont.headline)
                        .foregroundStyle(.black)
                }
                .disabled(isBracketLinked)
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
                                Text("Submitting game log...")
                                    .font(AppFont.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button {
                            Task { await handleSubmitTapped() }
                        } label: {
                            Text("Submit Game")
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
            if isLoading {
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
        .task { await loadIfNeeded() }
        .onChange(of: selectedCommunityId) { _, _ in
            resetSelectionForScopeChange()
            Task { await loadMembers() }
        }
        .onChange(of: selectedGameType) { _, _ in
            let newRange = validTeamSizeRange(for: selectedGameType)
            teamSize = min(max(teamSize, newRange.lowerBound), newRange.upperBound)
            resetSelectionForScopeChange()
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
                    Task { await loadMembers() }
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
            let selectionPoolMembers = isBracketLinked
                ? members.filter { bracketScopedParticipantProfileIds.contains($0.profileId) }
                : members
            let hasEnoughMembers = selectionPoolMembers.count >= (2 * teamSize)
            if let outcome, let myUserId = currentUserId {
                let isMySideWinners = (outcome == .won)
                let teammateSet = isMySideWinners ? selectedWinnerProfileIds : selectedLoserProfileIds
                let opponentSet = isMySideWinners ? selectedLoserProfileIds : selectedWinnerProfileIds

                if !hasEnoughMembers {
                    Section {
                        Text("League doesn’t have enough members for a team of size \(teamSize).")
                            .font(AppFont.subheadline)
                            .foregroundStyle(.black)
                    }
                    .listRowBackground(widgetOutlineBackground)
                }

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
                            members: members.filter { $0.profileId != myUserId }
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
                        members: members.filter { $0.profileId != myUserId }
                    )
                }
                .id(Self.autoPeekOpponentsAnchor)
                .listRowBackground(widgetOutlineBackground)
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
            Text("Game: \(selectedGameType.displayName)")
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
        if !participantProfileIds.isEmpty {
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
        outcome != nil &&
        selectedWinnerProfileIds.count == teamSize &&
        selectedLoserProfileIds.count == teamSize &&
        hasRequiredPhotos &&
        currentStatsValidationError == nil &&
        (!isBracketLinked || currentUserIsGameMember)
    }

    private var canSubmitWithoutPhotos: Bool {
        !selectedCommunityId.isEmpty &&
        outcome != nil &&
        selectedWinnerProfileIds.count == teamSize &&
        selectedLoserProfileIds.count == teamSize &&
        currentStatsValidationError == nil &&
        (!isBracketLinked || currentUserIsGameMember)
    }

    private var submitDisableReasons: [String] {
        var reasons: [String] = []
        if frontPhotoData == nil || backPhotoData == nil {
            reasons.append("Photos are required and will be captured when you submit")
        }
        if selectedWinnerProfileIds.count != teamSize || selectedLoserProfileIds.count != teamSize {
            reasons.append("Winners and losers must each equal team size")
        }
        if selectedGameType == .pong, teamSize > 1, isPongCupBreakdownEnabled {
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
        members.filter { participantProfileIds.contains($0.profileId) }
    }

    private var shouldShowDetailsSection: Bool {
        guard !participantProfileIds.isEmpty else { return false }
        return true
    }

    private var shouldShowPostSelectionSections: Bool {
        guard let outcome else { return false }
        guard !selectedOpponentSet(for: outcome).isEmpty else { return false }
        if teamSize == 1 {
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

    private var leagueTeamSizeCap: Int {
        max(1, members.count / 2)
    }

    private func baseTeamSizeRange(for gameType: GameType) -> ClosedRange<Int> {
        switch gameType {
        case .pong, .beerBall, .crossfire:
            return 1...10
        case .battlePong, .baseball:
            return 3...20
        }
    }

    private func validTeamSizeRange(for gameType: GameType) -> ClosedRange<Int> {
        let base = baseTeamSizeRange(for: gameType)
        let upperBound = min(base.upperBound, leagueTeamSizeCap)
        if upperBound < base.lowerBound {
            return base.lowerBound...base.lowerBound
        }
        return base.lowerBound...upperBound
    }

    private func isGameTypeAvailable(_ gameType: GameType) -> Bool {
        leagueTeamSizeCap >= baseTeamSizeRange(for: gameType).lowerBound
    }

    private var unavailableGameTypeMessage: String {
        let minimumTeamSize = baseTeamSizeRange(for: selectedGameType).lowerBound
        let minimumLeagueMembers = minimumTeamSize * 2
        return "League doesn’t have enough members for \(selectedGameType.displayName). This game needs at least \(minimumLeagueMembers) league members (\(minimumTeamSize)v\(minimumTeamSize))."
    }

    private func firstAvailableGameType() -> GameType {
        GameType.allCases.first(where: isGameTypeAvailable) ?? .pong
    }

    private func resetSelectionForScopeChange() {
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

    private func syncStatsWithParticipants() {
        let ids = Set(participantProfileIds)

        if selectedGameType == .pong, teamSize > 1, !isPongCupBreakdownEnabled {
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
        if selectedGameType == .pong, teamSize == 1, let winnerId = soloWinnerProfileId {
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
        let names = members
            .filter { ids.contains($0.profileId) }
            .map { $0.displayName.isEmpty ? "Unknown" : $0.displayName }
        return names.isEmpty ? "—" : names.joined(separator: ", ")
    }

    private var selectedLeagueNameForSummary: String {
        communities.first { $0.communityId == selectedCommunityId }?.name ?? "—"
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
        selectedWinnerProfileIds.removeAll()
        selectedLoserProfileIds.removeAll()
        participantSelectionRecency.removeAll()
        participantSelectionCounter = 0

        guard let outcome else { return }
        if isBracketLinked && !bracketParticipantProfileIdsInOrder.contains(myUserId) {
            // In bracket-linked flows, only auto-fill if the user is actually one of the match participants.
            return
        }

        // If bracket-linked, the match participant list already contains the full 2-team set.
        // We can deterministically split into "team A / team B" by ordering, then map them
        // onto winners/losers based on whether the user tapped "I won" or "I lost".
        if isBracketLinked, teamSize > 1 {
            let ids = bracketParticipantProfileIdsInOrder
            guard !ids.isEmpty else { return }

            let teamA = Array(ids.prefix(teamSize))
            let teamB = Array(ids.suffix(teamSize))
            let myIndex = ids.firstIndex(of: myUserId)
            let myTeamIsFirstHalf = (myIndex ?? 0) < teamSize

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

        // Solo or non-bracket-linked flows: keep the old behavior of locking just the current user.
        switch outcome {
        case .won:
            selectedWinnerProfileIds.insert(myUserId)
        case .lost:
            selectedLoserProfileIds.insert(myUserId)
        }
        markParticipantSelectedMostRecently(myUserId)
    }

    private func toggleTeammate(profileId: String, isSelected: Bool) {
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
        guard let uid = currentUserId else {
            await MainActor.run {
                submitErrorMessage = "Sign in again, then try submitting."
            }
            return
        }
        AppDebugLog.log(
            "submitGameLog: start bracketLinked=\(isBracketLinked) communityId=\(selectedCommunityId) teamSize=\(teamSize) gameType=\(selectedGameType.rawValue) bracketId=\(bracketContext?.bracketId ?? "nil") bracketMatchId=\(bracketContext?.bracketMatchId ?? "nil")"
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
        AppDebugLog.log("submitGameLog: combinedPhotoBytes=\(combinedPhotoData.count)")

        let gameLogId = AppFirestore.db().collection("gameLogs").document().documentID
        let communityId = selectedCommunityId
        let gameType = selectedGameType
        let pongStats = selectedGameType == .pong ? buildPongStats() : nil
        let beerBallStats = selectedGameType == .beerBall ? buildBeerBallStats() : nil
        let battlePongStats = selectedGameType == .battlePong ? buildBattlePongStats() : nil
        let baseballStats = selectedGameType == .baseball ? buildBaseballStats() : nil
        let crossfireStats = selectedGameType == .crossfire ? buildCrossfireStats() : nil
        let trimmedNotes = gameLogNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let notesPayload: String? = trimmedNotes.isEmpty ? nil : trimmedNotes
        let gameLogService = container.gameLogService

        await MainActor.run { isSubmitting = true }
        defer { Task { @MainActor in isSubmitting = false } }

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
                gameType: gameType.rawValue,
                createdByProfileId: uid,
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
            if selectedCommunityId.isEmpty {
                selectedCommunityId = communities.first?.communityId ?? ""
            }
            isLoading = false
            if !selectedCommunityId.isEmpty {
                Task { await loadMembers() }
            }
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func loadMembers() async {
        guard !selectedCommunityId.isEmpty else { return }
        isMembersLoading = true
        membersErrorMessage = nil
        if UITestRuntime.participatesInUiTestHarness {
            members = uiTestMembers
            if !isGameTypeAvailable(selectedGameType) {
                selectedGameType = firstAvailableGameType()
            }
            let range = validTeamSizeRange(for: selectedGameType)
            teamSize = min(max(teamSize, range.lowerBound), range.upperBound)
            syncStatsWithParticipants()
            isMembersLoading = false
            return
        }
        do {
            members = try await container.communityService.fetchMembers(communityId: selectedCommunityId)
            if !isGameTypeAvailable(selectedGameType) {
                selectedGameType = firstAvailableGameType()
            }
            let range = validTeamSizeRange(for: selectedGameType)
            teamSize = min(max(teamSize, range.lowerBound), range.upperBound)
            syncStatsWithParticipants()
        } catch {
            membersErrorMessage = error.localizedDescription
            members = []
        }
        isMembersLoading = false
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

private enum GameType: String, CaseIterable, Identifiable {
    case pong = "PONG"
    case beerBall = "BEER_BALL"
    case battlePong = "BATTLE_PONG"
    case baseball = "BASEBALL"
    case crossfire = "CROSSFIRE"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pong: return "Pong"
        case .beerBall: return "Beer Ball"
        case .battlePong: return "Battle Pong"
        case .baseball: return "Baseball"
        case .crossfire: return "Crossfire"
        }
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

