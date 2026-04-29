import FirebaseFirestore
import SwiftUI
import UIKit

private struct CommunityDetailGameLogEditItem: Identifiable {
    let id: String
}

private struct BracketCreateGameOption: Identifiable, Hashable {
    let id: String
    let title: String
    let gameTypeRaw: String
    let customDefinitionId: String?
}

struct CommunityDetailView: View {
    let communityId: String

    private let pageTitleFont = Font.custom("NeueHaasDisplay-Bold", size: 42)
    private let sectionHeaderFont = Font.custom("NeueHaasDisplay-Mediu", size: 28)
    private let memberRankFont = Font.custom("NeueHaasDisplay-Mediu", size: 18)
    private let memberNameFont = Font.custom("NeueHaasDisplay-Mediu", size: 17)
    private let memberDetailFont = Font.custom("NeueHaasDisplay-Light", size: 15)
    /// Same family as member names (`NeueHaasDisplay-Mediu`), smaller than `memberNameFont` for rank-by control.
    private let rankingBasisFont = Font.custom("NeueHaasDisplay-Mediu", size: 14)

    @EnvironmentObject private var container: DependencyContainer
    @EnvironmentObject private var sessionManager: AppSessionManager
    @State private var communityName: String = ""
    @State private var inviteCode: String?
    @State private var createdByProfileId: String?
    @State private var hiddenFromMembers = false
    @State private var confirmHideLeague = false
    @State private var confirmUnhideLeague = false
    @State private var isSavingVisibility = false
    @State private var visibilityErrorMessage: String?
    @State private var members: [CommunityMemberRosterRow] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var copiedInviteCode = false

    @State private var feedRows: [FeedRow] = []
    @State private var selectedSeedMethod: SeedMethod = .communityOdds
    /// Quick picks 1v1–4v4; use `bracketUsesCustomPlayersPerSide` + `bracketCustomPlayersPerSideText` for any size up to `bracketPlayersPerSideMax`.
    @State private var bracketPresetPlayersPerSide: Int = 2
    @State private var bracketUsesCustomPlayersPerSide: Bool = false
    @State private var bracketCustomPlayersPerSideText: String = "5"
    @FocusState private var customBracketTeamSizeFieldFocused: Bool
    @State private var bracketCreateGameOptionId: String = GameType.pong.rawValue
    @State private var isCreatingBracket = false
    @State private var bracketErrorMessage: String?
    @State private var brackets: [BracketListItem] = []
    @State private var isLoadingBrackets = false
    @State private var bracketsErrorMessage: String?
    @State private var selectedBracketForNavigation: BracketListItem?
    @State private var pendingManualBracket: BracketListItem?
    @State private var showManualSeedFlow = false
    @State private var showCreateBracketPopup = false
    @State private var isLoadingFeed = false
    @State private var feedErrorMessage: String?
    @State private var feedCursor: FeedPageCursor?
    @State private var hasMoreFeed = false
    @State private var isLoadingMoreFeed = false
    @State private var loadMoreFeedErrorMessage: String?
    @State private var visibleActiveBracketsCount = 3
    @State private var visiblePastBracketsCount = 3
    @State private var rankingChip: LeagueRankingChip = .allGames
    @State private var gameDefinitions: [GameDefinitionRecord] = []
    @State private var kickTargetProfileId: String?
    @State private var kickTargetDisplayName: String = ""
    @State private var showKickConfirm = false
    @State private var kickInProgress = false
    @State private var kickErrorMessage: String?
    @State private var gameLogEditSheet: CommunityDetailGameLogEditItem?
    /// Matches Cloud Function `BRACKET_TEAM_SIZE_MAX` (`functions/src/brackets.ts`).
    private static let bracketPlayersPerSideMax = 20

    private let uiTestMembers: [CommunityMemberRosterRow] = [
        .init(profileId: "ui-test-user", displayName: "You", profilePhotoUrl: nil, communityOdds: 0.75, communityGamesPlayed: 4),
        .init(profileId: "ui-opponent-1", displayName: "Alex", profilePhotoUrl: nil, communityOdds: 0.62, communityGamesPlayed: 3),
        .init(profileId: "ui-opponent-2", displayName: "Riley", profilePhotoUrl: nil, communityOdds: 0.51, communityGamesPlayed: 2),
        .init(profileId: "ui-opponent-3", displayName: "Jordan", profilePhotoUrl: nil, communityOdds: 0.41, communityGamesPlayed: 2)
    ]

    private var bracketAccentColor: Color {
        // Kept consistent with the existing community join/create flows.
        Color(red: 180.0 / 255.0, green: 61.0 / 255.0, blue: 37.0 / 255.0)
    }

    private var bracketAccentTextDisabledColor: Color {
        Color(red: 207.0 / 255.0, green: 106.0 / 255.0, blue: 84.0 / 255.0)
    }

    private var displayCommunityName: String {
        let trimmed = communityName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "League" : trimmed
    }

    private var isCurrentUserCreator: Bool {
        guard let uid = container.authService.currentUserId,
              let created = createdByProfileId
        else { return false }
        return uid == created
    }

