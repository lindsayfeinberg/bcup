import SwiftUI

struct JoinCommunityFlowView: View {
    @EnvironmentObject private var container: DependencyContainer
    @State private var inviteCode = ""
    @State private var isWorking = false
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
                        defer { isWorking = false }
                        do {
                            let id = try await container.communityService.joinCommunity(inviteCode: inviteCode)
                            onSuccess(id)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
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
    }
}
