import SwiftUI

struct CreateCommunityFlowView: View {
    @EnvironmentObject private var container: DependencyContainer
    @EnvironmentObject private var navigator: CommunitiesNavigator
    @State private var name = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var createdCommunity: (communityId: String, inviteCode: String, inviteLink: String)?

    let onSuccess: (String, String, String) -> Void

    var body: some View {
        if let community = createdCommunity {
            InviteView(
                communityId: community.communityId,
                inviteCode: community.inviteCode,
                inviteLink: community.inviteLink
            ) {
                navigator.navigateToDetail(communityId: community.communityId)
            }
        } else {
            Form {
                Section {
                    TextField("Community name", text: $name)
                } footer: {
                    Text("Creates the community on the server and adds you as the first member.")
                }

                Section {
                    Button("Create community") {
                        guard !isWorking else { return }
                        Task {
                            isWorking = true
                            errorMessage = nil
                            defer { isWorking = false }
                            do {
                                let result = try await container.communityService.createCommunity(name: name)
                                await MainActor.run {
                                    createdCommunity = (result.communityId, result.inviteCode, result.inviteLink)
                                }
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    }
                    .disabled(isWorking || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Create")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Could not create", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }
}
