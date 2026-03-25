import SwiftUI
import FirebaseFirestore

/// Intermediate full-screen flow for `SeedMethod.manual`.
/// Shows `ManualSeedView`, then waits for the bracket status to become ACTIVE/COMPLETE
/// before forwarding to the unified `BracketsView` screen.
struct ManualBracketSeedingFlowView: View {
    let bracketId: String
    let teamSize: Int
    let members: [CommunityMemberRosterRow]
    let onReady: () -> Void

    @EnvironmentObject private var container: DependencyContainer

    @State private var listener: ListenerRegistration?
    @State private var didConfirmTeams = false
    @State private var didNavigate = false
    @State private var latestStatus: String = "DRAFT"

    var body: some View {
        ManualSeedView(
            bracketId: bracketId,
            teamSize: teamSize,
            members: members
        ) {
            didConfirmTeams = true
            // If the bracket already moved out of DRAFT (race condition),
            // navigate immediately rather than waiting for another snapshot.
            if !didNavigate && latestStatus != "DRAFT" {
                didNavigate = true
                listener?.remove()
                listener = nil
                onReady()
            }
        }
        .environmentObject(container)
        .onAppear {
            startWatchingBracketStatus()
        }
        .onDisappear {
            listener?.remove()
            listener = nil
        }
    }

    private func startWatchingBracketStatus() {
        guard listener == nil, !didNavigate else { return }

        listener = AppFirestore.db()
            .collection("brackets")
            .document(bracketId)
            .addSnapshotListener { snapshot, _ in
                guard let status = snapshot?.data()?["status"] as? String else { return }
                Task { @MainActor in
                    latestStatus = status
                    guard didConfirmTeams else { return }
                    guard status != "DRAFT" else { return }
                    guard !didNavigate else { return }

                    listener?.remove()
                    listener = nil

                    didNavigate = true
                    onReady()
                }
            }
    }
}

