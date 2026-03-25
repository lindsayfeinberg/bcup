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

    init(
        bracketId: String,
        seedMethod: SeedMethod? = nil,
        teamSize: Int? = nil,
        members: [CommunityMemberRosterRow] = []
    ) {
        self.bracketId = bracketId
        self.seedMethod = seedMethod
        self.teamSize = teamSize
        self.members = members
        _bracketSeedMethod = State(initialValue: seedMethod)
        _bracketTeamSize = State(initialValue: teamSize ?? 1)
        _bracketMembers = State(initialValue: members)
    }

    var body: some View {
        VStack(spacing: 12) {
            toggleRow

            if viewMode == .bracket {
                VStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Text("Coming soon :)")
                        .font(AppFont.emptyStateTitle)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    } catch {
                        AppDebugLog.log("BracketsView: decode failed bracketId=\(bracketId) error=\(error.localizedDescription)")
                    }
                }
        }
        .task(id: bracketCommunityId) {
            await loadBracketMembersIfNeeded()
        }
        .onDisappear {
            listener?.remove()
            listener = nil
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
            NewGameLogFormView(bracketContext: context)
                .environmentObject(container)
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
                    let sortedRounds = bracketRounds.sorted(by: { $0.roundNumber < $1.roundNumber })
                    let finalRoundNumber = sortedRounds.last?.roundNumber

                    ForEach(sortedRounds, id: \.roundNumber) { round in
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

                            ForEach(Array(visibleMatches.enumerated()), id: \.element.id) { index, match in
                                BracketMatchRow(
                                    matchIndex: index,
                                    match: match,
                                    members: bracketMembers,
                                    matchById: matchById,
                                    onLogResult: { effectiveParticipantProfileIds in
                                        logResultContext = GameLogBracketContext(
                                            bracketId: bracketId,
                                            bracketMatchId: match.matchId,
                                            communityId: bracketCommunityId,
                                            participantProfileIds: effectiveParticipantProfileIds,
                                            teamSize: bracketTeamSize
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
                        .fill(isSelected ? Color.black : Color(.secondarySystemGroupedBackground))
                )
                .foregroundStyle(isSelected ? Color.white : Color.black)
        }
        .buttonStyle(.plain)
    }

    private func statusPill(text: String, isActive: Bool) -> some View {
        Text(text)
            .font(AppFont.caption)
            .foregroundStyle(isActive ? Color.black : Color(.secondaryLabel))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(isActive ? Color(.systemYellow).opacity(0.45) : Color(.tertiarySystemFill))
            )
    }

    private func shouldShowMatchInRound(_ match: BracketMatchSnapshot) -> Bool {
        // Hide round matches that are auto-advanced byes (single side, winner-only),
        // so users only see playable games in each round.
        let participants = match.participantProfileIds ?? []
        let winners = match.winnerProfileIds ?? []
        let losers = match.loserProfileIds ?? []
        let isWinnerOnlyBye = !winners.isEmpty &&
            losers.isEmpty &&
            participants.count == bracketTeamSize &&
            winners.count == bracketTeamSize
        return !isWinnerOnlyBye
    }

    private func loadBracketMembersIfNeeded() async {
        guard !bracketCommunityId.isEmpty else { return }
        if !bracketMembers.isEmpty { return }
        guard !isLoadingBracketMembers else { return }
        isLoadingBracketMembers = true
        defer { isLoadingBracketMembers = false }
        do {
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
    let onLogResult: ([String]) -> Void
    let teamSize: Int

    private var decodedParticipantProfileIds: [String] { match.participantProfileIds ?? [] }

    private var isPlaceholder: Bool { match.feederMatchIds != nil }

    /// Placeholder matches sometimes arrive with empty decoded `participantProfileIds`,
    /// but the bye-side participants can still be inferred from feeder matches that are
    /// already finalized. This lets the UI show byes without requiring the server prefill.
    private var effectiveParticipantProfileIds: [String] {
        guard isPlaceholder,
              decodedParticipantProfileIds.isEmpty,
              let feederIds = match.feederMatchIds
        else { return decodedParticipantProfileIds }

        // Preserve feeder order: feeder1 -> feeder2.
        var out: [String] = []
        var seen = Set<String>()
        for feederId in feederIds {
            guard let feeder = matchById[feederId] else { continue }
            let advancing: [String]
            if let winners = feeder.winnerProfileIds, !winners.isEmpty {
                advancing = winners
            } else if let losers = feeder.loserProfileIds, !losers.isEmpty {
                // This is a fallback (bye matches should only have winners),
                // but it keeps inference robust if the backend represents
                // advancing side via loser side instead.
                advancing = losers
            } else {
                // If the backend didn't mark the bye match as finalized yet,
                // `winnerProfileIds`/`loserProfileIds` may be missing. A bye match
                // will still contain exactly one team's participants.
                let participants = feeder.participantProfileIds ?? []
                advancing = participants.count == teamSize ? participants : []
            }
            for id in advancing where seen.insert(id).inserted {
                out.append(id)
            }
        }
        return out
    }

    private var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }

    /// Treat a match as "played" when it has either a winner or a loser side.
    /// This supports "bye matches" which may be finalized with only winners.
    private var isPlayed: Bool {
        let winners = match.winnerProfileIds ?? []
        let losers = match.loserProfileIds ?? []
        return !winners.isEmpty || !losers.isEmpty
    }

    private var canLogResult: Bool {
        !isPlayed &&
        !effectiveParticipantProfileIds.isEmpty &&
        (currentUserId != nil && effectiveParticipantProfileIds.contains(currentUserId!)) &&
        placeholderReadyToLog
    }

    /// For placeholders, only allow logging once both sides' participants are known.
    /// We treat "known" as `participantProfileIds.count == 2 * teamSize`.
    private var placeholderReadyToLog: Bool {
        if !isPlaceholder { return true }
        return effectiveParticipantProfileIds.count == 2 * teamSize
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text("Game \(matchIndex + 1)")
                    .font(AppFont.subheadlineBold)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                statusPill(text: isPlayed ? "Completed" : "Not completed", isActive: !isPlayed)
            }

            if isPlayed {
                let winners = match.winnerProfileIds ?? []
                let losers = match.loserProfileIds ?? []

                if !winners.isEmpty {
                    Text("˗ˏˋ  \(names(winners))  ˎˊ˗")
                        .font(AppFont.bodyMedium)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                }

                if !losers.isEmpty {
                    Text("Loser: \(names(losers))")
                        .font(AppFont.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            } else {
                if effectiveParticipantProfileIds.isEmpty, match.feederMatchIds != nil {
                    Text("Waiting for previous matches...")
                        .font(AppFont.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text(names(effectiveParticipantProfileIds))
                        .font(AppFont.bodyMedium)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                }

                if canLogResult {
                    Button {
                        onLogResult(effectiveParticipantProfileIds)
                    } label: {
                        Text("Log result")
                            .font(AppFont.buttonProminent)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.black)
                            )
                            .foregroundStyle(.white)
                    }
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

    private func names(_ ids: [String]) -> String {
        let mapped = members
            .filter { ids.contains($0.profileId) }
            .map { $0.displayName.isEmpty ? "Unknown" : $0.displayName }
        return mapped.isEmpty ? "—" : mapped.joined(separator: ", ")
    }

    private func statusPill(text: String, isActive: Bool) -> some View {
        Text(text)
            .font(AppFont.caption)
            .foregroundStyle(isActive ? Color.black : Color(.secondaryLabel))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(isActive ? Color(.systemYellow).opacity(0.45) : Color(.tertiarySystemFill))
            )
    }
}

private struct BracketSnapshot: Decodable {
    let communityId: String
    let seedMethod: SeedMethod?
    let status: String
    let teamSize: Int
    let rounds: [BracketRoundSnapshot]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        communityId = try c.decode(String.self, forKey: .communityId)
        status = try c.decode(String.self, forKey: .status)
        teamSize = try c.decode(Int.self, forKey: .teamSize)
        rounds = try c.decode([BracketRoundSnapshot].self, forKey: .rounds)
        if let rawSeedMethod = try c.decodeIfPresent(String.self, forKey: .seedMethod) {
            seedMethod = SeedMethod(rawValue: rawSeedMethod)
        } else {
            seedMethod = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case communityId
        case seedMethod
        case status
        case teamSize
        case rounds
    }
}

private struct BracketRoundSnapshot: Decodable {
    let roundNumber: Int
    let matches: [BracketMatchSnapshot]
}

private struct BracketMatchSnapshot: Decodable, Identifiable {
    let matchId: String
    let roundNumber: Int
    /// Can be missing or null until a later round is activated.
    let participantProfileIds: [String]?
    let winnerProfileIds: [String]?
    let loserProfileIds: [String]?
    let feederMatchIds: [String]?

    var id: String { matchId }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        matchId = try c.decode(String.self, forKey: .matchId)
        roundNumber = try c.decode(Int.self, forKey: .roundNumber)
        participantProfileIds = try c.decodeIfPresent([String].self, forKey: .participantProfileIds)
        winnerProfileIds = try c.decodeIfPresent([String].self, forKey: .winnerProfileIds)
        loserProfileIds = try c.decodeIfPresent([String].self, forKey: .loserProfileIds)
        feederMatchIds = try c.decodeIfPresent([String].self, forKey: .feederMatchIds)
    }

    enum CodingKeys: String, CodingKey {
        case matchId
        case roundNumber
        case participantProfileIds
        case winnerProfileIds
        case loserProfileIds
        case feederMatchIds
    }
}

extension GameLogBracketContext: Identifiable {
    var id: String {
        "\(bracketId)|\(bracketMatchId)"
    }
}
