import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import UIKit

/// Brand reds for the game log form. `formLightRed` is a softer tint than join-flow coral for headers and chips.
private enum GameLogBrandColor {
    static let red = Color(red: 180.0 / 255.0, green: 61.0 / 255.0, blue: 37.0 / 255.0)
    /// Section headers above widgets, in-widget coral labels, league picker accents, opponent chip text/stroke/fill tint.
    static let formLightRed = Color(red: 232.0 / 255.0, green: 162.0 / 255.0, blue: 145.0 / 255.0)
}

struct NewGameLogFormView: View {
    /// `FeedCardView` photo section height; form preview uses the same layout at a smaller scale.
    private static let feedCardPhotoHeight: CGFloat = 500
    private static var gameLogPhotoPreviewHeight: CGFloat { feedCardPhotoHeight * 0.6 }

    /// Teammate/opponent picker list; previously a fixed 260pt — that remains the cap when many people are available.
    private static let participantPickerListMaxHeight: CGFloat = 260
    private static let participantPickerListRowStride: CGFloat = 52
    private static let participantPickerListMinHeight: CGFloat = 52

    /// Background behind the form.
    private static let formBackgroundSoftRed = GameLogBrandColor.red
    private static let widgetOutlineColor = GameLogBrandColor.red

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var container: DependencyContainer
    @State private var frontPhotoData: Data?
    @State private var backPhotoData: Data?
    @State private var showDualCapture = false

    init(frontPhotoData: Data? = nil, backPhotoData: Data? = nil) {
        _frontPhotoData = State(initialValue: frontPhotoData)
        _backPhotoData = State(initialValue: backPhotoData)
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

    // T07.5 stats placeholders (persisted now).
    @State private var pongCupMode: PongCupMode = .ten
    @State private var pongCupsByProfileId: [String: Int] = [:]
    @State private var pongLastCupByProfileId: String = ""

    @State private var beerBallNewCansByProfileId: [String: Int] = [:]
    @State private var beerBallFirstFinishedByProfileId: String = ""

    @State private var battlePongCupsByProfileId: [String: Int] = [:]
    @State private var baseballHitsByProfileId: [String: Int] = [:]

    @State private var gameLogNotes: String = ""

    @State private var submitErrorMessage: String?
    @State private var isSubmitting = false
    @State private var showOpenSettingsAction = false
    @State private var submitAfterCapture = false

    private var widgetOutlineBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white)
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
                Form {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Game Photos")
                                .font(AppFont.title)
                                .foregroundStyle(GameLogBrandColor.red)
                                .frame(maxWidth: .infinity)
                                .multilineTextAlignment(.center)

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
                    }
                    .listRowBackground(widgetOutlineBackground)

                    Section {
                        Picker(selection: $selectedCommunityId) {
                            ForEach(communities, id: \.communityId) { community in
                                Text(community.name)
                                    .font(AppFont.body)
                                    .foregroundStyle(GameLogBrandColor.formLightRed)
                                    .tag(community.communityId)
                            }
                        } label: {
                            Text("League")
                                .font(AppFont.headline)
                        }
                    } header: {
                        Text("Choose league")
                            .font(AppFont.sectionHeader)
                            .foregroundStyle(GameLogBrandColor.formLightRed)
                    }
                    .listRowBackground(widgetOutlineBackground)

                    Section {
                        Picker(selection: $selectedGameType) {
                            ForEach(GameType.allCases) { type in
                                Text(type.displayName)
                                    .font(AppFont.body)
                                    .tag(type)
                            }
                        } label: {
                            Text("Game type")
                                .font(AppFont.headline)
                        }
                        .font(AppFont.body)
                        .pickerStyle(.segmented)
                    } header: {
                        Text("Choose game type")
                            .font(AppFont.sectionHeader)
                            .foregroundStyle(GameLogBrandColor.formLightRed)
                    }
                    .listRowBackground(widgetOutlineBackground)

