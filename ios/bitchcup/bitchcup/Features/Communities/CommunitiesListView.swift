import SwiftUI

/// Placeholder list of joined communities (profile menu → View communities). T06 will load from Firestore.
struct CommunitiesListView: View {
    var body: some View {
        List {
            Section {
                Text("No communities yet")
                    .foregroundStyle(.secondary)
            } footer: {
                Text("Communities you join will appear here. Use “Create/Join a Community” on the home tab to create or join.")
            }
        }
        .navigationTitle("Create/Join a Community")
        .navigationBarTitleDisplayMode(.inline)
    }
}
