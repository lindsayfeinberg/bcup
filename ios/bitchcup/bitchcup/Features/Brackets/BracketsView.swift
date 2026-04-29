import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct BracketsView: View {
    private enum BracketViewMode {
        case rounds
        case bracket
    }

    let bracketId: String
    let seedMethod: SeedMethod?
    let teamSize: Int?
    let members: [CommunityMemberRosterRow]

    @EnvironmentObject private var container: DependencyContainer
    @EnvironmentObject private var sessionManager: AppSessionManager
    @State private var viewMode: BracketViewMode = .rounds
    @State private var bracketStatus: String = "DRAFT"
    @State private var bracketRounds: [BracketRoundSnapshot] = []
    @State private var bracketCommunityId: String = ""
    @State private var bracketTeamSize: Int = 1
    @State private var bracketSeedMethod: SeedMethod?
    @State private var bracketMembers: [CommunityMemberRosterRow]
    @State private var isLoadingBracketMembers = false
    @State private var showManualSeed = false
    @State private var isFinalized = false
    @State private var listener: ListenerRegistration?
    @State private var bracketGameTypeFromDoc: String = "PONG"
    @State private var bracketCustomDefinitionIdFromDoc: String?
    @State private var bracketCustomDefinitionNameFromDoc: String?
    @State private var bracketParticipantProfileIds: [String] = []

    @State private var logResultContext: GameLogBracketContext?

    private var matchById: [String: BracketMatchSnapshot] {
        var dict: [String: BracketMatchSnapshot] = [:]
        for round in bracketRounds {
            for match in round.matches {
                dict[match.matchId] = match
            }
        }
        return dict
    }

    private var resolvedSeedMethod: SeedMethod? {
        bracketSeedMethod ?? seedMethod
    }

    /// Stored roster on the bracket doc, or a fallback union from round 1 (older docs).
    private var bracketAuthoritativeRoster: [String] {
        if !bracketParticipantProfileIds.isEmpty {
            return bracketParticipantProfileIds
        }
        guard let r1 = bracketRounds.first(where: { $0.roundNumber == 1 }) else { return [] }
        var seen = Set<String>()
        var ordered: [String] = []
        for m in r1.matches {
            for id in m.participantProfileIds ?? [] where !seen.contains(id) {
                seen.insert(id)
                ordered.append(id)
            }
        }
        return ordered
    }

    /// `initial*` values come from `BracketListItem` / navigation so game type is correct before the first Firestore snapshot (avoids a race where “Log game” used PONG).
    init(
        bracketId: String,
        seedMethod: SeedMethod? = nil,
        teamSize: Int? = nil,
        members: [CommunityMemberRosterRow] = [],
        initialBracketGameType: String? = nil,
        initialCustomGameDefinitionId: String? = nil,
        initialCustomGameDefinitionName: String? = nil
    ) {
        self.bracketId = bracketId
        self.seedMethod = seedMethod
        self.teamSize = teamSize
        self.members = members
        _bracketSeedMethod = State(initialValue: seedMethod)
        _bracketTeamSize = State(initialValue: teamSize ?? 1)
        _bracketMembers = State(initialValue: members)

        let trimmedType = (initialBracketGameType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        _bracketGameTypeFromDoc = State(initialValue: trimmedType.isEmpty ? "PONG" : trimmedType)

        let trimmedCustomId = (initialCustomGameDefinitionId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        _bracketCustomDefinitionIdFromDoc = State(initialValue: trimmedCustomId.isEmpty ? nil : trimmedCustomId)

        let trimmedCustomName = (initialCustomGameDefinitionName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        _bracketCustomDefinitionNameFromDoc = State(initialValue: trimmedCustomName.isEmpty ? nil : trimmedCustomName)
    }

    var body: some View {
        VStack(spacing: 12) {
            toggleRow

            if viewMode == .bracket {
                bracketVisualizationContent
            } else {
                if resolvedSeedMethod == .manual && !isFinalized {
                    manualSeedCta
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    bracketRoundsContent
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Bracket")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !bracketId.isEmpty else { return }
            if UITestRuntime.participatesInUiTestHarness {
                listener?.remove()
                listener = nil
                // Mock brackets from UITestContainerFactory are not in Firestore; avoid snapshot listener (permissions / missing doc).
                if bracketCommunityId.isEmpty {
                    bracketCommunityId = "ui-community-1"
                }
                if let seedMethod {
                    bracketSeedMethod = seedMethod
                }
                if let teamSize {
                    bracketTeamSize = teamSize
                }
                bracketStatus = "ACTIVE"
                bracketRounds = []
                isFinalized = true
                bracketGameTypeFromDoc = "PONG"
                bracketCustomDefinitionIdFromDoc = nil
                bracketCustomDefinitionNameFromDoc = nil
                bracketParticipantProfileIds = []
                return
            }
            listener?.remove()
            listener = AppFirestore.db()
                .collection("brackets")
                .document(bracketId)
                .addSnapshotListener { snapshot, _ in
                    guard let snapshot, snapshot.exists else { return }
                    do {
                        let data = try snapshot.data(as: BracketSnapshot.self)

                        bracketStatus = data.status
                        if data.status != "DRAFT" {
                            isFinalized = true
                        }
                        bracketRounds = data.rounds
                        bracketCommunityId = data.communityId
                        bracketTeamSize = data.teamSize
                        bracketSeedMethod = data.seedMethod
                        bracketGameTypeFromDoc = data.gameType
                        bracketCustomDefinitionIdFromDoc = data.customGameDefinitionId
                        bracketCustomDefinitionNameFromDoc = data.customGameDefinitionName
                        bracketParticipantProfileIds = data.participantProfileIds ?? []
                    } catch {
                        AppDebugLog.log("BracketsView: decode failed bracketId=\(bracketId) error=\(error.localizedDescription)")
                    }
                }
        }
        .task(id: "\(bracketId)|\(bracketCommunityId)") {
            await loadBracketMembersIfNeeded()
        }
        .onDisappear {
            listener?.remove()
            listener = nil
        }
        .communityFlowNavigationBarChrome()
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                CommunityFlowBackToolbarButton()
            }
        }
        .sheet(isPresented: $showManualSeed) {
            ManualSeedView(
                bracketId: bracketId,
                teamSize: bracketTeamSize,
                members: bracketMembers,
                onFinalized: {
                    // `ManualSeedView` no longer dismisses itself after finalizing;
                    // close this fallback sheet here so the bracket view can render.
                    isFinalized = true
                    showManualSeed = false
                }
            )
            .environmentObject(container)
        }
        .fullScreenCover(item: $logResultContext) { context in
            NavigationStack {
                NewGameLogFormView(bracketContext: context)
                    .environmentObject(container)
                    .environmentObject(sessionManager)
                    .navigationTitle("Log game")
                    .navigationBarTitleDisplayMode(.inline)
                    .communityFlowNavigationBarChrome()
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            CommunityFlowCloseToolbarButton {
                                logResultContext = nil
                            }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var bracketRoundsContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if bracketStatus != "ACTIVE", bracketStatus != "COMPLETE" {
                Text("Bracket status: \(bracketStatus)")
                    .font(AppFont.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    notInBracketRosterBanner
                    authoritativeBracketRosterSection
                    let sortedRounds = bracketRounds.sorted(by: { $0.roundNumber < $1.roundNumber })
                    let finalRoundNumber = sortedRounds.last?.roundNumber

                    ForEach(sortedRounds.filter {
                        BracketMatchDisplay.allPriorRoundsFullyPlayed(forMatchRound: $0.roundNumber, rounds: sortedRounds)
                    }, id: \.roundNumber) { round in
                        let visibleMatches = round.matches.filter { shouldShowMatchInRound($0) }

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(round.roundNumber == finalRoundNumber ? "Final" : "Round \(round.roundNumber)")
                                    .font(AppFont.headline)
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 0)
                                if bracketStatus == "COMPLETE", round.roundNumber == finalRoundNumber {
                                    statusPill(text: "Complete", isActive: false)
                                }
                            }

                            if visibleMatches.isEmpty {
                                Text("No games in this round.")
                                    .font(AppFont.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            let priorRoundsComplete = BracketMatchDisplay.allPriorRoundsFullyPlayed(
                                forMatchRound: round.roundNumber,
                                rounds: sortedRounds
                            )

                            ForEach(Array(visibleMatches.enumerated()), id: \.element.id) { index, match in
                                BracketMatchRow(
                                    matchIndex: index,
                                    match: match,
                                    members: bracketMembers,
                                    matchById: matchById,
                                    priorRoundsComplete: priorRoundsComplete,
                                    onLogResult: { effectiveParticipantProfileIds in
                                        logResultContext = GameLogBracketContext(
                                            bracketId: bracketId,
                                            bracketMatchId: match.matchId,
                                            communityId: bracketCommunityId,
                                            participantProfileIds: effectiveParticipantProfileIds,
                                            teamSize: bracketTeamSize,
                                            bracketGameType: bracketGameTypeFromDoc,
                                            bracketCustomGameDefinitionId: bracketCustomDefinitionIdFromDoc,
                                            bracketCustomGameDefinitionName: bracketCustomDefinitionNameFromDoc
                                        )
                                    },
                                    teamSize: bracketTeamSize
                                )
                            }
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                    }

                    if resolvedSeedMethod == .random {
                        Text("Players were randomly assigned to bracket positions (fixed for this bracket).")
                            .font(AppFont.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .padding(.top, 6)
                    }

                    Text("ID: \(bracketId)")
                        .font(AppFont.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 10)
                }
                .padding()
            }
        }
    }

    private var manualSeedCta: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Manual bracket")
                .font(AppFont.headline)
                .foregroundStyle(.primary)

            Text("Assign players to each team to activate this bracket.")
                .font(AppFont.footnote)
                .foregroundStyle(.secondary)

            Button {
                showManualSeed = true
            } label: {
                Text("Assign teams")
                    .font(AppFont.buttonProminent)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.black)
                    )
                    .foregroundStyle(.white)
            }
            .contentShape(Rectangle())
            .buttonStyle(.plain)

            Text("ID: \(bracketId)")
                .font(AppFont.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 6)
        }
        .padding()
    }

    private var toggleRow: some View {
        HStack(spacing: 10) {
            toggleButton(title: "Rounds", isSelected: viewMode == .rounds) {
                viewMode = .rounds
            }
            toggleButton(title: "Bracket", isSelected: viewMode == .bracket) {
                viewMode = .bracket
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func toggleButton(title: String, isSelected: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            Text(title)
                .font(AppFont.button)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? BracketBrandColor.accent : Color(.secondarySystemGroupedBackground))
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
        }
        .contentShape(Rectangle())
        .buttonStyle(.plain)
    }

    private func statusPill(text: String, isActive: Bool) -> some View {
        Text(text)
            .font(AppFont.caption)
            .foregroundStyle(isActive ? BracketBrandColor.accent : Color(.secondaryLabel))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(isActive ? BracketBrandColor.accent.opacity(0.18) : Color(.tertiarySystemFill))
            )
    }

    private func shouldShowMatchInRound(_ match: BracketMatchSnapshot) -> Bool {
        !BracketMatchDisplay.hideFromRoundsList(match: match, teamSize: bracketTeamSize)
    }

    @ViewBuilder
    private var bracketVisualizationContent: some View {
        if resolvedSeedMethod == .manual && !isFinalized {
            manualSeedCta
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else if bracketRounds.isEmpty {
            VStack(spacing: 8) {
                Spacer(minLength: 0)
                Text("No bracket data yet.")
                    .font(AppFont.emptyStateTitle)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                notInBracketRosterBanner
                authoritativeBracketRosterSection
                BracketTreeView(
                    rounds: bracketRounds,
                    matchById: matchById,
                    members: bracketMembers,
                    teamSize: bracketTeamSize,
                    onLogResult: { match, participantIds in
                        logResultContext = GameLogBracketContext(
                            bracketId: bracketId,
                            bracketMatchId: match.matchId,
                            communityId: bracketCommunityId,
                            participantProfileIds: participantIds,
                            teamSize: bracketTeamSize,
                            bracketGameType: bracketGameTypeFromDoc,
                            bracketCustomGameDefinitionId: bracketCustomDefinitionIdFromDoc,
                            bracketCustomGameDefinitionName: bracketCustomDefinitionNameFromDoc
                        )
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var notInBracketRosterBanner: some View {
        let roster = bracketAuthoritativeRoster
        if let uid = Auth.auth().currentUser?.uid,
           !roster.isEmpty,
           !roster.contains(uid) {
            Text("Your account is not in this bracket's saved player list. This list was fixed when the bracket was created. Create a new bracket to include everyone in the league now.")
                .font(AppFont.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var authoritativeBracketRosterSection: some View {
        let roster = bracketAuthoritativeRoster
        let showList = !roster.isEmpty && (resolvedSeedMethod != .manual || isFinalized)
        if showList {
            VStack(alignment: .leading, spacing: 6) {
                Text("Players in this bracket (\(roster.count))")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
                ForEach(roster, id: \.self) { id in
                    Text(displayNameForBracketRoster(id: id))
                        .font(AppFont.footnote)
                        .foregroundStyle(.primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
        }
    }

    private func displayNameForBracketRoster(id: String) -> String {
        if let row = bracketMembers.first(where: { $0.profileId == id }) {
            let t = row.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? "Unknown" : t
        }
        return "Unknown"
    }

    private func loadBracketMembersIfNeeded() async {
        guard !bracketCommunityId.isEmpty else { return }
        guard !isLoadingBracketMembers else { return }
        isLoadingBracketMembers = true
        defer { isLoadingBracketMembers = false }
        do {
            // Always refetch: parent `members` can be stale vs Firestore, and `names()` only resolves
            // IDs present in this array — missing rows made bracket participants look "left out".
            bracketMembers = try await container.communityService.fetchMembers(communityId: bracketCommunityId)
        } catch {
            AppDebugLog.log("BracketsView: load members failed communityId=\(bracketCommunityId) error=\(error.localizedDescription)")
        }
    }
}

private struct BracketMatchRow: View {
    let matchIndex: Int
    let match: BracketMatchSnapshot
    let members: [CommunityMemberRosterRow]
    let matchById: [String: BracketMatchSnapshot]
    let priorRoundsComplete: Bool
    let onLogResult: ([String]) -> Void
    let teamSize: Int

    private var currentUserId: String? {
        Auth.auth().currentUser?.uid ?? UITestRuntime.currentUserIdFallback
    }

    private var viewerProfileIds: Set<String> {
        Set([currentUserId].compactMap { $0 })
    }

    private var ui: BracketMatchUIState {
        BracketMatchDisplay.uiState(
            match: match,
            matchById: matchById,
            teamSize: teamSize,
            currentUserId: currentUserId,
            viewerProfileIds: viewerProfileIds,
            priorRoundsComplete: priorRoundsComplete
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text("Game \(matchIndex + 1)")
                    .font(AppFont.subheadlineBold)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                statusPill(text: ui.isPlayed ? "Completed" : "Not completed", isActive: !ui.isPlayed)
            }

            if ui.isPlayed {
                let winners = match.winnerProfileIds ?? []
                let losers = match.loserProfileIds ?? []

                if !winners.isEmpty {
                    Text("˗ˏˋ  \(nameLine(winners))  ˎˊ˗")
                        .font(AppFont.bodyMedium)
                        .foregroundStyle(.primary)
                        .lineLimit(4)
                }

                if !losers.isEmpty {
                    Text("Loser: \(nameLine(losers))")
                        .font(AppFont.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            } else {
                if ui.isBlockedByIncompletePriorRounds {
                    Text("Earlier rounds must finish before this game can be logged.")
                        .font(AppFont.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                } else if ui.isWaitingOnFeeders {
                    Text("Waiting for previous matches...")
                        .font(AppFont.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(ui.effectiveParticipantProfileIds, id: \.self) { id in
                            Text(memberDisplayName(for: id))
                                .font(AppFont.bodyMedium)
                                .foregroundStyle(.primary)
                        }
                    }
                }

                if ui.canLogResult {
                    Button {
                        onLogResult(ui.effectiveParticipantProfileIds)
                    } label: {
                        Text("Log game")
                            .font(AppFont.buttonProminent)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(BracketBrandColor.accent)
                            )
                            .foregroundStyle(.white)
                    }
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white)
        )
    }

    private func memberDisplayName(for id: String) -> String {
        guard let row = members.first(where: { $0.profileId == id }) else {
            return "Unknown"
        }
        let trimmed = row.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown" : trimmed
    }

    private func nameLine(_ ids: [String]) -> String {
        ids.map { memberDisplayName(for: $0) }.joined(separator: " · ")
    }

    private func statusPill(text: String, isActive: Bool) -> some View {
        Text(text)
            .font(AppFont.caption)
            .foregroundStyle(isActive ? BracketBrandColor.accent : Color(.secondaryLabel))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(isActive ? BracketBrandColor.accent.opacity(0.18) : Color(.tertiarySystemFill))
            )
    }
}

extension GameLogBracketContext: Identifiable {
    var id: String {
        "\(bracketId)|\(bracketMatchId)"
    }
}