                    Section {
                        HStack(spacing: 12) {
                            Button {
                                outcome = .won
                                lockUserIntoOutcome()
                            } label: {
                                Text("I won")
                                    .font(AppFont.buttonProminent)
                                    .frame(maxWidth: .infinity)
                            }
                            .foregroundStyle(outcome == .won ? .white : GameLogBrandColor.red)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(outcome == .won ? GameLogBrandColor.red : .white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(GameLogBrandColor.red, lineWidth: 2)
                            )
                            .buttonStyle(.plain)

                            Button {
                                outcome = .lost
                                lockUserIntoOutcome()
                            } label: {
                                Text("I lost")
                                    .font(AppFont.buttonProminent)
                                    .frame(maxWidth: .infinity)
                            }
                            .foregroundStyle(outcome == .lost ? .white : GameLogBrandColor.red)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(outcome == .lost ? GameLogBrandColor.red : .white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(GameLogBrandColor.red, lineWidth: 2)
                            )
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Outcome")
                            .font(AppFont.sectionHeader)
                            .foregroundStyle(GameLogBrandColor.formLightRed)
                    }
                    .listRowBackground(widgetOutlineBackground)

                    Section {
                        let range = teamSizeRange(for: selectedGameType)
                        Stepper(value: $teamSize, in: range, step: 1) {
                            Text("\(teamSize)")
                                .font(AppFont.headline)
                        }
                    } header: {
                        Text("Team size")
                            .font(AppFont.sectionHeader)
                            .foregroundStyle(GameLogBrandColor.formLightRed)
                    }
                    .listRowBackground(widgetOutlineBackground)

                    fillSlotsFormSections

                    Section {
                        statsSectionContent
                    }
                    .listRowBackground(widgetOutlineBackground)

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
                            .font(AppFont.sectionHeader)
                            .foregroundStyle(GameLogBrandColor.formLightRed)
                    }
                    .listRowBackground(widgetOutlineBackground)

                    Section {
                        TextField("Add a note", text: $gameLogNotes)
                            .font(AppFont.body)
                            .textFieldStyle(.roundedBorder)
                    } header: {
                        Text("Notes")
                            .font(AppFont.sectionHeader)
                            .foregroundStyle(GameLogBrandColor.formLightRed)
                    }
                    .listRowBackground(widgetOutlineBackground)

                    Section {
                        summaryWidgetContent
                    } header: {
                        Text("Summary")
                            .font(AppFont.sectionHeader)
                            .foregroundStyle(GameLogBrandColor.formLightRed)
                    }
                    .listRowBackground(widgetOutlineBackground)

