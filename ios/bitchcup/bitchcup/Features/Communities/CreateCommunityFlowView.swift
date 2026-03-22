import SwiftUI

struct CreateCommunityFlowView: View {
    @EnvironmentObject private var container: DependencyContainer
    @State private var name = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    let onSuccess: (String) -> Void

    var body: some View {
        Form {
            Section {
                TextField("Community name", text: $name)
            } footer: {
                Text("Creates the community on the server and adds you as the first member.")
            }

            Section {
                Button("Create community") {
                    Task {
                        isWorking = true
                        errorMessage = nil
                        defer { isWorking = false }
                        do {
                            let result = try await container.communityService.createCommunity(name: name)
                            onSuccess(result.communityId)
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