    /// Players per team sent to `createBracket` (presets 1–4 or custom 1…`bracketPlayersPerSideMax`).
    private var effectiveBracketPlayersPerSide: Int {
        let cap = Self.bracketPlayersPerSideMax
        if bracketUsesCustomPlayersPerSide {
            let t = bracketCustomPlayersPerSideText.trimmingCharacters(in: .whitespacesAndNewlines)
            if let v = Int(t), v >= 1, v <= cap {
                return v
            }
            return min(max(bracketPresetPlayersPerSide, 1), cap)
        }
        return min(max(bracketPresetPlayersPerSide, 1), cap)
    }

    /// Teams formed by chunking the seed list in `teamSize` slices; the last team may have fewer players.
    private var teamCountForBracket: Int {
        let s = effectiveBracketPlayersPerSide
        guard s > 0 else { return 0 }
        return (members.count + s - 1) / s
    }

    private var hasEnoughMembersForSelectedTeamSize: Bool {
        members.count >= 2 && teamCountForBracket >= 2
    }

    /// Entry-point gating: only disable the *popup opener* when no bracket is possible at all.
    /// (Creation itself is still validated by `canCreateBracket` based on selected team size.)
    private var canOpenCreateBracketPopup: Bool {
        members.count >= 2
    }

    private var canCreateBracket: Bool {
        hasEnoughMembersForSelectedTeamSize
    }

    private var bracketCreateGameOptions: [BracketCreateGameOption] {
        var list: [BracketCreateGameOption] = GameType.allCases.map {
            BracketCreateGameOption(
                id: $0.rawValue,
                title: $0.displayName,
                gameTypeRaw: $0.rawValue,
                customDefinitionId: nil
            )
        }
        list += gameDefinitions.map { def in
            BracketCreateGameOption(
                id: "CUSTOM:\(def.gameDefinitionId)",
                title: def.name,
                gameTypeRaw: "CUSTOM",
                customDefinitionId: def.gameDefinitionId
            )
        }
        return list
    }

    /// Highest effective odds for `rankingChip` first; ties broken by `profileId` for stable order.
    private var membersOrderedForRanking: [CommunityMemberRosterRow] {
        members.sorted { lhs, rhs in
            let lo = lhs.effectiveOdds(chip: rankingChip)
            let ro = rhs.effectiveOdds(chip: rankingChip)
            if lo != ro {
                return lo > ro
            }
            return lhs.profileId < rhs.profileId
        }
    }

    private var rankingChips: [LeagueRankingChip] {
        LeagueRankingChip.rankingChips(gameDefinitions: gameDefinitions)
    }

    private let rankingBasisGridSpacing: CGFloat = 8

