import SwiftUI

struct ManualSeedView: View {
    let bracketId: String
    let teamSize: Int
    let members: [CommunityMemberRosterRow]

    @EnvironmentObject private var container: DependencyContainer
    @Environment(\.dismiss) private var dismiss

    /// `slots[teamIndex][slotInTeam]` — profileId or nil (same shape as server `teams`).
    @State private var slots: [[String?]]
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var onFinalized: () -> Void

    init(
        bracketId: String,
        teamSize: Int,
        members: [CommunityMemberRosterRow],
        onFinalized: @escaping () -> Void
    ) {
        self.bracketId = bracketId
        self.teamSize = teamSize
        self.members = members
        self.onFinalized = onFinalized
        let sizes = Self.expectedTeamSizes(
            participantCount: members.count,
            teamSize: teamSize
        )
        _slots = State(
            initialValue: sizes.map { Array(repeating: nil as String?, count: $0) }
        )
    }

    private var assignedProfileIds: Set<String> {
        Set(slots.flatMap { $0 }.compactMap { $0 })
    }

    private var unassignedMembers: [CommunityMemberRosterRow] {
        members.filter { !assignedProfileIds.contains($0.profileId) }
    }

    private var allSlotsFilled: Bool {
        slots.allSatisfy { row in row.allSatisfy { $0 != nil } }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Text(
                    "Team 1 is the top bracket spot (bye preference). " +
                    "Choose league members for each slot."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)

                List {
                    ForEach(Array(slots.enumerated()), id: \.offset) { teamIndex, row in
                        Section("Team \(teamIndex + 1)") {
                            ForEach(Array(row.enumerated()), id: \.offset) { slotIndex, _ in
                                slotRow(teamIndex: teamIndex, slotIndex: slotIndex)
                            }
                        }
                    }

                    if !unassignedMembers.isEmpty {
                        Section("Not yet assigned") {
                            ForEach(unassignedMembers) { member in
                                Text(member.displayName.isEmpty ? "Unknown" : member.displayName)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                }

                Button {
                    Task { await finalize() }
                } label: {
                    HStack {
                        if isSubmitting {
                            ProgressView().scaleEffect(0.8)
                        }
                        Text(isSubmitting ? "Finalizing..." : "Confirm teams")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.black)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(isSubmitting || !allSlotsFilled)
                .padding()
            }
            .navigationTitle("Assign teams")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSubmitting)
                }
            }
        }
    }

    @ViewBuilder
    private func slotRow(teamIndex: Int, slotIndex: Int) -> some View {
        let profileId = slots[teamIndex][slotIndex]
        HStack {
            if let profileId {
                Text(displayName(for: profileId))
                    .font(.body)
                Spacer()
                Button("Remove") {
                    slots[teamIndex][slotIndex] = nil
                }
                .font(.subheadline)
                .foregroundStyle(.red)
            } else {
                Menu {
                    ForEach(unassignedMembers) { member in
                        Button(
                            member.displayName.isEmpty ? "Unknown" : member.displayName
                        ) {
                            slots[teamIndex][slotIndex] = member.profileId
                        }
                    }
                } label: {
                    HStack {
                        Text("Choose player")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func displayName(for profileId: String) -> String {
        guard let m = members.first(where: { $0.profileId == profileId }) else {
            return "Unknown"
        }
        return m.displayName.isEmpty ? "Unknown" : m.displayName
    }

    private func finalize() async {
        guard allSlotsFilled else {
            errorMessage = "Fill every team slot before confirming."
            return
        }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        let teams: [[String]] = slots.map { row in
            row.map { $0! }
        }
        do {
            try await container.bracketService.finalizeManualBracket(
                bracketId: bracketId,
                teams: teams
            )
            onFinalized()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Matches server `expectedTeamSizes` / greedy `chunkIntoTeams`.
    private static func expectedTeamSizes(
        participantCount: Int,
        teamSize: Int
    ) -> [Int] {
        var sizes: [Int] = []
        var remaining = participantCount
        while remaining > 0 {
            let n = min(teamSize, remaining)
            sizes.append(n)
            remaining -= n
        }
        return sizes
    }
}
