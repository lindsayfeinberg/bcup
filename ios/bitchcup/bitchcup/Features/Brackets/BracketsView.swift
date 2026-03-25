import SwiftUI

struct BracketsView: View {
    let bracketId: String
    let seedMethod: SeedMethod
    let teamSize: Int
    let members: [CommunityMemberRosterRow]

    @EnvironmentObject private var container: DependencyContainer
    @State private var showManualSeed = false
    @State private var isFinalized = false

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
                Text("Bracket is active.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if seedMethod == .random {
                    Text("Players were randomly assigned to bracket positions (fixed for this bracket).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Text("Rounds and match UI coming in T10.7+")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("ID: \(bracketId)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Bracket")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showManualSeed) {
            ManualSeedView(
                bracketId: bracketId,
                teamSize: teamSize,
                members: members,
                onFinalized: { isFinalized = true }
            )
            .environmentObject(container)
        }
    }
}
