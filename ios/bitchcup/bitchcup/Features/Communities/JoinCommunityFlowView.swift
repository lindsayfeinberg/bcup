import SwiftUI

struct JoinCommunityFlowView: View {
    @EnvironmentObject private var container: DependencyContainer
    @State private var inviteCode = ""
    @State private var isWorking = false
    @State private var showJoinConfirmation = false
    @State private var pendingPreview: CommunityJoinPreview?
    @State private var errorMessage: String?
    let onSuccess: (String) -> Void

    var body: some View {
        Form {
            Section {
                TextField("Invite code", text: $inviteCode)
                    .textInputAutocapitalization(.characters)
            } footer: {
                Text("Communities are limited to 350 members. If the community is full, you cannot join.")
            }

            Section {
                Button("Join community") {
                    Task {
                        isWorking = true
                        errorMessage = nil
                        do {
                            let preview = try await container.communityService.previewJoinCommunity(inviteCode: inviteCode)
                            pendingPreview = preview
                            showJoinConfirmation = true
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                        isWorking = false
                    }
                }
                .disabled(isWorking || inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("Join")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Could not join", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            "Join community",
            isPresented: $showJoinConfirmation,
            titleVisibility: .visible
        ) {
            Button("Join") {
                Task {
                    isWorking = true
                    errorMessage = nil
                    do {
                        let id = try await container.communityService.joinCommunity(inviteCode: inviteCode)
                        showJoinConfirmation = false
                        onSuccess(id)
                    } catch {
                        errorMessage = error.localizedDescription
                        showJoinConfirmation = false
                    }
                    isWorking = false
                }
            }
            Button("Cancel", role: .cancel) {
                showJoinConfirmation = false
            }
        } message: {
            let name = pendingPreview?.name ?? "this"
            let count = pendingPreview?.memberCount ?? 0
            return Text("Do you want to join \(name) community with \(count) members?")
        }
    }
}
