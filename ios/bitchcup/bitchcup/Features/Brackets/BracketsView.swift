import SwiftUI
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
                    guard let snapshot, snapshot.exists, let data = try? snapshot.data(as: BracketSnapshot.self) else {
                        return
                    }
                    bracketStatus = data.status
                    if data.status != "DRAFT" {
                        isFinalized = true
                    }
                    bracketRounds = data.rounds
                    bracketCommunityId = data.communityId
                    bracketTeamSize = data.teamSize
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
                onFinalized: { isFinalized = true }
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
                        BracketMatchRow(match: match, members: members) {
                            logResultContext = GameLogBracketContext(
                                bracketId: bracketId,
                                bracketMatchId: match.matchId,
                                communityId: bracketCommunityId,
                                participantProfileIds: match.participantProfileIds,
                                teamSize: bracketTeamSize
                            )
                        }
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
    let onLogResult: () -> Void

    private var isPlayed: Bool { match.winnerProfileIds != nil && match.loserProfileIds != nil }
    private var canLogResult: Bool { !isPlayed && !match.participantProfileIds.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isPlayed {
                Text("Finalized")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isPlayed, let winners = match.winnerProfileIds, let losers = match.loserProfileIds {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Winners: \(names(winners))")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Text("Losers: \(names(losers))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(names(match.participantProfileIds))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            if canLogResult {
                Button {
                    onLogResult()
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
    let participantProfileIds: [String]
    let winnerProfileIds: [String]?
    let loserProfileIds: [String]?
    let feederMatchIds: [String]?

    var id: String { matchId }
}

extension GameLogBracketContext: Identifiable {
    var id: String {
        "\(bracketId)|\(bracketMatchId)"
    }
}