    /// Chip grid (same idea as log form game types): no menu dropdown; matches league accent styling.
    private var rankingBasisChipGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: rankingBasisGridSpacing),
            GridItem(.flexible(), spacing: rankingBasisGridSpacing),
            GridItem(.flexible(), spacing: rankingBasisGridSpacing)
        ]
        return VStack(alignment: .leading, spacing: 10) {
            Text("Rank by")
                .font(.custom("NeueHaasDisplay-Bold", size: 15))
                .foregroundStyle(bracketAccentColor)

            LazyVGrid(columns: columns, spacing: rankingBasisGridSpacing) {
                ForEach(rankingChips) { chip in
                    let selected = rankingChip == chip
                    Button {
                        rankingChip = chip
                    } label: {
                        Text(chip.displayName)
                            .font(rankingBasisFont)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 6)
                            .foregroundStyle(selected ? bracketAccentColor : .primary)
                            .background {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(selected ? Color.white : Color(UIColor.secondarySystemGroupedBackground))
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(
                                        selected ? bracketAccentColor : Color.primary.opacity(0.12),
                                        lineWidth: selected ? 2 : 1
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(chip.displayName)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Rank by")
            .accessibilityIdentifier("community.detail.rankingBasis")
        }
    }

    /// Split from `body` so the Swift compiler can type-check the screen in reasonable time.
    @ViewBuilder
    private var leagueDetailMainColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(displayCommunityName)
                .font(pageTitleFont)
                .foregroundStyle(.black)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal)
                .padding(.top, 24)
                .padding(.bottom, 28)
                .accessibilityIdentifier("community.detail.title")

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    inviteCodeSection
                    leagueBoardSection
                    creatorVisibilitySection
                    customGamesSection
                    membersSection
                    WhatIfMatchupSection(
                        members: members,
                        gameDefinitions: gameDefinitions,
                        accentColor: bracketAccentColor,
                        sectionHeaderFont: sectionHeaderFont
                    )
                    recentGamesSection
                    bracketPlaceholder
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .refreshable {
                await refreshAll()
            }
        }
        .background(Color.white)
        .overlay {
            bracketCreatePopupOverlay
        }
    }

    @ViewBuilder
    private var bracketCreatePopupOverlay: some View {
        if showCreateBracketPopup {
            ZStack {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture {
                        bracketErrorMessage = nil
                        showCreateBracketPopup = false
                    }

                VStack(alignment: .center, spacing: 18) {
                    Text("Create Bracket")
                        .font(sectionHeaderFont)
                        .foregroundStyle(.black)
                        .multilineTextAlignment(.center)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Seeding method")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Picker("Seeding", selection: $selectedSeedMethod) {
                            ForEach(SeedMethod.allCases) { method in
                                VStack(alignment: .leading) {
                                    Text(method.displayName)
                                }
                                .tag(method)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(selectedSeedMethod.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    bracketCreateGameTypePickerSection

                    bracketTeamSizePickerSection

                    if let bracketErrorMessage {
                        Text(bracketErrorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if !hasEnoughMembersForSelectedTeamSize {
                        Text("Need at least 2 members and enough for two teams (for \(effectiveBracketPlayersPerSide)v\(effectiveBracketPlayersPerSide), more than \(effectiveBracketPlayersPerSide) people in the league).")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack(spacing: 12) {
                        Button {
                            bracketErrorMessage = nil
                            showCreateBracketPopup = false
                        } label: {
                            Text("Cancel")
                                .font(.custom("NeueHaasDisplay-Mediu", size: 22))
                                .foregroundStyle(bracketAccentColor)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.white)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(bracketAccentColor, lineWidth: 2)
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { await createBracket() }
                        } label: {
                            HStack(spacing: 8) {
                                if isCreatingBracket {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                }
                                Text(isCreatingBracket ? "Creating" : "Create ")
                            }
                            .font(.custom("NeueHaasDisplay-Mediu", size: 22))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(bracketAccentColor)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!canCreateBracket || isCreatingBracket)
                        .accessibilityIdentifier("community.popup.createBracket")
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white, lineWidth: 2)
                )
                .padding(.horizontal, 24)
            }
        }
    }

    private var bracketCreateGameTypePickerSection: some View {
        let columns = [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ]
        return VStack(alignment: .leading, spacing: 8) {
            Text("Game type")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(bracketCreateGameOptions) { opt in
                    let selected = bracketCreateGameOptionId == opt.id
                    Button {
                        bracketCreateGameOptionId = opt.id
                    } label: {
                        Text(opt.title)
                            .font(rankingBasisFont)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 6)
                            .foregroundStyle(selected ? bracketAccentColor : .primary)
                            .background {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(selected ? Color.white : Color(UIColor.secondarySystemGroupedBackground))
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(
                                        selected ? bracketAccentColor : Color.primary.opacity(0.12),
                                        lineWidth: selected ? 2 : 1
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var bracketTeamSizePickerSection: some View {
        let columns = [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ]
        let cap = Self.bracketPlayersPerSideMax
        let presets = [1, 2, 3, 4]
        return VStack(alignment: .leading, spacing: 10) {
            Text("Team size")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(presets, id: \.self) { n in
                    let selected = !bracketUsesCustomPlayersPerSide && bracketPresetPlayersPerSide == n
                    Button {
                        bracketUsesCustomPlayersPerSide = false
                        bracketPresetPlayersPerSide = n
                    } label: {
                        Text("\(n)v\(n)")
                            .font(rankingBasisFont)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 6)
                            .foregroundStyle(selected ? bracketAccentColor : .primary)
                            .background {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(selected ? Color.white : Color(UIColor.secondarySystemGroupedBackground))
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(
                                        selected ? bracketAccentColor : Color.primary.opacity(0.12),
                                        lineWidth: selected ? 2 : 1
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                }
                let customSelected = bracketUsesCustomPlayersPerSide
                Button {
                    bracketUsesCustomPlayersPerSide = true
                    if bracketCustomPlayersPerSideText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        bracketCustomPlayersPerSideText = String(bracketPresetPlayersPerSide)
                    }
                } label: {
                    Text("Custom")
                        .font(rankingBasisFont)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 6)
                        .foregroundStyle(customSelected ? bracketAccentColor : .primary)
                        .background {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(customSelected ? Color.white : Color(UIColor.secondarySystemGroupedBackground))
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(
                                    customSelected ? bracketAccentColor : Color.primary.opacity(0.12),
                                    lineWidth: customSelected ? 2 : 1
                                )
                        }
                }
                .buttonStyle(.plain)
            }

            if bracketUsesCustomPlayersPerSide {
                HStack(alignment: .center, spacing: 10) {
                    TextField("Players per team (1–\(cap))", text: $bracketCustomPlayersPerSideText)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                        .focused($customBracketTeamSizeFieldFocused)
                        .accessibilityIdentifier("community.bracket.customTeamSize")

                    Button {
                        customBracketTeamSizeFieldFocused = false
                    } label: {
                        Text("Save")
                            .font(.custom("NeueHaasDisplay-Mediu", size: 18))
                            .foregroundStyle(bracketAccentColor)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(bracketAccentColor, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("community.bracket.customTeamSize.save")
                }
            }

            Text(
                "Seeding builds teams of up to \(effectiveBracketPlayersPerSide) in order; the last team can have fewer players if the league count doesn’t divide evenly (e.g. 5 people at 2v2 → two teams of 2 and one team of 1)."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    var body: some View {
        Group {
            if isLoading {
                LoadingView(message: "Loading league...")
            } else if let error = errorMessage {
                ErrorView(message: error) {
                    Task { await loadInitial() }
                }
            } else {
                leagueDetailMainColumn
            }
        }
        .background(Color.white)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                CommunityFlowBackToolbarButton()
            }
        }
        .toolbarBackground(Color.white, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task {
            await loadInitial()
        }
        .sheet(item: $gameLogEditSheet) { item in
            NavigationStack {
                NewGameLogFormView(editingGameLogId: item.id)
                    .environmentObject(container)
                    .environmentObject(sessionManager)
                    .navigationTitle("Edit game")
                    .navigationBarTitleDisplayMode(.inline)
                    .communityFlowNavigationBarChrome()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            CommunityFlowCloseToolbarButton {
                                gameLogEditSheet = nil
                            }
                        }
                    }
            }
        }
        .confirmationDialog(
            "Hide this league from members?",
            isPresented: $confirmHideLeague,
            titleVisibility: .visible
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Hide", role: .destructive) {
                Task { await applyCommunityVisibility(hidden: true) }
            }
        } message: {
            Text("They remain members, but won't see this league, games, or brackets in the app. Overall stats are unchanged.")
        }
        .confirmationDialog(
            "Unhide this league for members?",
            isPresented: $confirmUnhideLeague,
            titleVisibility: .visible
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Unhide") {
                Task { await applyCommunityVisibility(hidden: false) }
            }
        } message: {
            Text("Everyone in the league will see it again in their lists.")
        }
        .fullScreenCover(isPresented: $showManualSeedFlow) {
            if let pendingManualBracket {
                ManualBracketSeedingFlowView(
                    bracketId: pendingManualBracket.bracketId,
                    teamSize: pendingManualBracket.teamSize,
                    members: members
                ) {
                    showManualSeedFlow = false
                    selectedBracketForNavigation = BracketListItem(
                        bracketId: pendingManualBracket.bracketId,
                        communityId: pendingManualBracket.communityId,
                        seedMethod: pendingManualBracket.seedMethod,
                        status: "ACTIVE",
                        teamSize: pendingManualBracket.teamSize,
                        gameType: pendingManualBracket.gameType,
                        customGameDefinitionId: pendingManualBracket.customGameDefinitionId,
                        customGameDefinitionName: pendingManualBracket.customGameDefinitionName,
                        createdAt: pendingManualBracket.createdAt
                    )
                }
                .environmentObject(container)
            } else {
                EmptyView()
            }
        }
        .navigationDestination(item: $selectedBracketForNavigation) { bracket in
            BracketsView(
                bracketId: bracket.bracketId,
                seedMethod: bracket.seedMethod,
                teamSize: bracket.teamSize,
                members: members,
                initialBracketGameType: bracket.gameType,
                initialCustomGameDefinitionId: bracket.customGameDefinitionId,
                initialCustomGameDefinitionName: bracket.customGameDefinitionName
            )
        }
    }

    private var bracketPlaceholder: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Bracket Manager")
                .font(sectionHeaderFont)
                .foregroundStyle(.black)

            // Create bracket entrypoint (opens the popup).
            Button {
                bracketErrorMessage = nil
                showCreateBracketPopup = true
            } label: {
                Text(isCreatingBracket ? "Creating..." : "Create Bracket")
                    .font(.custom("NeueHaasDisplay-Bold", size: 26))
                    .foregroundStyle(
                        canOpenCreateBracketPopup
                            ? .white
                            : bracketAccentTextDisabledColor
                    )
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(bracketAccentColor)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canOpenCreateBracketPopup || isCreatingBracket || showCreateBracketPopup)
            .opacity((isCreatingBracket || showCreateBracketPopup) ? 0.65 : 1.0)
            .accessibilityIdentifier("community.createBracket")

            Text("Active Brackets")
                .font(sectionHeaderFont)
                .foregroundStyle(.black)

            if isLoadingBrackets {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if let bracketsErrorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(bracketsErrorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await loadBracketsSection() }
                    }
                    .buttonStyle(.bordered)
                }
            } else if activeBrackets.isEmpty {
                Text("No active brackets yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleActiveBrackets) { bracket in
                    bracketRowButton(bracket)
                }
                if hasMoreActiveBrackets {
                    Button("Show more active brackets") {
                        visibleActiveBracketsCount += 3
                    }
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
                    .font(Font.custom("NeueHaasDisplay-Light", size: 16))
                    .foregroundStyle(.secondary)
                    .underline()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.white)
                }
            }

            Text("Past Brackets")
                .font(sectionHeaderFont)
                .foregroundStyle(.black)

            if !isLoadingBrackets, bracketsErrorMessage == nil {
                if pastBrackets.isEmpty {
                    Text("No past brackets yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visiblePastBrackets) { bracket in
                        bracketRowButton(bracket)
                    }
                    if hasMorePastBrackets {
                        Button("Show more past brackets") {
                            visiblePastBracketsCount += 3
                        }
                        .contentShape(Rectangle())
                        .buttonStyle(.plain)
                        .font(Font.custom("NeueHaasDisplay-Light", size: 16))
                        .foregroundStyle(.secondary)
                        .underline()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.white)
                    }
                }
            }

            if !canCreateBracket {
                Text("Need at least 2 members and enough for two teams at the selected team size.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Members (\(members.count))")
                .font(sectionHeaderFont)
                .foregroundStyle(.black)

            if members.isEmpty {
                Text("No members yet.")
                    .font(memberDetailFont)
                    .foregroundStyle(.secondary)
            } else {
                rankingBasisChipGrid

                ForEach(Array(membersOrderedForRanking.enumerated()), id: \.element.id) { index, member in
                    HStack(alignment: .center, spacing: 10) {
                        Text("\(index + 1).")
                            .font(memberRankFont)
                            .foregroundStyle(.black)
                            .frame(minWidth: 36, alignment: .trailing)
                            .monospacedDigit()

                        memberAvatar(for: member)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.displayName.isEmpty ? "Unknown" : member.displayName)
                                .font(memberNameFont)
                                .foregroundStyle(.black)
                            Text(memberOddsSubtitle(for: member))
                                .font(memberDetailFont)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if sessionManager.isPlatformAdmin {
                            Button {
                                kickTargetProfileId = member.profileId
                                kickTargetDisplayName = member.displayName.isEmpty ? "Unknown" : member.displayName
                                kickErrorMessage = nil
                                showKickConfirm = true
                            } label: {
                                Text("Kick")
                                    .font(.custom("NeueHaasDisplay-Mediu", size: 15))
                                    .foregroundStyle(Color.red.opacity(0.9))
                            }
                            .buttonStyle(.plain)
                            .disabled(kickInProgress)
                        }
                    }
                }
            }
            if sessionManager.isPlatformAdmin, let kickErrorMessage {
                Text(kickErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .confirmationDialog(
            "Remove \(kickTargetDisplayName) from this league?",
            isPresented: $showKickConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove from league", role: .destructive) {
                Task { await performKickMember() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They lose access and league stats for this league. This is logged for operators.")
        }
    }

    private var inviteCodeDisplayText: String {
        let trimmed = inviteCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "League code unavailable" : trimmed
    }

    private var hasInviteCode: Bool {
        let trimmed = inviteCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !trimmed.isEmpty
    }

    @ViewBuilder
    private var creatorVisibilitySection: some View {
        if isCurrentUserCreator {
            // Layout mirrors `inviteCodeSection`: centered red header, supporting copy, then full-width action.
            VStack(alignment: .leading, spacing: 8) {
                Text(hiddenFromMembers ? "Hidden from members" : "Visible to members")
                    .font(.custom("NeueHaasDisplay-Bold", size: 15))
                    .foregroundStyle(bracketAccentColor)
                    .frame(maxWidth: .infinity, alignment: .center)

                Text(
                    hiddenFromMembers
                        ? "Only you see this league here. Members don't see it in their lists or feeds."
                        : "Anyone in the league can open it, log games, and use brackets."
                )
                .font(memberDetailFont)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)

                if let visibilityErrorMessage {
                    Text(visibilityErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                Button {
                    if hiddenFromMembers {
                        confirmUnhideLeague = true
                    } else {
                        confirmHideLeague = true
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isSavingVisibility {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.85)
                        }
                        Text(hiddenFromMembers ? "Unhide league for members" : "Hide league from members")
                    }
                    .font(.custom("NeueHaasDisplay-Mediu", size: 22))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(bracketAccentColor)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isSavingVisibility)
                .accessibilityIdentifier("community.detail.visibilityToggle")
            }
        }
    }

    private var inviteCodeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Invite Code")
                .font(.custom("NeueHaasDisplay-Bold", size: 15))
                .foregroundStyle(bracketAccentColor)
                .frame(maxWidth: .infinity, alignment: .center)

            Text(inviteCodeDisplayText)
                .font(.custom("NeueHaasDisplay-Bold", size: hasInviteCode ? 32 : 18))
                .foregroundStyle(bracketAccentColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(bracketAccentTextDisabledColor.opacity(0.28))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(bracketAccentColor.opacity(0.55), lineWidth: 1.5)
                )
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityIdentifier("community.detail.inviteCode")

            Button {
                UIPasteboard.general.string = inviteCodeDisplayText
                copiedInviteCode = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    copiedInviteCode = false
                }
            } label: {
                Label(copiedInviteCode ? "Copied!" : "Copy Code", systemImage: "doc.on.doc")
                    .font(.custom("NeueHaasDisplay-Mediu", size: 22))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.white)
                    )
                    .foregroundStyle(bracketAccentColor)
            }
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .disabled(!hasInviteCode)
            .opacity(hasInviteCode ? 1.0 : 0.65)
            .accessibilityIdentifier("community.detail.copyInviteCode")
        }
    }

    private var customGamesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Custom game types")
                .font(.custom("NeueHaasDisplay-Bold", size: 15))
                .foregroundStyle(bracketAccentColor)
                .frame(maxWidth: .infinity, alignment: .center)

            Text("Add named rules for games unique to this league. Anyone in the league can manage these; everyone picks them when logging a game.")
                .font(memberDetailFont)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)

            NavigationLink {
                LeagueCustomGamesSettingsView(communityId: communityId)
                    .environmentObject(container)
            } label: {
                Text("Manage custom games")
                    .font(.custom("NeueHaasDisplay-Mediu", size: 22))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white)
                    )
                    .foregroundStyle(bracketAccentColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(bracketAccentColor, lineWidth: 2)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var leagueBoardSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("League board")
                .font(.custom("NeueHaasDisplay-Bold", size: 15))
                .foregroundStyle(bracketAccentColor)
                .frame(maxWidth: .infinity, alignment: .center)

            Text("A place to talk about past and future games.")
                .font(.custom("NeueHaasDisplay-Light", size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            NavigationLink {
                LeagueBoardView(communityId: communityId)
                    .environmentObject(container)
            } label: {
                Text("Open board")
                    .font(.custom("NeueHaasDisplay-Mediu", size: 22))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.white)
                    )
                    .foregroundStyle(bracketAccentColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(bracketAccentColor, lineWidth: 2)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("community.detail.openBoard")
        }
    }

    private func memberOddsSubtitle(for member: CommunityMemberRosterRow) -> String {
        let games = member.effectiveGamesPlayed(chip: rankingChip)
        if games == 0 {
            return rankingChip == .allGames
                ? "No league games yet"
                : "No \(rankingChip.displayName) games in this league"
        }
        let odds = member.effectiveOdds(chip: rankingChip)
        let oddsText = Self.oddsFormatter.string(from: NSNumber(value: odds)) ?? "0.000"
        let wins = winCount(fromOdds: odds, gamesPlayed: games)
        let losses = games - wins
        return "\(oddsText) · \(wins)-\(losses)"
    }

    /// Reconstructs integer wins from server `wins/games` odds (same source as `communityOdds` / per-type maps).
    private func winCount(fromOdds odds: Double, gamesPlayed games: Int) -> Int {
        guard games > 0 else { return 0 }
        let raw = (odds * Double(games)).rounded()
        let w = Int(raw)
        return min(max(w, 0), games)
    }

    @ViewBuilder
    private func memberAvatar(for member: CommunityMemberRosterRow) -> some View {
        if let photoURLString = member.profilePhotoUrl,
           let photoURL = URL(string: photoURLString) {
            AsyncImage(url: photoURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    Circle()
                        .foregroundStyle(Color(.systemGray4))
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(Circle())
        } else {
            Circle()
                .frame(width: 36, height: 36)
                .foregroundStyle(Color(.systemGray4))
        }
    }

    private var recentGamesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Games")
                .font(sectionHeaderFont)
                .foregroundStyle(.black)

            if isLoadingFeed && feedErrorMessage == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else if let feedError = feedErrorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(feedError)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        Task { await loadInitialFeedSection() }
                    }
                    .buttonStyle(.bordered)
                }
            } else if feedRows.isEmpty {
                Text("No games in this league yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(spacing: 24) {
                    ForEach(feedRows) { row in
                        FeedCardView(row: row, showCommunityLabel: false, onRequestEdit: { r in
                            gameLogEditSheet = CommunityDetailGameLogEditItem(id: r.gameLogId)
                        })
                    }
                    feedFooter
                }
            }
        }
    }

    private func loadInitial() async {
        isLoading = true
        errorMessage = nil
        feedErrorMessage = nil
        bracketsErrorMessage = nil
        do {
            try await fetchCommunityAndMembers()
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return
        }
        isLoading = false
        await loadInitialFeedSection()
        await loadBracketsSection()
    }

    private func fetchCommunityAndMembers() async throws {
        if UITestRuntime.participatesInUiTestHarness {
            // Never hit live data in UI tests.
            communityName = "UI Test League"
            inviteCode = "UI-TEST"
            createdByProfileId = "ui-test-user"
            hiddenFromMembers = false
            members = uiTestMembers
            gameDefinitions = []
            reconcileRankingChipWithDefinitions()
            return
        }
        let db = AppFirestore.db()
        let communityDoc = try await db.collection("communities").document(communityId).getDocument()
        let data = communityDoc.data()
        communityName = data?["name"] as? String ?? "League"
        inviteCode = data?["inviteCode"] as? String
        createdByProfileId = data?["createdByProfileId"] as? String
        hiddenFromMembers = (data?["hiddenFromMembers"] as? Bool) ?? false
        members = try await container.communityService.fetchMembers(communityId: communityId)
        gameDefinitions = try await container.communityService.listGameDefinitions(communityId: communityId)
        reconcileRankingChipWithDefinitions()
    }

    private func reconcileRankingChipWithDefinitions() {
        switch rankingChip {
        case .allGames:
            break
        case .builtIn:
            if !rankingChips.contains(rankingChip) {
                rankingChip = .allGames
            }
        case .customDefinition(let id, _):
            if let def = gameDefinitions.first(where: { $0.gameDefinitionId == id }) {
                rankingChip = .customDefinition(id: def.gameDefinitionId, name: def.name)
            } else {
                rankingChip = .allGames
            }
        }
        let validBracketGameIds = Set(bracketCreateGameOptions.map(\.id))
        if !validBracketGameIds.contains(bracketCreateGameOptionId) {
            bracketCreateGameOptionId = GameType.pong.rawValue
        }
    }

    private func performKickMember() async {
        guard let pid = kickTargetProfileId else { return }
        kickInProgress = true
        kickErrorMessage = nil
        defer { kickInProgress = false }
        do {
            try await container.platformAdminService.kickMember(communityId: communityId, profileId: pid)
            kickTargetProfileId = nil
            await loadInitial()
        } catch {
            kickErrorMessage = error.localizedDescription
        }
    }

    private func applyCommunityVisibility(hidden: Bool) async {
        if UITestRuntime.participatesInUiTestHarness {
            do {
                try await container.communityService.setCommunityHidden(communityId: communityId, hidden: hidden)
                hiddenFromMembers = hidden
            } catch {
                visibilityErrorMessage = error.localizedDescription
            }
            confirmHideLeague = false
            confirmUnhideLeague = false
            return
        }
        isSavingVisibility = true
        visibilityErrorMessage = nil
        defer { isSavingVisibility = false }
        do {
            try await container.communityService.setCommunityHidden(communityId: communityId, hidden: hidden)
            hiddenFromMembers = hidden
            confirmHideLeague = false
            confirmUnhideLeague = false
        } catch {
            visibilityErrorMessage = error.localizedDescription
        }
    }

    private func loadInitialFeedSection() async {
        isLoadingFeed = true
        feedErrorMessage = nil
        feedCursor = nil
        hasMoreFeed = false
        loadMoreFeedErrorMessage = nil
        do {
            let page = try await container.feedService.fetchFeedPage(
                forCommunityId: communityId,
                cursor: nil,
                pageSize: 2
            )
            feedRows = page.items
            feedCursor = page.nextCursor
            hasMoreFeed = page.hasMore
        } catch {
            feedRows = []
            feedErrorMessage = Self.mapFeedError(error)
        }
        isLoadingFeed = false
    }

    private func refreshAll() async {
        feedErrorMessage = nil
        errorMessage = nil
        bracketsErrorMessage = nil
        do {
            try await fetchCommunityAndMembers()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        await loadInitialFeedSection()
        await loadBracketsSection()
    }

    private func loadMoreFeedIfNeeded(currentRow: FeedRow) async {
        guard hasMoreFeed, !isLoadingMoreFeed else { return }

        isLoadingMoreFeed = true
        loadMoreFeedErrorMessage = nil
        defer { isLoadingMoreFeed = false }

        do {
            let page = try await container.feedService.fetchFeedPage(
                forCommunityId: communityId,
                cursor: feedCursor,
                pageSize: 2
            )
            let unique = Dictionary(grouping: (feedRows + page.items), by: \.gameLogId).compactMap { $0.value.first }
            feedRows = unique.sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt { return lhs.gameLogId > rhs.gameLogId }
                return lhs.createdAt > rhs.createdAt
            }
            feedCursor = page.nextCursor
            hasMoreFeed = page.hasMore
        } catch {
            loadMoreFeedErrorMessage = Self.mapFeedError(error)
        }
    }
    private func createBracket() async {
        guard canCreateBracket else {
            bracketErrorMessage =
                "Need at least 2 members and enough for two teams at team size \(effectiveBracketPlayersPerSide)."
            return
        }
        let gameOpt = bracketCreateGameOptions.first(where: { $0.id == bracketCreateGameOptionId })
            ?? BracketCreateGameOption(
                id: GameType.pong.rawValue,
                title: GameType.pong.displayName,
                gameTypeRaw: GameType.pong.rawValue,
                customDefinitionId: nil
            )
        if UITestRuntime.participatesInUiTestHarness {
            let bracketId = "ui-bracket-\(brackets.count + 1)"
            let created = BracketListItem(
                bracketId: bracketId,
                communityId: communityId,
                seedMethod: selectedSeedMethod,
                status: selectedSeedMethod == .manual ? "DRAFT" : "ACTIVE",
                teamSize: effectiveBracketPlayersPerSide,
                gameType: gameOpt.gameTypeRaw,
                customGameDefinitionId: gameOpt.customDefinitionId,
                customGameDefinitionName: gameDefinitions.first(where: { $0.gameDefinitionId == gameOpt.customDefinitionId })?.name,
                createdAt: Date()
            )
            showCreateBracketPopup = false
            brackets = [created] + brackets
            if selectedSeedMethod == .manual {
                pendingManualBracket = created
                showManualSeedFlow = true
            } else {
                showManualSeedFlow = false
                selectedBracketForNavigation = created
            }
            return
        }
        isCreatingBracket = true
        bracketErrorMessage = nil
        defer { isCreatingBracket = false }
        do {
            let bracketId = try await container.bracketService.createBracket(
                communityId: communityId,
                seedMethod: selectedSeedMethod,
                teamSize: effectiveBracketPlayersPerSide,
                gameType: gameOpt.gameTypeRaw,
                customGameDefinitionId: gameOpt.customDefinitionId
            )
            let created = BracketListItem(
                bracketId: bracketId,
                communityId: communityId,
                seedMethod: selectedSeedMethod,
                status: selectedSeedMethod == .manual ? "DRAFT" : "ACTIVE",
                teamSize: effectiveBracketPlayersPerSide,
                gameType: gameOpt.gameTypeRaw,
                customGameDefinitionId: gameOpt.customDefinitionId,
                customGameDefinitionName: gameDefinitions.first(where: { $0.gameDefinitionId == gameOpt.customDefinitionId })?.name,
                createdAt: Date()
            )
            showCreateBracketPopup = false
            if selectedSeedMethod == .manual {
                pendingManualBracket = created
                showManualSeedFlow = true
            } else {
                showManualSeedFlow = false
                selectedBracketForNavigation = created
            }
            await loadBracketsSection()
        } catch {
            bracketErrorMessage = error.localizedDescription
        }
    }

    private func loadBracketsSection() async {
        if UITestRuntime.participatesInUiTestHarness {
            isLoadingBrackets = false
            bracketsErrorMessage = nil
            visibleActiveBracketsCount = 3
            visiblePastBracketsCount = 3
            return
        }
        isLoadingBrackets = true
        defer { isLoadingBrackets = false }
        do {
            brackets = try await container.communityService.fetchBrackets(communityId: communityId)
            bracketsErrorMessage = nil
            visibleActiveBracketsCount = 3
            visiblePastBracketsCount = 3
        } catch {
            brackets = []
            bracketsErrorMessage = error.localizedDescription
            visibleActiveBracketsCount = 3
            visiblePastBracketsCount = 3
        }
    }

    private var activeBrackets: [BracketListItem] {
        brackets.filter { $0.status != "COMPLETE" }
    }

    private var pastBrackets: [BracketListItem] {
        brackets.filter { $0.status == "COMPLETE" }
    }

    private var visibleActiveBrackets: [BracketListItem] {
        Array(activeBrackets.prefix(visibleActiveBracketsCount))
    }

    private var visiblePastBrackets: [BracketListItem] {
        Array(pastBrackets.prefix(visiblePastBracketsCount))
    }

    private var hasMoreActiveBrackets: Bool {
        activeBrackets.count > visibleActiveBrackets.count
    }

    private var hasMorePastBrackets: Bool {
        pastBrackets.count > visiblePastBrackets.count
    }

    @ViewBuilder
    private func bracketRowButton(_ bracket: BracketListItem) -> some View {
        Button {
            selectedBracketForNavigation = bracket
        } label: {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(bracket.seedMethod.displayName) • \(bracket.teamSize)v\(bracket.teamSize) • \(bracket.gameTypeSummary)")
                        .font(.custom("NeueHaasDisplay-Mediu", size: 18))
                        .foregroundStyle(.black)
                    Text("Status: \(bracket.status)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let createdAt = bracket.createdAt {
                        Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text("ID: \(bracket.bracketId)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .accessibilityIdentifier("community.bracket.\(bracket.bracketId)")
    }

    private static func mapFeedError(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == FirestoreErrorDomain,
           ns.code == FirestoreErrorCode.permissionDenied.rawValue {
            return "You can't view games in this league."
        }
        return ns.localizedDescription
    }

    @ViewBuilder
    private var feedFooter: some View {
        if isLoadingMoreFeed {
            ProgressView("Loading more...")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        } else if let loadMoreFeedErrorMessage {
            VStack(spacing: 8) {
                Text(loadMoreFeedErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("Retry loading more") {
                    Task {
                        if let last = feedRows.last {
                            await loadMoreFeedIfNeeded(currentRow: last)
                        }
                    }
                }
                .contentShape(Rectangle())
                .buttonStyle(.plain)
                .font(sectionHeaderFont)
                .foregroundStyle(.black)
                .underline()
                .frame(maxWidth: .infinity)
                .background(Color.white)
            }
            .padding(.vertical, 8)
        } else if hasMoreFeed && !feedRows.isEmpty {
            Button("Show more games") {
                Task {
                    if let last = feedRows.last {
                        await loadMoreFeedIfNeeded(currentRow: last)
                    }
                }
            }
            .contentShape(Rectangle())
            .buttonStyle(.plain)
            .font(Font.custom("NeueHaasDisplay-Light", size: 16))              // or Font.custom("NeueHaasDisplay-Light", size: 16)
            .foregroundStyle(.secondary)    // gray
            .underline()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.white)
        } else if !hasMoreFeed, !feedRows.isEmpty {
            Text("No older games.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
    }
    
    
    private static let oddsFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.minimumFractionDigits = 3
        f.maximumFractionDigits = 3
        f.numberStyle = .decimal
        return f
    }()
}