                    Section {
                        if !submitDisableReasons.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Missing before submit:")
                                    .font(AppFont.subheadlineBold)
                                    .foregroundStyle(.black)
                                ForEach(submitDisableReasons, id: \.self) { reason in
                                    Text("• \(reason)")
                                        .font(AppFont.subheadlineBold)
                                        .foregroundStyle(.black)
                                }
                            }
                        }
                        if let statsError = currentStatsValidationError {
                            Text(statsError)
                                .foregroundStyle(.red)
                                .font(AppFont.footnote)
                        }
                        if let submitErrorMessage {
                            Text(submitErrorMessage)
                                .foregroundStyle(.red)
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
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Self.formBackgroundSoftRed)
            }
        }
        .task { await loadIfNeeded() }
        .onChange(of: selectedCommunityId) { _, _ in
            resetSelectionForScopeChange()
            Task { await loadMembers() }
        }
        .onChange(of: selectedGameType) { _, _ in
            let newRange = teamSizeRange(for: selectedGameType)
            teamSize = newRange.lowerBound
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
            let hasEnoughMembers = members.count >= (2 * teamSize)
            if let outcome, let myUserId = currentUserId {
                let isMySideWinners = (outcome == .won)
                let teammateSet = isMySideWinners ? selectedWinnerProfileIds : selectedLoserProfileIds
                let opponentSet = isMySideWinners ? selectedLoserProfileIds : selectedWinnerProfileIds

                if !hasEnoughMembers {
                    Section {
                        Text("League doesn’t have enough members for a team of size \(teamSize).")
                            .font(AppFont.subheadline)
                            .foregroundStyle(.red)
                    }
                    .listRowBackground(widgetOutlineBackground)
                }

                if teamSize > 1 {
                    Section {
                        dropdownBlock(
                            title: "Teammates (\(isMySideWinners ? "Winners" : "Losers"))",
                            includeTitleAboveButton: true,
                            selectedCount: teammateSet.count,
                            query: $teammateQuery,
                            isOpen: $isTeammateDropdownOpen,
                            participants: members.filter { $0.profileId != myUserId },
                            onOpposite: opponentSet,
                            onCurrent: teammateSet,
                            oppositeLabel: "Opponents",
                            hasEnoughMembers: hasEnoughMembers
                        ) { profileId, isSelected in
                            toggleTeammate(profileId: profileId, isSelected: isSelected)
                        }
                    }
                    .listRowBackground(widgetOutlineBackground)
                }

                Section {
                    dropdownBlock(
                        title: "Opponents (\(isMySideWinners ? "Losers" : "Winners"))",
                        includeTitleAboveButton: false,
                        buttonTitleForeground: GameLogBrandColor.red,
                        selectedCount: opponentSet.count,
                        query: $opponentQuery,
                        isOpen: $isOpponentDropdownOpen,
                        participants: members.filter { $0.profileId != myUserId },
                        onOpposite: teammateSet,
                        onCurrent: opponentSet,
                        oppositeLabel: "Teammates",
                        hasEnoughMembers: hasEnoughMembers
                    ) { profileId, isSelected in
                        toggleOpponent(profileId: profileId, isSelected: isSelected)
                    }
                } header: {
                    opponentSectionHeaderPills(
                        selectedProfileIds: opponentSet,
                        members: members.filter { $0.profileId != myUserId }
                    )
                }
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
    private func opponentSectionHeaderPills(
        selectedProfileIds: Set<String>,
        members: [CommunityMemberRosterRow]
    ) -> some View {
        let selectedParticipants = members
            .filter { selectedProfileIds.contains($0.profileId) }
            .sorted { lhs, rhs in
                let left = lhs.displayName.isEmpty ? "Unknown" : lhs.displayName
                let right = rhs.displayName.isEmpty ? "Unknown" : rhs.displayName
                return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
            }
        if !selectedParticipants.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(selectedParticipants, id: \.profileId) { member in
                        Text(member.displayName.isEmpty ? "Unknown" : member.displayName)
                            .font(AppFont.footnote)
                            .foregroundStyle(GameLogBrandColor.formLightRed)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(GameLogBrandColor.formLightRed.opacity(0.22))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(GameLogBrandColor.formLightRed, lineWidth: 1)
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
                    .font(AppFont.sectionHeader)
                    .foregroundStyle(GameLogBrandColor.formLightRed)
            }

            Button {
                isOpen.wrappedValue.toggle()
                if isOpen.wrappedValue { query.wrappedValue = "" }
            } label: {
                HStack {
                    if !title.isEmpty {
                        Text(title)
                            .font(AppFont.headline)
                            .foregroundStyle(buttonTitleForeground ?? .primary)
                    }
                    Spacer()
                    Text("\(selectedCount)/\(teamSize)")
                        .font(AppFont.subheadline)
                        .foregroundStyle(GameLogBrandColor.red)
                    Image(systemName: isOpen.wrappedValue ? "chevron.up" : "chevron.down")
                        .foregroundStyle(GameLogBrandColor.red)
                }
            }
            .disabled(!hasEnoughMembers)

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
                                HStack(spacing: 12) {
                                    if onOppositeSide {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.red)
                                    } else {
                                        if isSelected {
                                            Image(systemName: "checkmark.circle.fill")
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(GameLogBrandColor.red, .white)
                                        } else {
                                            Image(systemName: "circle")
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Text(member.displayName.isEmpty ? "Unknown" : member.displayName)
                                        .font(AppFont.body)
                                        .foregroundStyle(.primary)
                                    if onOppositeSide {
                                        Text(oppositeLabel)
                                            .font(AppFont.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(rowDisabled)
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
            Text("Game: \(selectedGameType.displayName)")
                .font(AppFont.subheadlineBold)
            Text("Winners: \(namesList(for: selectedWinnerProfileIds))")
                .font(AppFont.subheadlineBold)
            Text("Losers: \(namesList(for: selectedLoserProfileIds))")
                .font(AppFont.subheadlineBold)

            if !selectedMVPProfileId.isEmpty {
                Text("MVP: \(displayName(for: selectedMVPProfileId))")
                    .font(AppFont.subheadlineBold)
            }
            if !selectedLVPProfileId.isEmpty {
                Text("LVP: \(displayName(for: selectedLVPProfileId))")
                    .font(AppFont.subheadlineBold)
            }

            summaryStatsDetailContent
        }
        .foregroundStyle(GameLogBrandColor.red)
    }

    @ViewBuilder
    private var summaryStatsDetailContent: some View {
        if !participantProfileIds.isEmpty {
            switch selectedGameType {
            case .pong:
                if teamSize > 1 {
                    Text("Cup game: \(pongCupMode.displayName)")
                        .font(AppFont.subheadlineBold)
                    ForEach(participantProfileIds.sorted(), id: \.self) { profileId in
                        let cups = pongCupsByProfileId[profileId] ?? 0
                        if cups > 0 {
                            Text("\(displayName(for: profileId)): \(cups) cups")
                                .font(AppFont.subheadlineBold)
                        }
                    }
                    if !pongLastCupByProfileId.isEmpty {
                        Text("Last cup: \(displayName(for: pongLastCupByProfileId))")
                            .font(AppFont.subheadlineBold)
                    }
                } else if soloWinnerProfileId != nil {
                    Text("Pong: Solo \(pongCupMode.displayName)")
                        .font(AppFont.subheadlineBold)
                    if !pongLastCupByProfileId.isEmpty {
                        Text("Last cup: \(displayName(for: pongLastCupByProfileId))")
                            .font(AppFont.subheadlineBold)
                    }
                }
            case .beerBall:
                ForEach(participantProfileIds.sorted(), id: \.self) { profileId in
                    let n = beerBallNewCansByProfileId[profileId] ?? 0
                    if n > 0 {
                        Text("\(displayName(for: profileId)): \(n) new cans")
                            .font(AppFont.subheadlineBold)
                    }
                }
                if !beerBallFirstFinishedByProfileId.isEmpty {
                    Text("Finished first: \(displayName(for: beerBallFirstFinishedByProfileId))")
                        .font(AppFont.subheadlineBold)
                }
            case .battlePong:
                ForEach(participantProfileIds.sorted(), id: \.self) { profileId in
                    let n = battlePongCupsByProfileId[profileId] ?? 0
                    if n > 0 {
                        Text("\(displayName(for: profileId)): \(n) cups made")
                            .font(AppFont.subheadlineBold)
                    }
                }
            case .baseball:
                ForEach(participantProfileIds.sorted(), id: \.self) { profileId in
                    let n = baseballHitsByProfileId[profileId] ?? 0
                    if n > 0 {
                        Text("\(displayName(for: profileId)): \(n) hits")
                            .font(AppFont.subheadlineBold)
                    }
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
            }
        }
    }

    @ViewBuilder
    private var pongStatsView: some View {
        if teamSize == 1 {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Cup game", selection: $pongCupMode) {
                    ForEach(PongCupMode.allCases) { mode in
                        Text(mode.displayName)
                            .font(AppFont.body)
                            .tag(mode)
                    }
                }
                .font(AppFont.body)
                .pickerStyle(.segmented)

                ForEach(selectedParticipants, id: \.profileId) { participant in
                    Stepper(
                        value: binding(for: participant.profileId, in: $pongCupsByProfileId),
                        in: 0...pongCupMode.rawValue
                    ) {
                        Text("\(displayName(for: participant.profileId)): \(pongCupsByProfileId[participant.profileId] ?? 0) cups")
                            .font(AppFont.body)
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

                let total = pongTotalCups
                Text("Pong total: \(total) / \(pongCupMode.rawValue)")
                    .font(AppFont.footnote)
                    .foregroundColor(total == pongCupMode.rawValue ? .secondary : .red)
            }
        }
    }

    @ViewBuilder
    private var beerBallStatsView: some View {
        VStack(alignment: .leading, spacing: 12) {
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
        VStack(alignment: .leading, spacing: 12) {
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
        VStack(alignment: .leading, spacing: 12) {
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

    private var canSubmitGameLog: Bool {
        !selectedCommunityId.isEmpty &&
        outcome != nil &&
        selectedWinnerProfileIds.count == teamSize &&
        selectedLoserProfileIds.count == teamSize &&
        hasRequiredPhotos &&
        currentStatsValidationError == nil
    }

    private var canSubmitWithoutPhotos: Bool {
        !selectedCommunityId.isEmpty &&
        outcome != nil &&
        selectedWinnerProfileIds.count == teamSize &&
        selectedLoserProfileIds.count == teamSize &&
        currentStatsValidationError == nil
    }

    private var submitDisableReasons: [String] {
        var reasons: [String] = []
        if frontPhotoData == nil || backPhotoData == nil {
            reasons.append("Photos are required and will be captured when you submit")
        }
        if selectedWinnerProfileIds.count != teamSize || selectedLoserProfileIds.count != teamSize {
            reasons.append("Winners and losers must each equal team size")
        }
        if selectedGameType == .pong, teamSize > 1, pongTotalCups != pongCupMode.rawValue {
            reasons.append("Pong total must equal selected cup mode")
        }
        if !selectedMVPProfileId.isEmpty &&
            !selectedLVPProfileId.isEmpty &&
            selectedMVPProfileId == selectedLVPProfileId {
            reasons.append("MVP and LVP must be different players")
        }
        return reasons
    }

    private var currentUserId: String? {
        Auth.auth().currentUser?.uid
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

    private var pongTotalCups: Int {
        participantProfileIds.reduce(0) { $0 + (pongCupsByProfileId[$1] ?? 0) }
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
            if pongTotalCups != pongCupMode.rawValue {
                return "Pong cups must add up to \(pongCupMode.rawValue)."
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

    private func teamSizeRange(for gameType: GameType) -> ClosedRange<Int> {
        switch gameType {
        case .pong, .beerBall:
            return 1...10
        case .battlePong, .baseball:
            return 3...20
        }
    }

    private func resetSelectionForScopeChange() {
        outcome = nil
        selectedWinnerProfileIds.removeAll()
        selectedLoserProfileIds.removeAll()
        isTeammateDropdownOpen = false
        isOpponentDropdownOpen = false
        teammateQuery = ""
        opponentQuery = ""
        syncStatsWithParticipants()
    }

    private func syncStatsWithParticipants() {
        let ids = Set(participantProfileIds)

        pongCupsByProfileId = keepOnly(ids: ids, from: pongCupsByProfileId)
        beerBallNewCansByProfileId = keepOnly(ids: ids, from: beerBallNewCansByProfileId)
        battlePongCupsByProfileId = keepOnly(ids: ids, from: battlePongCupsByProfileId)
        baseballHitsByProfileId = keepOnly(ids: ids, from: baseballHitsByProfileId)

        if !pongLastCupByProfileId.isEmpty && !ids.contains(pongLastCupByProfileId) {
            pongLastCupByProfileId = ""
        }
        if !beerBallFirstFinishedByProfileId.isEmpty && !ids.contains(beerBallFirstFinishedByProfileId) {
            beerBallFirstFinishedByProfileId = ""
        }
        if !selectedMVPProfileId.isEmpty && !ids.contains(selectedMVPProfileId) {
            selectedMVPProfileId = ""
        }
        if !selectedLVPProfileId.isEmpty && !ids.contains(selectedLVPProfileId) {
            selectedLVPProfileId = ""
        }

        // Solo Pong defaults: fixed 10-cup mode and last cup = winner.
        if selectedGameType == .pong, teamSize == 1, let winnerId = soloWinnerProfileId {
            pongCupMode = .ten
            pongLastCupByProfileId = winnerId
            var onlyWinner: [String: Int] = [:]
            onlyWinner[winnerId] = 10
            pongCupsByProfileId = onlyWinner
        }
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
        switch outcome {
        case .won:
            selectedWinnerProfileIds.insert(myUserId)
        case .lost:
            selectedLoserProfileIds.insert(myUserId)
        case .none:
            break
        }
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
        } else {
            guard currentSet.count < teamSize else { return }
            if isMySideWinners {
                selectedWinnerProfileIds.insert(profileId)
                selectedLoserProfileIds.remove(profileId)
            } else {
                selectedLoserProfileIds.insert(profileId)
                selectedWinnerProfileIds.remove(profileId)
            }
        }
        selectedWinnerProfileIds.subtract(selectedLoserProfileIds)
        selectedLoserProfileIds.subtract(selectedWinnerProfileIds)
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
        } else {
            guard currentSet.count < teamSize else { return }
            if opponentsAreLosers {
                selectedLoserProfileIds.insert(profileId)
                selectedWinnerProfileIds.remove(profileId)
            } else {
                selectedWinnerProfileIds.insert(profileId)
                selectedLoserProfileIds.remove(profileId)
            }
        }
        selectedWinnerProfileIds.subtract(selectedLoserProfileIds)
        selectedLoserProfileIds.subtract(selectedWinnerProfileIds)
    }

    private func submitGameLog() async {
        submitErrorMessage = nil
        showOpenSettingsAction = false
        guard canSubmitGameLog else { return }
        guard let uid = currentUserId else {
            submitErrorMessage = "Sign in again, then try submitting."
            return
        }
        let participants = participantProfileIds
        let winners = Array(selectedWinnerProfileIds).sorted()
        let losers = Array(selectedLoserProfileIds).sorted()
        guard !participants.isEmpty else {
            submitErrorMessage = "Select participants before submitting."
            return
        }
        guard let frontData = frontPhotoData, let backData = backPhotoData else {
            submitErrorMessage = "Capture both front and back photos before submitting."
            return
        }
        guard let combinedPhotoData = makeCombinedPhotoData(frontData: frontData, backData: backData) else {
            submitErrorMessage = "Could not combine front and back photos. Please retake and try again."
            return
        }

        let gameLogId = AppFirestore.db().collection("gameLogs").document().documentID
        let communityId = selectedCommunityId
        let gameType = selectedGameType
        let pongStats = selectedGameType == .pong ? buildPongStats() : nil
        let beerBallStats = selectedGameType == .beerBall ? buildBeerBallStats() : nil
        let battlePongStats = selectedGameType == .battlePong ? buildBattlePongStats() : nil
        let baseballStats = selectedGameType == .baseball ? buildBaseballStats() : nil
        let trimmedNotes = gameLogNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let notesPayload: String? = trimmedNotes.isEmpty ? nil : trimmedNotes
        let gameLogService = container.gameLogService

        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let combinedUrl = try await gameLogService.uploadGamePhoto(
                communityId: communityId,
                gameLogId: gameLogId,
                side: "combined",
                data: combinedPhotoData,
                contentType: "image/jpeg"
            )

            let payload = GameLogCreatePayload(
                gameLogId: gameLogId,
                communityId: communityId,
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
                baseballStats: baseballStats
            )
            try await gameLogService.createGameLog(payload: payload)
            dismiss()
        } catch {
            submitErrorMessage = error.localizedDescription
            AppDebugLog.log("submitGameLog failed: \(error.localizedDescription)")
        }
    }

    private func handleSubmitTapped() async {
        submitErrorMessage = nil
        showOpenSettingsAction = false

        guard canSubmitWithoutPhotos else {
            submitErrorMessage = "Complete required game details before submitting."
            return
        }

        if !hasRequiredPhotos {
            let status = await CameraPermissionCoordinator.ensureVideoPermission()
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
            "playerCupsHit": pongCupsByProfileId
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
            selectedCommunityId = communities.first?.communityId ?? ""
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
        do {
            members = try await container.communityService.fetchMembers(communityId: selectedCommunityId)
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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(GameLogBrandColor.red)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(GameLogBrandColor.red, lineWidth: 2)
            )
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Same treatment as `FeedPrimaryActionButtonStyle` (feed bottom actions).
private struct BrandPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(GameLogBrandColor.red)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white, lineWidth: 2)
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

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pong: return "Pong"
        case .beerBall: return "Beer Ball"
        case .battlePong: return "Battle Pong"
        case .baseball: return "Baseball"
        }
    }
}

private enum PongCupMode: Int, CaseIterable, Identifiable {
    case six = 6
    case ten = 10

    var id: Int { rawValue }

    var displayName: String {
        "\(rawValue)-cup"
    }
}

