import SwiftUI

struct CommunityDetailView: View {
    let communityId: String

    @EnvironmentObject private var container: DependencyContainer
    @State private var communityName: String = ""
    @State private var members: [(profileId: String, displayName: String)] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                LoadingView(message: "Loading league...")
            } else if let error = errorMessage {
                ErrorView(message: error) {
                    Task { await load() }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {

                        // Members section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Members (\(members.count))")
                                .font(.headline)

                            if members.isEmpty {
                                Text("No members yet.")
                                    .foregroundStyle(.secondary)
                                    .font(.subheadline)
                            } else {
                                ForEach(members, id: \.profileId) { member in
                                    HStack {
                                        Circle()
                                            .frame(width: 36, height: 36)
                                            .foregroundStyle(Color(.systemGray4))
                                        Text(member.displayName.isEmpty ? "Unknown" : member.displayName)
                                            .font(.subheadline)
                                        Spacer()
                                    }
                                }
                            }
                        }

                        // Placeholder sections
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recent Games")
                                .font(.headline)
                            Text("Game logs will appear here (T07).")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Bracket")
                                .font(.headline)
                            Text("Bracket entry will appear here (T10).")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
            }
        }
        .navigationTitle(communityName.isEmpty ? "League" : communityName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let db = AppFirestore.db()
            let communityDoc = try await db.collection("communities").document(communityId).getDocument()
            communityName = communityDoc.data()?["name"] as? String ?? "League"
            members = try await container.communityService.fetchMembers(communityId: communityId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
