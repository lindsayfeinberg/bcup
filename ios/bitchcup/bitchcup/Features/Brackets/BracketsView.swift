import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct BracketsView: View {
    let bracketId: String
    let seedMethod: SeedMethod
    let teamSize: Int
    let members: [CommunityMemberRosterRow]

    @EnvironmentObject private var container: DependencyContainer
    @State private var bracketStatus: String = "DRAFT"
    @State private var bracketRounds: [BracketRoundSnapshot] = []
    @State private var bracketCommunityId: String = ""
    @State private var bracketTeamSize: Int = 1
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

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 48))
                .foregroundStyle(.yellow)

            Text("Bracket Created!")
                .font(.title2)
                .fontWeight(.bold)

            if seedMethod == .manual && !isFinalized {
                Text("Assign players to each team to activate this bracket.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button {
                    showManualSeed = true
                } label: {
                    Text("Assign teams")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.black)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(.horizontal)
            } else {
                if bracketStatus == "ACTIVE" {
                    bracketMatchesSection
                } else if bracketStatus == "COMPLETE" {
                    bracketMatchesSection
                        .overlay(
                            Text("Complete")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6),
                            alignment: .topTrailing
                        )
                } else {
                    Text("Bracket status: \(bracketStatus)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if seedMethod == .random {
                    Text("Players were randomly assigned to bracket positions (fixed for this bracket).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }

            Text("ID: \(bracketId)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        
                        print("""
                            [BracketsView] decoded OK
                            bracketId=\(bracketId)
                            status=\(data.status)
                            teamSize=\(data.teamSize)
                            roundsCount=\(data.rounds.count)
                            round1MatchIds=\(data.rounds.first(where: { $0.roundNumber == 1 })?.matches.map { $0.matchId } ?? [])
                            round1WinnerProfileCounts=\(data.rounds
                                .first(where: { $0.roundNumber == 1 })?.matches
                                .map { ($0.matchId, ($0.winnerProfileIds ?? []).count) } ?? [])
                            round2PlaceholderMatchIds=\(data.rounds
                                .first(where: { $0.roundNumber == 2 })?.matches
                                .filter { $0.feederMatchIds != nil }
                                .map { $0.matchId } ?? [])
                            round2PlaceholderParticipantProfileIds=\(data.rounds
                                .first(where: { $0.roundNumber == 2 })?.matches
                                .filter { $0.feederMatchIds != nil }
                                .map { ($0.matchId, $0.participantProfileIds ?? []) } ?? [])
                        """)
                        
                        bracketStatus = data.status
                        if data.status != "DRAFT" {
                            isFinalized = true
                        }
                        bracketRounds = data.rounds
                        bracketCommunityId = data.communityId
                        bracketTeamSize = data.teamSize
                    } catch {
                        // Temporary diagnostics: if decoding fails, we want to know which key shape
                        // is causing the issue (bye match often differs: winner-only).
                        let bracketIdLocal = bracketId
                        print("""
                        [BracketsView] FAILED to decode BracketSnapshot
                        bracketId=\(bracketIdLocal)
                        error=\(error)
                        """)

                        if let decoding = error as? DecodingError {
                            switch decoding {
                            case .dataCorrupted(let context):
                                print("[BracketsView] dataCorrupted codingPath=\(context.codingPath) debug=\(context.debugDescription)")
                            case .keyNotFound(let key, let context):
                                print("[BracketsView] keyNotFound key=\(key) codingPath=\(context.codingPath) debug=\(context.debugDescription)")
                            case .typeMismatch(_, let context):
                                print("[BracketsView] typeMismatch codingPath=\(context.codingPath) debug=\(context.debugDescription)")
                            case .valueNotFound(_, let context):
                                print("[BracketsView] valueNotFound codingPath=\(context.codingPath) debug=\(context.debugDescription)")
                            @unknown default:
                                print("[BracketsView] DecodingError (unknown case)")
                            }
                        }

                        if let raw = snapshot.data() {
                            print("[BracketsView] Raw top-level keys=\(Array(raw.keys).sorted())")

                            if let roundsRaw = raw["rounds"] {
                                print("[BracketsView] Raw rounds type=\(type(of: roundsRaw))")

                                if let roundsArray = roundsRaw as? [[String: Any]] {
                                    print("[BracketsView] Raw rounds array count=\(roundsArray.count)")
                                } else if let roundsArray = roundsRaw as? [Any] {
                                    print("[BracketsView] Raw rounds array count=\(roundsArray.count)")
                                } else {
                                    // Don't spam; just show type if it isn't a simple array.
                                }
                            }
                        }
                    }
                }
        }
        .onDisappear {
            listener?.remove()
            listener = nil
        }
        .sheet(isPresented: $showManualSeed) {
            ManualSeedView(
                bracketId: bracketId,
                teamSize: teamSize,
                members: members,
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
    private var bracketMatchesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(bracketRounds.sorted(by: { $0.roundNumber < $1.roundNumber }), id: \.roundNumber) { round in
                VStack(alignment: .leading, spacing: 8) {
                    Text("Round \(round.roundNumber)")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    ForEach(round.matches) { match in
                        BracketMatchRow(
                            match: match,
                            members: members,
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
                .padding(.horizontal)
            }
        }
    }
}

private struct BracketMatchRow: View {
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
        VStack(alignment: .leading, spacing: 8) {
            if isPlayed {
                Text("Finalized")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isPlayed {
                let winners = match.winnerProfileIds ?? []
                let losers = match.loserProfileIds ?? []
                VStack(alignment: .leading, spacing: 4) {
                    if !winners.isEmpty {
                        Text("Winners: \(names(winners))")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                    }
                    if !losers.isEmpty {
                        Text("Losers: \(names(losers))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                if effectiveParticipantProfileIds.isEmpty, match.feederMatchIds != nil {
                    Text("Waiting for previous matches...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text(names(effectiveParticipantProfileIds))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
            }

            if canLogResult {
                Button {
                    onLogResult(effectiveParticipantProfileIds)
                } label: {
                    Text("Log result")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.black)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func names(_ ids: [String]) -> String {
        let mapped = members
            .filter { ids.contains($0.profileId) }
            .map { $0.displayName.isEmpty ? "Unknown" : $0.displayName }
        return mapped.isEmpty ? "—" : mapped.joined(separator: ", ")
    }
}

private struct BracketSnapshot: Decodable {
    let communityId: String
    let status: String
    let teamSize: Int
    let rounds: [BracketRoundSnapshot]
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
